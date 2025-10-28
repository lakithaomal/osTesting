-- ==========================================================
-- Sysbench Time-Series Benchmark Script (Prepare + Run)
-- ==========================================================
sysbench.cmdline.options = {
  table_name  = {"Target table name", "ts_v00"},
  prefix      = {"Prefix tag value", "TS"},
  table_size  = {"Number of rows to insert during prepare", 10000},
  batch_size  = {"Rows per batch insert during run", 100},
  total_rows  = {"Total rows per thread to insert during run", 10000},
  verbose     = {"Print every batch progress", false}
}

-- ==========================================================
-- Utility: Choose time range based on weighted probabilities
-- ==========================================================
local function choose_range()
  local r = sysbench.rand.uniform(1, 100)
  if r <= 40 then
    return {label = "daily",   hours = 24}
  elseif r <= 70 then
    return {label = "weekly",  hours = 24 * 7}
  elseif r <= 85 then
    return {label = "monthly", hours = 24 * 30}
  elseif r <= 95 then
    return {label = "2months", hours = 24 * 60}
  else
    return {label = "3months", hours = 24 * 90}
  end
end

-- ==========================================================
-- Utility: Pick a random time window based on chosen range
-- ==========================================================
local function pick_time_window()
  local range = choose_range()
  local now = os.time()
  local six_months_ago = now - (24 * 60 * 60 * 30 * 6)
  local span = range.hours * 60 * 60
  local start_ts = sysbench.rand.uniform(six_months_ago, now - span)
  local end_ts = start_ts + span
  return range.label,
         os.date("!%Y-%m-%d %H:%M:%S", start_ts),
         os.date("!%Y-%m-%d %H:%M:%S", end_ts)
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
-- Utility: Generate variable-size JSON (100B – 1KB)
-- ==========================================================
local function gen_json_payload()
  local target = sysbench.rand.uniform(100, 1000)
  local pad_len = target - 41  -- subtract ~41 B for fixed JSON part
  if pad_len < 0 then pad_len = 0 end
  local pad = sysbench.rand.string(string.rep("x", pad_len))

  local json_str = string.format(
    '{"sensor":"abc","value":%.2f,"unit":"C","v_extra":"%s"}',
    sysbench.rand.uniform(20.0, 30.0),
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

function event()
  local label, start_time, end_time = pick_time_window()

  local sql = string.format([[
    SELECT time, data
    FROM %s
    WHERE prefix='%s'
      AND time BETWEEN '%s' AND '%s'
    ORDER BY time ASC
  ]], table_name, prefix_val, start_time, end_time)

  local ok, err = pcall(function() con:query(sql) end)

  if not ok then
    print(string.format("❌ [%s] Query failed: %s", label, tostring(err)))
  elseif sysbench.opt.verbose then
    print(string.format("✅ [%s] Range query %s → %s", label, start_time, end_time))
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
