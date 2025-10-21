-- ==========================================================
-- Sysbench Time-Series Benchmark Script (Prepare + Run)
-- ==========================================================
-- CRUD operations: 40% C, 30% R, 20% U, and 10% D.
-- Record sizes should be in the range of 4KB to 64KB 
-- Pick guids from a list of pre-generated guids to simulate realistic access patterns.
-- Custom size of the startup prep table.
-- CSV Logging of detailed per-transaction latencies.
-- ==========================================================

sysbench.cmdline.options = {
  table_name  = {"Target table name", "oltp_v00"},
  prefix      = {"Prefix tag value", "OLTP"},
  table_size  = {"Number of rows to insert during prepare", 10000},
  batch_size  = {"Rows per batch insert during run", 100},
  total_rows  = {"Total rows per thread to insert during run", 10000},
  verbose     = {"Print every batch progress", false}
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
-- Generate realistic OLTP-style JSON payload (4KB–64KB)
-- ==========================================================
local function gen_json_payload()
  -- Choose total target size (simulate variable record sizes)
  local target = sysbench.rand.uniform(4096, 65536)

  -- Core OLTP-style fields
  local txn_id   = gen_uuid()
  local cust_id  = sysbench.rand.default(1000, 999999)
  local region   = string.format("R%03d", sysbench.rand.default(1, 250))
  local amount   = sysbench.rand.uniform(10.00, 9999.99)
  local quantity = sysbench.rand.default(1, 50)
  local product  = string.format("P-%05d", sysbench.rand.default(1, 99999))
  local status   = (sysbench.rand.uniform(0, 1) > 0.5) and "APPROVED" or "PENDING"
  local tstamp   = os.date("!%Y-%m-%dT%H:%M:%S")

  -- Base JSON (~200 bytes depending on value length)
  local base_json = string.format(
    '{"txn_id":"%s","customer_id":%d,"product":"%s","region":"%s","quantity":%d,"amount":%.2f,"status":"%s","timestamp":"%s"',
    txn_id, cust_id, product, region, quantity, amount, status, tstamp
  )

  -- Optional nested metadata (to mimic application-level detail)
  local meta = string.format(
    ',"meta":{"device":"%s","channel":"%s","promo":%s}',
    (sysbench.rand.uniform(0, 1) > 0.5) and "MOBILE" or "WEB",
    (sysbench.rand.uniform(0, 1) > 0.5) and "APP" or "PORTAL",
    (sysbench.rand.uniform(0, 1) > 0.8) and "true" or "false"
  )

  local current_size = #base_json + #meta + 1  -- +1 for closing brace
  local pad_len = target - current_size
  if pad_len < 0 then pad_len = 0 end

  -- Filler for realistic variable-length remarks or logs
  local pad = sysbench.rand.string(string.rep("x", pad_len))

  local json_str = string.format('%s%s,"notes":"%s"}', base_json, meta, pad)
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
      time   TIMESTAMPTZ NOT NULL,
      prefix TEXT NOT NULL,
      guid   UUID NOT NULL,
      data   JSONB,
      PRIMARY KEY (time, prefix, guid)
    );
  ]], table_name)

  assert(con:query(create_sql))
  print("Table created successfully.")
end

