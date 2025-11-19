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
-- 9. Why is no time included in the primary key for the OLTP schema?
-- 10 Do I need seperate GUID pools for oltp and tsdb tests?
-- ==========================================================


-- ==========================================================

sysbench.cmdline.options = {
  table_name         = {"Target table name", "ts_v00"},
  prefix             = {"Prefix tag value", "TS"},
  table_size         = {"Number of rows to insert during prepare", 10000},
  batch_size         = {"Rows per batch insert during run", 100},  
  total_rows         = {"Total rows per thread to insert during run", 10000},
  verbose            = {"Print every batch progress", false},
  n_guids            = {"Number of GUIDs to generate or load", 1000},
  csv_path           = {"Path to save or load the GUID CSV file", "./guids/oltp.csv"},
  use_compression    = {"Enable compression (true/false)", false},
  compression_algo   = {"Compression algorithm (lz4, pglz, zstd)", "lz4"},
  pct_create         = {"Percentage of CREATE operations", 40},
  pct_read           = {"Percentage of READ operations", 30},
  pct_update         = {"Percentage of UPDATE operations", 20},
  pct_delete         = {"Percentage of DELETE operations", 10},
}


local socket_ok, socket = pcall(require, "socket")

function get_timestamp_utc()
  if socket_ok and socket.gettime then
    local t = socket.gettime()
    local seconds = math.floor(t)
    local micros = math.floor((t - seconds) * 1e6)
    return string.format("%s.%06d", os.date("!%Y-%m-%d %H:%M:%S", seconds), micros)
  else
    -- fallback: use os.date() + random microsecond jitter
    local micros = math.random(0, 999999)
    return string.format("%s.%06d", os.date("!%Y-%m-%d %H:%M:%S"), micros)
  end
