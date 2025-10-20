--
-- Sysbench custom prepare script for PostgreSQL
-- Supports dynamic table name and configuration via CLI or config file.
--
-- Schema:
--   time   (TIMESTAMPTZ)
--   prefix (TEXT)
--   guid   (UUID)
--   data   (JSONB)
-- Primary key: (time, prefix, guid)
--

require("sysbench")

-- ==========================================================
-- Command line options
-- ==========================================================
sysbench.cmdline.options = {
  table_size = {"Number of rows to insert", 10000},
  prefix = {"Prefix tag value", "TS"},
  table_name = {"Target table name", "ts_v00"}  -- 👈 configurable table name
}

-- ==========================================================
-- Hooks
-- ==========================================================
function sysbench.hooks.before_test()
  print("Connecting to PostgreSQL...")
  con = sysbench.sql.driver():connect()
end

function sysbench.hooks.after_test()
  print("Closing connection...")
  con:disconnect()
end

-- ==========================================================
-- Create table dynamically
-- ==========================================================
function create_table()
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
-- Prepare phase
-- ==========================================================
function prepare()
  local table_name = sysbench.opt.table_name
  local prefix_val = sysbench.opt.prefix
  local total_rows = sysbench.opt.table_size

  print(string.format("=== Prepare phase started for table: %s ===", table_name))
  print(string.format("Inserting %d rows with prefix: %s", total_rows, prefix_val))

  create_table()

  local insert_sql = string.format([[
    INSERT INTO %s (time, prefix, guid, data)
    VALUES ($1, $2, $3, $4)
  ]], table_name)
  local stmt = assert(con:prepare(insert_sql))

  local json_template = '{"sensor":"abc","value":%.2f,"unit":"C"}'

  for i = 1, total_rows do
    local guid = sysbench.rand.string("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx")
    local now = os.date("!%Y-%m-%d %H:%M:%S")
    local json_str = string.format(json_template, sysbench.rand.uniform(20.0, 30.0))
    stmt:execute(now, prefix_val, guid, json_str)

    if i % 1000 == 0 then
      print(string.format("Inserted %d / %d rows", i, total_rows))
    end
  end

  stmt:close()
  print(string.format("=== Prepare phase completed for table: %s ===", table_name))
end

-- ==========================================================
-- Cleanup function
-- ==========================================================
function cleanup()
  local table_name = sysbench.opt.table_name
  print(string.format("Dropping table: %s", table_name))
  con:query(string.format("DROP TABLE IF EXISTS %s;", table_name))
  print("Cleanup completed.")
end
