-- ==========================================================
-- Sysbench Time-Series Benchmark Script (Prepare + Run)
-- ==========================================================
-- OLTP
-- CRUD operations: 40% C, 30% R, 20% U, and 10% D.
-- Record sizes should be in the range of 4KB to 64KB 
-- Pick guids from a list of pre-generated guids to simulate realistic access patterns.
-- Custom size of the startup prep table.
-- CSV Logging of detailed per-transaction latencies.
-- The length should vary 
-- not sure if it will make any difference in performance, 
-- but we'll eventually use TIMESTAMP, not TIMESTAMPZ (we don't --
-- want to store time zone data; only ever UTC)
-- "guid" needs to be a string; this is what I'm calling "key" 
-- (field names don't really matter for testing, and you can use 
-- a UUID for the key, but it should be stored as a string to most 
-- closely match the real record)
-- "prefix" is what I'm calling "instance"; again names don't matter
-- the PRIMARY KEY should be prefix, guid (or instance, key)
-- what I don't know about PG is whether declaring PRIMARY KEY 
-- results in a queryable index or if it just prevents duplicates; 
-- also, what kind of index should be used?
-- TSDB
-- - same with TIMEZONE
-- - same with "guid"
-- - same with "prefix"
-- - the PRIMARY KEY should be prefix, guid, time (or index, key, time)
--   same question here about whether this results in an index
-- The variable-length field should be JSONB
-- I have a note about using compression on the JSONB field. I believe the syntax is this (after the field declaration): STORAGE MAIN COMPRESSION lz4

-- TASKS -
-- TIMESTAMPTZ for time field should be TIMESTAMP where all times are in UTC : OK
-- GUID field should be just a varchar/string field : OK
-- The data field should be JSONB with variable length (100B-1KB) : OK
-- Create a pool of pre-generated GUIDs (say 1000) and : OK
-- Have a flag for compression - STORAGE MAIN COMPRESSION lz4  OK


-- ==========================================================
-- Questions:
-- 1. I am using time resolution of seconds (upto 2 decimals). Is that okay?
-- 2. After creating the guid pool, how should i oscillate between guids during the run phase?
-- 3. How long can the key be - I have it limited to 64 chars now.
-- 4. Do i need multiple sensors per record? Right now I have one sensor with multiple fields.
-- 5. If compression is enabled, TimescaleDB won’t automatically convert a table into a hypertable.
      -- Won’t be chunked by time.
      -- Won’t use Timescale’s time-based optimizations (like chunk pruning or parallel compression).
      -- Will behave exactly like a regular PostgreSQL tab

-- 6. Can I introduce time skew when generating timestamps? Right now I am just using os.date in UTC.
-- 7. Should I do last 6 months, last 1 year, or random timestamps?
-- 8. Do I simulate some GUIDs to be more active than others?
-- ==========================================================


-- ==========================================================

sysbench.cmdline.options = {
  table_name       = {"Target table name", "ts_v00"},
  prefix           = {"Prefix tag value", "TS"},
  table_size       = {"Number of rows to insert during prepare", 10000},
  batch_size       = {"Rows per batch insert during run", 100},
  total_rows       = {"Total rows per thread to insert during run", 10000},
  verbose          = {"Print every batch progress", false},
  n_guids          = {"Number of GUIDs to generate or load", 1000},
  csv_path         = {"Path to save or load the GUID CSV file", "./guid_pool.csv"},
  use_compression  = {"Enable compression (true/false)", false},
  compression_algo = {"Compression algorithm (lz4, pglz, zstd)", "lz4"},
}
-- ==========================================================
-- Utility: Generate a valid UUID (Version 4)
-- ==========================================================
local function gen_uuid()
  local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
  return string.gsub(template, '[xy]', function(c)
    local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
    return string.format('%x', v)
  end)
end

