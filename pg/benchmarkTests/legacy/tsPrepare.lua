-- ==========================================================
-- Sysbench Custom Prepare Script for Time-Series Inserts
-- ==========================================================

-- ==========================================================
-- Command line options
-- ==========================================================
sysbench.cmdline.options = {
  table_size = {"Number of rows to insert", 10000},
  prefix     = {"Prefix tag value", "TS"},
  table_name = {"Target table name", "ts_v00"}
}

-- ==========================================================
-- Generate a valid UUID (Version 4)
-- ==========================================================
local function gen_uuid()
  local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
  return string.gsub(template, '[xy]', function(c)
    local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
    return string.format('%x', v)
  end)
end

-- ==========================================================
-- Create table dynamically
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
-- Prepare phase — insert all rows
-- ==========================================================
function prepare()
  local table_name = sysbench.opt.table_name
  local prefix_val = sysbench.opt.prefix
  local total_rows = sysbench.opt.table_size
  local batch_size = 100   -- 👈 change this to 1000 or any size you like

  print("Connecting to PostgreSQL...")
  local con = sysbench.sql.driver():connect()
  create_table(con)

  print(string.format("=== Prepare phase started for %s ===", table_name))
  print(string.format("Inserting %d rows in batches of %d", total_rows, batch_size))

  local values = {}

  for i = 1, total_rows do
    local guid = gen_uuid()
    local now = os.date("!%Y-%m-%d %H:%M:%S")
    local json_str = string.format(
      '{"sensor":"abc","value":%.2f,"unit":"C"}',
      sysbench.rand.uniform(20.0, 30.0)
    )

    table.insert(values, string.format(
      "('%s','%s','%s','%s'::jsonb)",
      now, prefix_val, guid, json_str
    ))

    -- When batch is full or last row → run single INSERT for the batch
    if (#values == batch_size or i == total_rows) then
      local sql = string.format(
        "INSERT INTO %s (time, prefix, guid, data) VALUES %s",
        table_name, table.concat(values, ",")
      )

      local ok, err = pcall(function() con:query(sql) end)
      if not ok then
        print(string.format("❌ Batch ending at row %d failed: %s", i, tostring(err)))
      else
        print(string.format("✅ Inserted rows %d-%d", i - #values + 1, i))
      end

      values = {}     -- reset batch buffer
      io.flush()      -- show progress immediately
    end
  end

  print(string.format("=== Prepare phase completed for %s ===", table_name))
  con:disconnect()
end


-- ==========================================================
-- Cleanup phase — drop table if needed
-- ==========================================================
function cleanup()
  local table_name = sysbench.opt.table_name
  print("Connecting to PostgreSQL for cleanup...")
  local con = sysbench.sql.driver():connect()
  print(string.format("Dropping table: %s", table_name))
  con:query(string.format("DROP TABLE IF EXISTS %s;", table_name))
  print("Cleanup completed.")
  print("Closing connection...")
  con:disconnect()
end
