
# 🧭 End-to-End Tutorial: Deploying a Highly-Available PostgreSQL 16 Cluster with Patroni + etcd + Ansible

## 1️⃣ Overview

**Cluster topology**
| Node | Role | Host IP | Key services |
|------|------|----------|---------------|
| **pg1** | Primary | 192.168.2.5 | PostgreSQL 16 + Patroni (Leader) |
| **pg2** | Replica 1 | 192.168.2.6 | PostgreSQL 16 + Patroni (Follower) |
| **pg3** | Replica 2 | 192.168.2.7 | PostgreSQL 16 + Patroni (Follower) |
| **etcd1–3** | DCS cluster | 192.168.2.2–.4 | etcd 3.4 (x3 nodes) |

**Core components**
- Patroni 4.1.0  
- PostgreSQL 16.10 (Ubuntu 24.04 aarch64)  
- etcd 3.4.x (as DCS backend)  
- systemd service units for all  
- Ansible role set from ObjectSpectrum’s `pgCluster` repository  

---

## 2️⃣ Ansible deployment

### Step 1 – Inventory and playbook
Inventory file (`hosts.ini`):
```ini
[etcd]
etcd1 ansible_host=192.168.2.2
etcd2 ansible_host=192.168.2.3
etcd3 ansible_host=192.168.2.4

[postgres]
pg1 ansible_host=192.168.2.5
pg2 ansible_host=192.168.2.6
pg3 ansible_host=192.168.2.7
```

Run the playbook:
```bash
ansible-playbook site.yml -l etcd,postgres
```

### Step 2 – Packages and services
Each node installs:
- `postgresql-16`, `patroni`, `pgbackrest`
- `etcd` (for the DCS)
- systemd units for both `etcd` and `patroni`

---

## 3️⃣ Patroni configuration

File: `/etc/patroni/patroni.yml`
```yaml
scope: pg-cluster
namespace: /service/pg-cluster/
name: pg1                    # unique per node

restapi:
  listen: 0.0.0.0:8008
  connect_address: 192.168.2.5:8008

etcd:
  hosts: 192.168.2.2:2379,192.168.2.3:2379,192.168.2.4:2379

bootstrap:
  dcs:
    postgresql:
      parameters:
        max_connections: 100
        wal_level: replica
        hot_standby: on
    slots: {}
  initdb:
    - encoding: UTF8
    - data-checksums

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 192.168.2.5:5432
  data_dir: /var/lib/postgresql/16/data
  bin_dir: /usr/lib/postgresql/16/bin
  authentication:
    replication:
      username: replicator
      password: somepassword
```

---

## 4️⃣ Problems and fixes

| # | Issue | Symptom | Root Cause | Fix |
|--|--|--|--|--|
| 1 | **Patroni bootstrap failed** | `Failed to bootstrap cluster` | Pre-existing `/var/lib/postgresql/16/data` | Stopped and disabled `postgresql.service`, cleared data dir, restarted Patroni |
| 2 | **Port conflict (5432)** | `could not bind IPv4 address` | Both PostgreSQL and Patroni using 5432 | Disabled vanilla `postgresql.service` |
| 3 | **Missing etcdctl** | `Command not found` | Minimal Ubuntu install | Installed `etcd-client` |
| 4 | **Replica panic** | `no valid checkpoint record` | Incomplete basebackup | Deleted data dir and restarted Patroni to reclone |
| 5 | **patronictl warning** | `No cluster names provided` | Config not specified | Used `patronictl -c /etc/patroni/patroni.yml list` |
| 6 | **Replica query errors** | Invalid column names | Postgres 16 column changes | Updated queries to use `written_lsn`, `flushed_lsn` |

---

## 5️⃣ Validation

### Primary (pg1)
```bash
sudo patronictl -c /etc/patroni/patroni.yml list
```

### Replication slot and status
```bash
sudo -u postgres psql -X -c "SELECT slot_name, active, restart_lsn FROM pg_replication_slots;"
sudo -u postgres psql -X -c "SELECT application_name, client_addr, state, sync_state, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;"
```

### Standby checks
```bash
sudo -u postgres psql -X -c "SELECT pg_is_in_recovery();"
sudo -u postgres psql -X -c "SELECT * FROM pg_stat_wal_receiver;"
```

### Data replication test
```bash
sudo -u postgres psql -X -c "CREATE TABLE IF NOT EXISTS ha_smoke(t timestamptz default now(), node text, msg text);"
sudo -u postgres psql -X -c "INSERT INTO ha_smoke(node,msg) VALUES ('pg1','hello');"
sudo -u postgres psql -X -c "SELECT * FROM ha_smoke ORDER BY t DESC LIMIT 1;"
```

---

## 6️⃣ Synchronous replication and failover

Enable sync replication:
```yaml
synchronous_mode: true
synchronous_node_count: 1
```
Reload Patroni:
```bash
sudo patronictl -c /etc/patroni/patroni.yml reload pg1
sudo patronictl -c /etc/patroni/patroni.yml list
```

Trigger manual failover:
```bash
sudo patronictl -c /etc/patroni/patroni.yml failover
```

---

## 7️⃣ Maintenance tips
- Always disable vanilla `postgresql.service`.
- Remove stale `/var/lib/postgresql/16/data.failed` before bootstrap.
- Inspect logs:  
  - `journalctl -u patroni -f`  
  - `/var/lib/postgresql/16/data/pg_log/patroni.log`
- Use `etcdctl --endpoints=http://192.168.2.2:2379,... get /service/pg-cluster --prefix` for DCS inspection.

---

## 8️⃣ Cluster summary
```
+ Cluster: pg-cluster ---------------------------------------------+
| Member | Host        | Role    | State     | TL | LSN       | Lag |
|--------+-------------+---------+-----------+----+-----------+-----|
| pg1    | 192.168.2.5 | Leader  | running   |  1 | 0/9000060 |  0  |
| pg2    | 192.168.2.6 | Replica | streaming |  1 | 0/9000060 |  0  |
| pg3    | 192.168.2.7 | Replica | streaming |  1 | 0/9000060 |  0  |
+------------------------------------------------------------------+
```

---

## 9️⃣ Next steps
- Integrate `pgBackRest` for S3/MinIO backups.  
- Add `pgBouncer` for connection pooling.  
- Benchmark with `sysbench`.  
- Test rolling configuration changes via Ansible and Patroni reloads.