-- ==========================================================
-- Save GUID pool to CSV (one per line)
-- ==========================================================
local function save_guid_pool_to_csv(filename, guids)
  local f, err = io.open(filename, "w")
  assert(f, "❌ Cannot open " .. filename .. ": " .. tostring(err))
  for _, g in ipairs(guids) do
    f:write(g .. "\n")
  end
  f:close()
  print(string.format("💾 Saved %d GUIDs to %s", #guids, filename))
end


-- ==========================================================
-- Generate realistic multi-sensor JSON payload (100B–1KB)
-- One random sensor per record, with all its fields
-- ==========================================================
local function gen_json_payload()
  -- Target payload size variation
  local target = sysbench.rand.uniform(300, 1200)
  local pad_len = target - 150
  if pad_len < 0 then pad_len = 0 end
  local pad = sysbench.rand.string(string.rep("x", pad_len))

  -- Define available sensors and their readings
  local sensors = {
    {
      id = "BME280",
      fields = {
        {name = "temperature", unit = "C",   min = 20.0,  max = 35.0},
        {name = "pressure",    unit = "hPa", min = 950.0, max = 1050.0},
        {name = "humidity",    unit = "%",   min = 20.0,  max = 80.0}
      }
    },
    {
      id = "SCD41",
      fields = {
        {name = "co2", unit = "ppm", min = 400.0, max = 2000.0}
      }
    },
    {
      id = "SHT31",
      fields = {
        {name = "temperature", unit = "C", min = 18.0, max = 32.0},
        {name = "humidity",    unit = "%", min = 25.0, max = 85.0}
      }
    },
    {
      id = "TGS2611",
      fields = {
        {name = "ch4", unit = "ppm", min = 1.5, max = 3.5}
      }
    },
    {
      id = "LPS22HB",
      fields = {
        {name = "pressure", unit = "hPa", min = 950.0, max = 1050.0}
      }
    }
  }

  -- Randomly pick one sensor type
  local sensor = sensors[sysbench.rand.default(1, #sensors)]

  -- Generate readings for all fields of that sensor
  local readings = {}
  for _, f in ipairs(sensor.fields) do
    local value = sysbench.rand.uniform(f.min, f.max)
    table.insert(readings, string.format(
      '{"field":"%s","value":%.3f,"unit":"%s"}',
      f.name, value, f.unit
    ))
  end

  -- Assemble JSON payload for this sensor
  local json_str = string.format(
    '{"sensor_id":"%s","readings":[%s],"extra":"%s"}',
    sensor.id,
    table.concat(readings, ","),
    pad
  )

  return json_str
end

-- ==========================================================
-- Create the time-series table if not exists
-- ==========================================================
function create_table(con)
  local table_name = sysbench.opt.table_name
  print(string.format("Creating table if not exists: %s", table_name))

  local create_sql = string.format([[
    CREATE TABLE IF NOT EXISTS %s (
      time     TIMESTAMP(2) NOT NULL,
      prefix   VARCHAR(4) NOT NULL,
      guid     VARCHAR(64) NOT NULL,
      data     JSONB,
      PRIMARY KEY (time, prefix, guid)
    );
  ]], table_name)

  -- ✅ First, create the table
  assert(con:query(create_sql))
  print("Table created successfully.")

  -- ✅ Optional: apply compression after creation
  if sysbench.opt.use_compression then
    print(string.format("Applying compression (%s) to table: %s",
                        sysbench.opt.compression_algo, table_name))
    local ok1, err1 = pcall(function()
      con:query(string.format(
        "ALTER TABLE %s ALTER COLUMN data SET STORAGE MAIN;", table_name))
    end)
    if not ok1 then
      print("⚠️  Warning: could not set STORAGE MAIN: " .. tostring(err1))
    end

    local ok2, err2 = pcall(function()
      con:query(string.format(
        "ALTER TABLE %s ALTER COLUMN data SET COMPRESSION %s;",
        table_name, sysbench.opt.compression_algo))
    end)
    if not ok2 then
      print("⚠️  Warning: compression setting failed: " .. tostring(err2))
    else
      print(string.format("✅ Compression applied using %s", sysbench.opt.compression_algo))
    end
  end
end



-- ==========================================================
-- create_guid_pool(n)
-- Generates a diverse set of IoT-style identifiers:
-- UUID, MAC (Wi-Fi/Ethernet), BLE address, LoRaWAN DevEUI,
-- Zigbee IEEE address, IMEI (cellular), Vendor-prefixed IDs.
-- ==========================================================
function create_guid_pool(n)
  local pool = {}

  -- --- Helper Generators ---

  local function gen_uuid()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function(c)
      local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
      return string.format('%x', v)
    end)
  end

  local function gen_mac()
    local mac = {}
    for _ = 1, 6 do
      table.insert(mac, string.format("%02X", math.random(0, 255)))
    end
    return table.concat(mac, ":")
  end

  local function gen_ble_addr()
    local ble = {}
    for _ = 1, 6 do
      table.insert(ble, string.format("%02X", math.random(0, 255)))
    end
    return table.concat(ble, "-")
  end

  local function gen_lorawan_eui()
    local eui = {}
    for _ = 1, 8 do
      table.insert(eui, string.format("%02X", math.random(0, 255)))
    end
    return table.concat(eui)
  end

  local function gen_zigbee_ieee()
    local ieee = {}
    for _ = 1, 8 do
      table.insert(ieee, string.format("%02X", math.random(0, 255)))
    end
    return table.concat(ieee, ":")
  end

  local function gen_imei()
    local imei = {}
    for _ = 1, 15 do
      table.insert(imei, math.random(0, 9))
    end
    return table.concat(imei)
  end

  local function gen_vendor_id()
    local vendors = {
      "RAK",        -- LoRaWAN gateways and modules
      "NORDIC",     -- BLE/Thread chipsets
      "SENSEAIR",   -- Gas sensors
      "TEKTELIC",   -- Industrial IoT nodes
      "KERLINK",    -- LoRa gateways
      "ST",         -- STM32/LoRa chips
      "OSPREY",     -- Generic custom hardware tag
    }
    return string.format("%s-%04X", vendors[math.random(#vendors)], math.random(0, 0xFFFF))
  end

  -- --- Main Pool Generation Loop ---
  for i = 1, n do
    local id_type = sysbench.rand.uniform(1, 7)
    local id

    if id_type == 1 then
      id = gen_uuid()                          -- UUID (app/cloud IDs)
    elseif id_type == 2 then
      id = gen_mac()                           -- Wi-Fi / Ethernet MAC
    elseif id_type == 3 then
      id = gen_ble_addr()                      -- BLE device address
    elseif id_type == 4 then
      id = gen_lorawan_eui()                   -- LoRaWAN DevEUI
    elseif id_type == 5 then
      id = gen_zigbee_ieee()                   -- Zigbee IEEE 64-bit addr
    elseif id_type == 6 then
      id = gen_imei()                          -- Cellular IMEI
    else
      id = gen_vendor_id()                     -- Vendor-based device tag
    end

    table.insert(pool, id)
  end

  print(string.format("✅ Generated %d mixed IoT-style IDs", #pool))
  return pool
end


-- ==========================================================
-- Prepare Phase — Bulk Insert
-- This version uses a pre-generated GUID pool
-- and cycles through it in random order
-- ==========================================================

function prepare()
  local csv_path   = sysbench.opt.csv_path or "guid_pool.csv"
  local n_guids    = sysbench.opt.n_guids or 1000
  local table_name = sysbench.opt.table_name
  local prefix_val = sysbench.opt.prefix
  local total_rows = sysbench.opt.table_size
  local batch_size = sysbench.opt.batch_size

  print("Connecting to PostgreSQL...")
  local con = sysbench.sql.driver():connect()
  create_table(con)

  -- ✅ Generate and save GUID pool
  guid_pool = create_guid_pool(n_guids)
  save_guid_pool_to_csv(csv_path, guid_pool)

  print(string.format("=== Prepare phase started for table: %s ===", table_name))
  print(string.format("Total rows: %d | GUIDs: %d | Batch size: %d", total_rows, #guid_pool, batch_size))

  -- Helper to shuffle GUID list in-place (Fisher–Yates)
  local function shuffle(tbl)
    for i = #tbl, 2, -1 do
      local j = math.random(i)
      tbl[i], tbl[j] = tbl[j], tbl[i]
    end
  end

  local values   = {}
  local inserted = 0
  local round    = 0

  while inserted < total_rows do
    round = round + 1
    shuffle(guid_pool)
    print(string.format("🔄 Round %d – inserting for %d GUIDs (random order)", round, #guid_pool))

    for _, guid in ipairs(guid_pool) do
      if inserted >= total_rows then break end

      local now = string.format(
        "%s.%02d",
        os.date("!%Y-%m-%d %H:%M:%S"),
        math.floor((os.clock() * 100) % 100)
      )
      local json_str = gen_json_payload()

      table.insert(values, string.format(
        "('%s','%s','%s','%s'::jsonb)", now, prefix_val, guid, json_str
      ))
      inserted = inserted + 1

      if (#values == batch_size or inserted == total_rows) then
        local sql = string.format(
          "INSERT INTO %s (time, prefix, guid, data) VALUES %s",
          table_name, table.concat(values, ",")
        )
        local ok, err = pcall(function() con:query(sql) end)
        if not ok then
          print(string.format("❌ Batch failed at row %d: %s", inserted, tostring(err)))
        end
        values = {}
      end
    end

    print(string.format("✅ Round %d complete — total inserted so far: %d / %d", round, inserted, total_rows))
  end

  print(string.format("🎯 Prepare phase completed (%d total rows) across %d rounds.", inserted, round))
  con:disconnect()
end



-- ==========================================================
-- Run Phase — Continuous Write Benchmark
-- ==========================================================
function thread_init()
  math.randomseed(os.time() + sysbench.tid) -- Seed RNG per thread
  drv = sysbench.sql.driver()
  con = drv:connect()
  table_name = sysbench.opt.table_name
  prefix_val = sysbench.opt.prefix
  batch_size = sysbench.opt.batch_size
  total_rows = sysbench.opt.total_rows
  verbose = sysbench.opt.verbose

  -- ✅ Load GUIDs once per thread
  guid_pool = {}
  for line in io.lines(sysbench.opt.csv_path) do
    table.insert(guid_pool, line)
  end

  print(string.format("[Thread %d] Initialized (batch=%d, total=%d)",
                      sysbench.tid, batch_size, total_rows))
end

function event()
  local values = {}

  -- 1️⃣ Shuffle the GUID pool for this batch
  local function shuffle(tbl)
    for i = #tbl, 2, -1 do
      local j = math.random(i)
      tbl[i], tbl[j] = tbl[j], tbl[i]
    end
  end

  shuffle(guid_pool)

  -- 2️⃣ Iterate through GUIDs up to batch_size
  local inserted_batch = 0
  for i = 1, math.min(batch_size, #guid_pool) do
    local guid = guid_pool[i]

    local now = string.format(
      "%s.%02d",
      os.date("!%Y-%m-%d %H:%M:%S"),
      math.floor((os.clock() * 100) % 100)
    )

    local json_str = gen_json_payload()

    table.insert(values, string.format(
      "('%s','%s','%s','%s'::jsonb)", now, prefix_val, guid, json_str
    ))
    inserted_batch = inserted_batch + 1
  end

  -- 3️⃣ Combine and execute insert
  local sql = string.format(
    "INSERT INTO %s (time, prefix, guid, data) VALUES %s",
    table_name, table.concat(values, ",")
  )

  local ok, err = pcall(function() con:query(sql) end)
  if not ok then
    print(string.format("[Thread %d] ❌ Batch insert failed: %s", sysbench.tid, tostring(err)))
  elseif verbose then
    print(string.format("[Thread %d] ✅ Inserted %d rows for shuffled GUIDs", sysbench.tid, inserted_batch))
  end
end


function thread_done()
  con:disconnect()
end

-- ==========================================================
-- Cleanup Phase
-- ==========================================================
function cleanup()
  local table_name = sysbench.opt.table_name
  print("Connecting to PostgreSQL for cleanup...")
  local con = sysbench.sql.driver():connect()
  print(string.format("Dropping table: %s", table_name))
  con:query(string.format("DROP TABLE IF EXISTS %s;", table_name))
  print("Cleanup completed.")
  con:disconnect()
end