-- ==========================================================
-- Sysbench Run Script for Time-Series Write Workload
-- ==========================================================

sysbench.cmdline.options = {
  table_name  = {"Target table name", "ts_v00"},
  prefix      = {"Prefix tag value", "TS"},
  batch_size  = {"Number of rows per INSERT batch", 100},
  total_rows  = {"Total rows per thread to insert", 10000},
  verbose     = {"Print every batch progress", false}
}

-- ==========================================================
-- Generate UUID (Version 4)
-- ==========================================================
local function gen_uuid()
  local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
  return string.gsub(template, '[xy]', function(c)
    local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
    return string.format('%x', v)
  end)
end

-- ==========================================================
-- Thread initialization
-- ==========================================================
function thread_init()
  drv = sysbench.sql.driver()
  con = drv:connect()
  table_name = sysbench.opt.table_name
  prefix_val = sysbench.opt.prefix
  batch_size = sysbench.opt.batch_size
  total_rows = sysbench.opt.total_rows

  print(string.format("[Thread %d] Initialized for %s (batch=%d, total=%d)",
                      sysbench.tid, table_name, batch_size, total_rows))
end

-- Generate a JSON payload between 100 B and 1 KB
local function gen_json_payload()
  -- pick target size between 100 and 1000 bytes
  local target = sysbench.rand.uniform(100, 1000)
  -- random text length to fill the gap
  local pad_len = target - 41  -- subtract ~41 B for base fields
  if pad_len < 0 then pad_len = 0 end

  -- random alphanumeric filler
  local pad = sysbench.rand.string(string.rep("x", pad_len))

  local json_str = string.format(
    '{"sensor":"abc","value":%.2f,"unit":"C","extra":"%s"}',
    sysbench.rand.uniform(20.0, 30.0),
    pad
  )
  return json_str
end


-- ==========================================================
-- Core write workload (executed repeatedly)
-- ==========================================================
function event()
  local values = {}
  for i = 1, batch_size do
    local guid = gen_uuid()
    local now = os.date("!%Y-%m-%d %H:%M:%S")
    local json_str = string.format(
      '{"sensor":"abc","value":%.2f,"unit":"C"}',
      sysbench.rand.uniform(20.0, 30.0)
    )
    table.insert(values, string.format(
      "('%s','%s','%s','%s'::jsonb)", now, prefix_val, guid, json_str))
  end

  local sql = string.format(
    "INSERT INTO %s (time, prefix, guid, data) VALUES %s",
    table_name, table.concat(values, ",")
  )

  local ok, err = pcall(function() con:query(sql) end)
  if not ok then
    print(string.format("[Thread %d] ❌ Batch insert failed: %s", sysbench.tid, tostring(err)))
  elseif sysbench.opt.verbose then
    print(string.format("[Thread %d] ✅ Inserted %d rows", sysbench.tid, batch_size))
  end
end

-- ==========================================================
-- Cleanup
-- ==========================================================
function thread_done()
  con:disconnect()
end