-- ==========================================================
-- Prepare Phase — Bulk Insert
-- ==========================================================
function prepare()
  local table_name = sysbench.opt.table_name
  local prefix_val = sysbench.opt.prefix
  local total_rows = sysbench.opt.table_size
  local batch_size = 100

  print("Connecting to PostgreSQL...")
  local con = sysbench.sql.driver():connect()
  create_table(con)

  print(string.format("=== Prepare phase started for table: %s ===", table_name))
  print(string.format("Inserting %d rows (batch size = %d)", total_rows, batch_size))

  local values = {}
  local inserted = 0

  for i = 1, total_rows do
    local guid = gen_uuid()
    local now = os.date("!%Y-%m-%d %H:%M:%S")
    local json_str = gen_json_payload()

    table.insert(values, string.format(
      "('%s','%s','%s','%s'::jsonb)", now, prefix_val, guid, json_str
    ))

    if (#values == batch_size or i == total_rows) then
      local sql = string.format(
        "INSERT INTO %s (time, prefix, guid, data) VALUES %s",
        table_name, table.concat(values, ",")
      )
      local ok, err = pcall(function() con:query(sql) end)
      if not ok then
        print(string.format("❌ Batch failed at row %d: %s", i, tostring(err)))
      end
      inserted = inserted + #values
      if inserted % 1000 == 0 then
        print(string.format("Inserted %d / %d rows", inserted, total_rows))
      end
      values = {}
    end
  end

  print(string.format("=== Prepare phase completed (%d total rows) ===", inserted))
  con:disconnect()
end

-- ==========================================================
-- Run Phase — Continuous Write Benchmark
-- ==========================================================
function thread_init()
  drv = sysbench.sql.driver()
  con = drv:connect()
  table_name = sysbench.opt.table_name
  prefix_val = sysbench.opt.prefix
  batch_size = sysbench.opt.batch_size
  total_rows = sysbench.opt.total_rows
  verbose = sysbench.opt.verbose
  print(string.format("[Thread %d] Initialized (batch=%d, total=%d)",
                      sysbench.tid, batch_size, total_rows))
end

-- This needs to have custom logic for each operation type -- CREATE, READ, UPDATE, DELETE  
-- according to the specified percentages.

function event()
  local op = sysbench.rand.uniform(1, 100)

  if op <= 40 then
    -------------------------------------------------
    -- 🟢 CREATE (40%)
    -------------------------------------------------
    local values = {}
    for i = 1, batch_size do
      local guid = gen_uuid()
      local now = os.date("!%Y-%m-%d %H:%M:%S")
      local json_str = gen_json_payload()
      table.insert(values, string.format(
        "('%s','%s','%s','%s'::jsonb)", now, prefix_val, guid, json_str))
    end
  

    local sql = string.format(
      "INSERT INTO %s (time, prefix, guid, data) VALUES %s",
      table_name, table.concat(values, ",")
    )

    local ok, err = pcall(function() con:query(sql) end)
    if not ok then
      print(string.format("[Thread %d] ❌ Insert failed: %s", sysbench.tid, tostring(err)))
    elseif verbose then
      print(string.format("[Thread %d] ✅ Inserted %d rows", sysbench.tid, batch_size))
    end

  elseif op <= 70 then
    -------------------------------------------------
    -- 🔵 READ (30%)
    -------------------------------------------------
    local sql = string.format(
      "SELECT * FROM %s ORDER BY time DESC LIMIT 10",
      table_name
    )



    local ok, err = pcall(function() con:query(sql) end)
    if not ok then
      print(string.format("[Thread %d] ❌ Read failed: %s", sysbench.tid, tostring(err)))
    elseif verbose then
      print(string.format("[Thread %d] 🔍 Read 10 rows", sysbench.tid))
    end
 

  elseif op <= 90 then
    -------------------------------------------------
    -- 🟠 UPDATE (20%)
    -------------------------------------------------
    local new_json = gen_json_payload()
    local sql = string.format([[
      UPDATE %s
      SET data = '%s'::jsonb
      WHERE guid IN (
        SELECT guid FROM %s ORDER BY RANDOM() LIMIT 5
      )
    ]], table_name, new_json, table_name)


    local ok, err = pcall(function() con:query(sql) end)
    if not ok then
      print(string.format("[Thread %d] ❌ Update failed: %s", sysbench.tid, tostring(err)))
    elseif verbose then
      print(string.format("[Thread %d] 🛠️ Updated 5 rows", sysbench.tid))
    end



  else
    -------------------------------------------------
    -- 🔴 DELETE (10%)
    -------------------------------------------------
    local sql = string.format([[
      DELETE FROM %s
      WHERE guid IN (
        SELECT guid FROM %s ORDER BY RANDOM() LIMIT 3
      )
    ]], table_name, table_name)



    local ok, err = pcall(function() con:query(sql) end)
    if not ok then
      print(string.format("[Thread %d] ❌ Delete failed: %s", sysbench.tid, tostring(err)))
    elseif verbose then
      print(string.format("[Thread %d] 🗑️ Deleted 3 rows", sysbench.tid))
    end

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


