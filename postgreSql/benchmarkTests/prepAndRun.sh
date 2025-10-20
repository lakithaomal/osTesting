sysbench \
  --config-file=sysbench.cfg \
  --lua-script=tsdb_write.lua \
  prepare

### Run Phase (Execute the Workload)

sysbench \
  --config-file=sysbench.cfg \
  --lua-script=tsdb_write.lua \
  run

# This approach simplifies the command line dramatically, 
# keeps sensitive information out of the command history,
# and allows you to easily manage multiple testing 
# environments by switching the config file.