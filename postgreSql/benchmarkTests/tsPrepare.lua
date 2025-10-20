--
-- Sysbench custom prepare script for PostgreSQL Time-Series workload
--
-- Table: ts_data
-- Columns:
--   time   (TIMESTAMPTZ)
--   prefix (TEXT)
--   guid   (UUID)
--   data   (JSONB)
-- Primary key: (time, prefix, guid)
--

require("sysbench")

-- Command line options
sysbench.cmdline.options = {
  table_size = {"Number of rows to insert", 10000},
  prefix = {"Prefix tag value", "TS"}
}

function sysbench.hooks.before_test()
  print("Connecting to PostgreSQL...")
  con = sysbench.sql.driver():connect()
end

function sysbench.hooks.after_test()
  print("Closing connection...")
  con:disconnect()
end

-- Create the time-series table
function create_table()
  local create_sql = [[
    CREATE TABLE IF NOT EXISTS ts_data (
      time   TIMESTAMPTZ NOT NULL,
      prefix TEXT NOT NULL,
      guid   UUID NOT NULL,
      data   JSONB,
      PRIMARY KEY (time, prefix, guid)
    );
  ]]
  assert(con:query(create_sql))
  print("Created table ts_data")
end

-- Prepare phase: populate with sample data
function prepare()
  print("=== Prepare phase for ts_data ===")
  create_table()

  local insert_sql = [[
    INSERT INTO ts_data (time, prefix, guid, data)
    VALUES ($1, $2, $3, $4)
  ]]
  local stmt = assert(con:prepare(insert_sql))

  local prefix_val = sysbench.opt.prefix
  local json_template = '{"sensor":"abc","value":%.2f,"unit":"C"}'

  for i = 1, sysbench.opt.table_size do
    local guid = sysbench.rand.string("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx")
    local now = os.date("!%Y-%m-%d %H:%M:%S")
    local json_str = string.format(json_template, sysbench.rand.uniform(20.0, 30.0))

    stmt:execute(now, prefix_val, guid, json_str)

    if i % 1000 == 0 then
      print(string.format("Inserted %d/%d rows", i, sysbench.opt.table_size))
    end
  end

  stmt:close()
  print("=== Prepare phase complete ===")
end

function cleanup()
  print("Dropping ts_data table...")
  con:query("DROP TABLE IF EXISTS ts_data;")
end