end

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
-- gen_json_payload()
-- Enterprise OLTP payload generator (no datetime inside JSON)
-- Payload size: ~4KB – 64KB
-- ==========================================================
local function gen_json_payload()
  -- Target payload size range
  local target = sysbench.rand.uniform(4096, 65536)
  local pad_len = target - 600  -- structured portion ~600 B
  if pad_len < 0 then pad_len = 0 end
  local pad = sysbench.rand.string(string.rep("x", pad_len))

  -- Define realistic business entities
  local entities = {
    {
      type = "customer_profile",
      fields = {
        {name = "first_name",  sample = {"Alice", "Bob", "Charlie", "Diana", "Ethan"}},
        {name = "last_name",   sample = {"Smith", "Johnson", "Lee", "Patel", "Garcia"}},
        {name = "email",       sample = {"alice@example.com", "bob@corp.com", "charlie@biz.io"}},
        {name = "status",      sample = {"active", "suspended", "pending"}},
        {name = "tier",        sample = {"standard", "gold", "platinum"}},
        {name = "balance",     min = 0.0, max = 100000.0},
        {name = "points",      min = 0, max = 20000},
        {name = "region",      sample = {"US-TX", "US-CA", "US-NY", "CA-ON"}}
      }
    },
    {
      type = "order_record",
      fields = {
        {name = "order_id",    sample = {"ORD-20251022-0001", "ORD-20251022-0002", "ORD-20251022-0003"}},
        {name = "order_date",  sample = {"2025-10-22", "2025-10-21", "2025-09-30"}},
        {name = "items",       min = 1, max = 20},
        {name = "amount",      min = 10.0, max = 5000.0},
        {name = "currency",    sample = {"USD", "EUR", "JPY", "GBP"}},
        {name = "payment",     sample = {"credit_card", "paypal", "wire"}},
        {name = "status",      sample = {"processing", "shipped", "delivered", "cancelled"}},
        {name = "warehouse",   sample = {"DAL", "NYC", "LON", "TOR"}}
      }
    },
    {
      type = "invoice",
      fields = {
        {name = "invoice_no",  sample = {"INV-001", "INV-002", "INV-003"}},
        {name = "invoice_date", sample = {"2025-09-01", "2025-09-15", "2025-10-01"}},
        {name = "due_date",     sample = {"2025-10-15", "2025-10-30"}},
        {name = "amount_due",   min = 50.0, max = 20000.0},
        {name = "tax_rate",     min = 0.05, max = 0.15},
        {name = "currency",     sample = {"USD", "CAD", "EUR"}},
        {name = "paid",         sample = {"true", "false"}},
        {name = "client_name",  sample = {"ACME Corp", "Globex Ltd", "Wayne Enterprises"}}
      }
    },
    {
      type = "employee_record",
      fields = {
        {name = "emp_id",       sample = {"E001", "E002", "E003", "E004"}},
        {name = "department",   sample = {"HR", "ENG", "OPS", "FIN", "SALES"}},
        {name = "salary",       min = 40000.0, max = 180000.0},
        {name = "bonus",        min = 0.0, max = 25000.0},
        {name = "performance",  sample = {"A", "B", "C"}},
        {name = "manager",      sample = {"John Doe", "Mary Liu", "Peter Khan"}}
      }
    },
    {
      type = "shipment",
      fields = {
        {name = "shipment_id",  sample = {"SHP-101", "SHP-102", "SHP-103"}},
        {name = "carrier",      sample = {"UPS", "FedEx", "DHL", "USPS"}},
        {name = "weight",       min = 0.5, max = 200.0},
        {name = "priority",     sample = {"standard", "express", "overnight"}},
        {name = "cost",         min = 5.0, max = 500.0},
        {name = "delivered",    sample = {"true", "false"}},
        {name = "destination",  sample = {"Dallas TX", "London UK", "Berlin DE", "Toronto CA"}}
      }
    }
  }

  -- Choose random entity
  local entity = entities[sysbench.rand.default(1, #entities)]

  -- Populate fields
  local data_fields = {}
  for _, f in ipairs(entity.fields) do
    local value
    if f.sample then
      value = f.sample[sysbench.rand.default(1, #f.sample)]
    elseif f.min and f.max then
      local v = sysbench.rand.uniform(f.min, f.max)
      value = (v % 1 == 0) and string.format("%d", v) or string.format("%.2f", v)
    else
      value = "N/A"
    end
    table.insert(data_fields, string.format('"%s":"%s"', f.name, value))
  end

  -- Assemble JSON payload (no timestamp)
  local json_str = string.format(
    '{"entity_type":"%s","data":{%s},"notes":"%s"}',
    entity.type,
    table.concat(data_fields, ","),
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
      time     TIMESTAMP(6) NOT NULL,
      prefix   VARCHAR(4) NOT NULL,
      guid     VARCHAR(64) NOT NULL,
      data     JSONB,
      PRIMARY KEY (guid, prefix)
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
        "ALTER TABLE %s ALTER COLUMN data SET (compression = '%s');",
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
-- Generates a diverse set of enterprise-style identifiers:
-- UUIDs, Customer IDs, Account Numbers, Order Codes, 
-- Invoice Numbers, and Region/Dept prefixed identifiers.
-- ==========================================================
function create_guid_pool(n)
  local pool = {}

  -- --- Helper Generators ---

  -- UUID (standard version 4)
  local function gen_uuid()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function(c)
      local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
      return string.format('%x', v)
    end)
  end

  -- Simple Customer ID: CUST-000001
  local function gen_customer_id(i)
    return string.format("CUST-%06d", i)
  end

  -- Account ID: ACC-XXXX (random alphanumeric)
  local function gen_account_id()
    return string.format("ACC-%04X", math.random(0, 0xFFFF))
  end

  -- Order Code: ORD-YYYYMMDD-XXXX
  local function gen_order_code()
    local date_str = os.date("!%Y%m%d")
    return string.format("ORD-%s-%04d", date_str, math.random(0, 9999))
  end

  -- Invoice ID: INV-ABCD1234 (letters + digits)
  local function gen_invoice_id()
    local letters = ""
    for _ = 1, 4 do
      letters = letters .. string.char(math.random(65, 90)) -- A–Z
    end
    return string.format("INV-%s%04d", letters, math.random(0, 9999))
  end

  -- Region/Department Code: TX-SALES-00123
  local function gen_region_tag()
    local regions = {"TX", "CA", "NY", "IL", "FL", "WA", "GA"}
    local depts = {"SALES", "OPS", "FIN", "HR", "ENG", "RND"}
    return string.format("%s-%s-%05d",
      regions[math.random(#regions)],
      depts[math.random(#depts)],
      math.random(0, 99999))
  end

  -- Vendor-style prefix key (enterprise products)
  local function gen_vendor_tag()
    local vendors = {"MICROSOFT", "AMZN", "GOOGLE", "IBM", "ORCL", "SAP"}
    return string.format("%s-%04X", vendors[math.random(#vendors)], math.random(0, 0xFFFF))
  end

  -- --- Main Pool Generation Loop ---
  for i = 1, n do
    local id_type = math.floor(sysbench.rand.uniform(1, 6))

    local id

    if id_type == 1 then
      id = gen_customer_id(i)      -- sequential customer IDs
    elseif id_type == 2 then
      id = gen_account_id()        -- random account code
    elseif id_type == 3 then
      id = gen_order_code()        -- daily order ID
    elseif id_type == 4 then
      id = gen_invoice_id()        -- invoice-like key
    elseif id_type == 5 then
      id = gen_region_tag()        -- region/department composite
    else
      id = gen_vendor_tag()        -- vendor-tag style
    end

    -- Occasionally mix in UUIDs for diversity
    if math.random() < 0.15 then
      id = gen_uuid()
    end

    table.insert(pool, id)
  end

  print(string.format("✅ Generated %d enterprise-style GUIDs", #pool))
  return pool
end

-- ==========================================================
-- Prepare Phase — Bulk Insert
-- This version uses a pre-generated GUID pool
-- and cycles through it in random order
-- ==========================================================


-- Helper to shuffle GUID list in-place
function shuffle(tbl)
  for i = #tbl, 2, -1 do
    local j = math.random(i)
    tbl[i], tbl[j] = tbl[j], tbl[i]
  end
end

-- ==========================================================
-- Prepare Phase — Bulk Insert
-- ==========================================================
function prepare()
  local csv_path     = sysbench.opt.csv_path or "guid_pool.csv"
  local n_guids      = sysbench.opt.n_guids or 1000
  local table_name   = sysbench.opt.table_name
  local prefix_val   = sysbench.opt.prefix
  local total_rows   = sysbench.opt.table_size
  local batch        = sysbench.opt.batch_size

  print("Connecting to PostgreSQL...")
  local con = sysbench.sql.driver():connect()
  create_table(con)

  -- ✅ Generate and save GUID pool
  guid_pool = create_guid_pool(n_guids)
  save_guid_pool_to_csv(csv_path, guid_pool)

  print(string.format(
    "=== Prepare phase started for table: %s ===", table_name))
  print(string.format(
    "Total rows: %d | GUIDs: %d | Batch size: %d",
    total_rows, #guid_pool, batch))



  local values   = {}
  local inserted = 0
  local round    = 0

  while inserted < total_rows do
    round = round + 1
    shuffle(guid_pool)
    print(string.format("🔄 Round %d – inserting for %d GUIDs (random order)", round, #guid_pool))

    for _, guid in ipairs(guid_pool) do
      if inserted >= total_rows then break end
      -- local ms = math.random(0, 999999)  -- adds microsecond-level randomness
      -- local now = string.format("%s.%06d", os.date("!%Y-%m-%d %H:%M:%S"), ms)
      -- local now = string.format("%s.%06d", os.date("!%Y-%m-%d %H:%M:%S"), math.floor((os.clock() * 1000000) % 1000000))

      local now = get_timestamp_utc()
      local json_str = gen_json_payload()

      table.insert(values, string.format(
        "('%s','%s','%s','%s'::jsonb)", now, prefix_val, guid, json_str))
      inserted = inserted + 1

      if (#values == batch or inserted == total_rows) then
        local sql = string.format(
          "INSERT INTO %s (time, prefix, guid, data) VALUES %s",
          table_name, table.concat(values, ","))
        local ok, err = pcall(function() con:query(sql) end)
        if not ok then
          print(string.format("❌ Batch failed at row %d: %s", inserted, tostring(err)))
        end
        values = {}
      end
    end

    print(string.format("✅ Round %d complete — inserted %d / %d rows", round, inserted, total_rows))
  end

  print(string.format("🎯 Prepare phase completed (%d rows total across %d rounds)", inserted, round))
  con:disconnect()
end





-- ==========================================================
-- Thread Initialization — Run Phase Setup (OLTP Version)
-- ==========================================================
function thread_init()
  math.randomseed(os.time() + sysbench.tid) -- unique RNG seed per thread
  drv = sysbench.sql.driver()
  con = drv:connect()

  table_name = sysbench.opt.table_name
  prefix_val = sysbench.opt.prefix
  batch_size = sysbench.opt.run_batch_size or sysbench.opt.batch_size or 1
  total_rows = sysbench.opt.total_rows
  verbose    = sysbench.opt.verbose

  -- ✅ Load GUIDs for this thread
  guid_pool = {}
  for line in io.lines(sysbench.opt.csv_path) do
    table.insert(guid_pool, line)
  end

  current_index = 1
  shuffle(guid_pool)


  -- ✅ Normalize CRUD operation ratios (once per thread)
  pct_create = tonumber(sysbench.opt.pct_create) or 40
  pct_read   = tonumber(sysbench.opt.pct_read)   or 30
  pct_update = tonumber(sysbench.opt.pct_update) or 20
  pct_delete = tonumber(sysbench.opt.pct_delete) or 10

  local total_pct = pct_create + pct_read + pct_update + pct_delete
  if total_pct ~= 100 then
    print(string.format("[Thread %d] ⚠️ Adjusting CRUD mix (sum was %d, scaling to 100)", sysbench.tid, total_pct))
    local scale = 100 / total_pct
    pct_create = math.floor(pct_create * scale + 0.5)
    pct_read   = math.floor(pct_read   * scale + 0.5)
    pct_update = math.floor(pct_update * scale + 0.5)
    pct_delete = 100 - (pct_create + pct_read + pct_update)
  end

  print(string.format(
    "[Thread %d] Initialized (run_batch=%d, total_rows=%d, GUIDs=%d, CRUD mix: C=%d%% R=%d%% U=%d%% D=%d%%)",
    sysbench.tid, batch_size, total_rows, #guid_pool,
    pct_create, pct_read, pct_update, pct_delete
  ))
end

-- ==========================================================
-- Run Phase — OLTP Transaction Mix (C/R/U/D)
-- ==========================================================

function event()

  
  local guid = guid_pool[current_index]
  current_index = current_index + 1
  if current_index > #guid_pool then
    current_index = 1
    shuffle(guid_pool)
  end


  local op  = math.floor(sysbench.rand.uniform(1, 100))
  local now = get_timestamp_utc()

  if op <= pct_create then
    -- UPSERT (insert or update the same key)
    local json_str = gen_json_payload()
    local sql = string.format([[
      INSERT INTO %s (time, prefix, guid, data)
      VALUES ('%s','%s','%s',$$%s$$::jsonb)
      ON CONFLICT (prefix, guid)
      DO UPDATE SET data = EXCLUDED.data, time = EXCLUDED.time;
    ]], table_name, now, prefix_val, guid, json_str)

    local ok, err = pcall(function() con:query(sql) end)
    if not ok then print("[UPSERT ❌]", err) elseif verbose then print("[UPSERT ✅]", guid) end

  elseif op <= pct_create + pct_read then
    -- READ
    local sql = string.format(
      "SELECT data FROM %s WHERE prefix='%s' AND guid='%s' LIMIT 1",
      table_name, prefix_val, guid)
    local ok, err = pcall(function() con:query(sql) end)
    if not ok then print("[READ ❌]", err) elseif verbose then print("[READ ✅]", guid) end

  elseif op <= pct_create + pct_read + pct_update then
    -- UPDATE
    local json_str = gen_json_payload()
    local sql = string.format(
      "UPDATE %s SET data=$$%s$$::jsonb, time='%s' WHERE prefix='%s' AND guid='%s'",
      table_name, json_str, now, prefix_val, guid)
    local ok, err = pcall(function() con:query(sql) end)
    if not ok then print("[UPDATE ❌]", err) elseif verbose then print("[UPDATE ✅]", guid) end

  else
    -- DELETE
    local sql = string.format(
      "DELETE FROM %s WHERE prefix='%s' AND guid='%s'",
      table_name, prefix_val, guid)
    local ok, err = pcall(function() con:query(sql) end)
    if not ok then print("[DELETE ❌]", err) elseif verbose then print("[DELETE ✅]", guid) end
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