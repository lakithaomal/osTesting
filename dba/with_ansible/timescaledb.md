# 🧩 Instructable: Adding TimescaleDB Extension to a Patroni Cluster

## 🧠 Overview

This guide walks through how to **safely enable the TimescaleDB extension** across a **high-availability Patroni PostgreSQL 16 cluster**, while maintaining uptime and data consistency.

We’ll:
- Install TimescaleDB on each node  
- Update Patroni configuration (`shared_preload_libraries`)  
- Perform a **rolling restart** using `patronictl` or Ansible  
- Verify TimescaleDB activation cluster-wide  

---

## 🧱 Prerequisites

- A working **Patroni HA cluster** with etcd and PostgreSQL 16.  
- SSH or Ansible access to all DB nodes.  
- Sudo privileges.  
- Network access between nodes (TCP ports 2379, 5432, 8008).  

---

## ⚙️ Step 1 — Add the TimescaleDB repository

Perform this on **all PostgreSQL nodes** (`pg1`, `pg2`, `pg3`).

```bash
sudo apt update
sudo apt install gnupg postgresql-common apt-transport-https lsb-release wget -y

echo "deb [signed-by=/usr/share/keyrings/timescaledb.gpg] https://packagecloud.io/timescale/timescaledb/ubuntu $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/timescaledb.list

wget -qO- https://packagecloud.io/timescale/timescaledb/gpgkey | gpg --dearmor | sudo tee /usr/share/keyrings/timescaledb.gpg > /dev/null
```

Then install the Timescale package:
```bash
sudo apt update
sudo apt install timescaledb-2-postgresql-16 -y
```

Verify installation:
```bash
ls /usr/lib/postgresql/16/lib/timescaledb.so
```
✅ The `.so` file must exist on all nodes.

---

## 🪶 Step 2 — Update Patroni configuration

Edit `/etc/patroni/patroni.yml` on **any one node** (typically pg1):

Find:
```yaml
postgresql:
  parameters:
    wal_level: replica
    hot_standby: on
```

Add or modify this line:
```yaml
    shared_preload_libraries: timescaledb
```

You can use `yq` or `ansible.builtin.lineinfile` to automate the change across all nodes.

---

## 🔄 Step 3 — Reload Patroni configuration

After editing, apply the updated configuration:
```bash
sudo patronictl -c /etc/patroni/patroni.yml reload pg-cluster
```

Check status:
```bash
sudo patronictl -c /etc/patroni/patroni.yml list
```

You’ll now see:
```
| Pending restart | shared_preload_libraries: ->timescaledb |
```

This means Patroni knows the config changed and that a restart is required.

---

## ♻️ Step 4 — Perform a rolling restart

You can do this **manually** or via **Ansible**.

### Option A — Manual method
Restart replicas first:
```bash
sudo patronictl -c /etc/patroni/patroni.yml restart pg-cluster pg2
sudo patronictl -c /etc/patroni/patroni.yml restart pg-cluster pg3
```
Then restart the leader:
```bash
sudo patronictl -c /etc/patroni/patroni.yml restart pg-cluster pg1
```

If prompted:
```
When should the restart take place [...] [now]: 
Are you sure you want to restart members pg2? [y/N]: y
```
Just press **Enter** to accept defaults and confirm.

### Option B — Automated (recommended)
Run your `rolling_restart.yml` playbook:
```bash
ansible-playbook -i ../inventory.yml rolling_restart.yml
```

This handles:
- Restart order (replicas → leader)
- Health checks
- Automatic delay and retries  

---

## 🔍 Step 5 — Verify cluster and Timescale activation

After all nodes restart:
```bash
sudo patronictl -c /etc/patroni/patroni.yml list
```
✅ All nodes should show `running` and no pending restart.

Then, confirm Timescale is preloaded:
```bash
sudo -u postgres psql -X -c "SHOW shared_preload_libraries;"
```
Expected output:
```
 shared_preload_libraries
--------------------------
 timescaledb
(1 row)
```

Create the Timescale extension (only once on the primary):
```bash
sudo -u postgres psql -X -c "CREATE EXTENSION IF NOT EXISTS timescaledb;"
```

---

## 🧩 Step 6 — Confirm replication continuity

On any node:
```bash
sudo -u postgres psql -X -c "SELECT application_name, state, sync_state FROM pg_stat_replication;"
```
You should see both replicas streaming normally.

---

## 🧾 Step 7 — Optional validation (Ansible)

If you want, you can extend your `rolling_restart.yml` with this validation:

```yaml
- name: Verify TimescaleDB preload on all nodes
  shell: sudo -u postgres psql -tAc "SHOW shared_preload_libraries;"
  register: preload_result
  changed_when: false

- name: Print preload library status
  debug:
    msg: "{{ inventory_hostname }} → {{ preload_result.stdout }}"
```

---

## ✅ Summary

| Step | Action | Description |
|------|---------|-------------|
| 1 | Add repo | Add Timescale package repo |
| 2 | Install package | Install TimescaleDB for PostgreSQL 16 |
| 3 | Edit Patroni YAML | Add `shared_preload_libraries: timescaledb` |
| 4 | Reload Patroni | Register config change |
| 5 | Rolling restart | Restart replicas → leader |
| 6 | Verify | Check `shared_preload_libraries` and `CREATE EXTENSION` |
| 7 | Optional | Verify via Ansible automation |

---
