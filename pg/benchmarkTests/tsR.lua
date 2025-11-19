-- ==========================================================
-- Sysbench Time-Series Reader Benchmark
-- ==========================================================
-- Description:
--   Simulates realistic time-range queries on a time-series
--   PostgreSQL database table using random GUIDs.
--
-- Usage:
--   sysbench tsReader.lua \
--     --db-driver=pgsql \
--     --pgsql-host=<host> \
--     --pgsql-user=<user> \
--     --pgsql-password=<pass> \
--     --pgsql-db=<db> \
--     --table_name=ts_v01 \
--     --guid_source=ts_v01 \
--     --prefix=TS \
--     --threads=4 \
--     --time=60 \
--     run
-- ==========================================================

sysbench.cmdline.options = {
  table_name   = {"Target table name", "ts_v01"},
  guid_source  = {"Source table for GUID list", "ts_v01"},
  prefix       = {"Prefix tag value", "TS"},
  verbose      = {"Print query details", false},
}

-- ==========================================================
-- Utility: Weighted random time-range selector
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
-- Utility: Shuffle table in-place
-- ==========================================================
local function shuffle(tbl)
  for i = #tbl, 2, -1 do
    local j = math.random(i)
    tbl[i], tbl[j] = tbl[j], tbl[i]
  end
end

-- ==========================================================
-- Thread Initialization — Setup GUID list
-- ==========================================================
function thread_init()
  math.randomseed(os.time() + sysbench.tid)
  drv = sysbench.sql.driver()
  con = drv:connect()

  table_name = sysbench.opt.table_name
  guid_src   = sysbench.opt.guid_source
  prefix_val = sysbench.opt.prefix
  verbose    = sysbench.opt.verbose

  guid_pool = {}
  local sql = string.format(
    "SELECT DISTINCT guid FROM %s WHERE prefix='%s';",
    guid_src, prefix_val)
  local cursor = con:query(sql)

  if cursor then
    for row in cursor:rows() do
      table.insert(guid_pool, row[1])
    end
  end

  if #guid_pool == 0 then
    print(string.format("[Thread %d] ⚠️ No GUIDs found for prefix=%s", sysbench.tid, prefix_val))
  else
    print(string.format("[Thread %d] ✅ Loaded %d GUIDs", sysbench.tid, #guid_pool))
  end

  current_index = 1
  shuffle(guid_pool)
end

-- ==========================================================
-- Run Phase — Perform time-range reads
-- ==========================================================
function event()
  if #guid_pool == 0 then return end

  local guid = guid_pool[current_index]
  current_index = current_index + 1
  if current_index > #guid_pool then
    current_index = 1
    shuffle(guid_pool)
  end

  local range = choose_range()
  local hours = range.hours
  local end_time = os.date("!%Y-%m-%d %H:%M:%S")
  local start_time = os.date("!%Y-%m-%d %H:%M:%S", os.time() - (hours * 3600))

  local sql = string.format([[
    SELECT time, data
    FROM %s
    WHERE prefix='%s'
      AND guid='%s'
      AND time BETWEEN '%s' AND '%s'
    ORDER BY time ASC;
  ]], table_name, prefix_val, guid, start_time, end_time)

  local ok, result = pcall(function() return con:query(sql) end)
  if not ok then
    print(string.format("[Thread %d] ❌ Query error: %s", sysbench.tid, tostring(result)))
  elseif result == nil then
    print(string.format("[Thread %d] ⚠️ Query returned nil", sysbench.tid))
  elseif verbose then
    print(string.format("[Thread %d] 🕓 Queried %s (%s range, %s–%s)",
      sysbench.tid, guid, range.label, start_time, end_time))
  end
end

-- ==========================================================
-- Cleanup and Disconnect
-- ==========================================================
function thread_done()
  con:disconnect()
end
