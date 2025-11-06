
# 🧭 PostgreSQL High-Availability Cluster on Multipass (Etcd + Patroni + PgBouncer)

A complete guide to deploying a **3-node PostgreSQL HA cluster** with **automatic failover** and **connection pooling**, built using **Multipass**, **Ansible**, **Etcd**, **Patroni**, and **PgBouncer**.

---

## 📘 Table of Contents
- [1️⃣ Environment Overview](#1️⃣-environment-overview)
- [2️⃣ Launch Virtual Machines](#2️⃣-launch-virtual-machines)
- [3️⃣ Configure SSH Access](#3️⃣-configure-ssh-access)
- [4️⃣ Deploy Etcd Cluster](#4️⃣-deploy-etcd-cluster)
- [5️⃣ Deploy Patroni + PostgreSQL](#5️⃣-deploy-patroni--postgresql)
- [6️⃣ Deploy PgBouncer](#6️⃣-deploy-pgbouncer)
- [7️⃣ Validate Cluster Health](#7️⃣-validate-cluster-health)
- [8️⃣ Test Failover](#8️⃣-test-failover)
- [9️⃣ Reset or Re-initialize Cluster](#9️⃣-reset-or-re-initialize-cluster)
- [🔟 Verification Commands](#🔟-verification-commands)
- [🏁 Final Cluster Status](#🏁-final-cluster-status)
- [🚀 Next Steps](#🚀-next-steps)

---

## 1️⃣ Environment Overview

| Node | IP Address | Role |
|------|-------------|------|
| etcd1 | 192.168.2.23 | Etcd |
| etcd2 | 192.168.2.24 | Etcd |
| etcd3 | 192.168.2.25 | Etcd |
| pg1 | 192.168.2.26 | Patroni / PostgreSQL Leader |
| pg2 | 192.168.2.27 | Patroni Replica (Sync) |
| pg3 | 192.168.2.28 | Patroni Replica (Async) |

> 💡 All nodes run **Ubuntu 24.04 LTS**  
> Ansible is executed from the **host machine**.

---

## 2️⃣ Launch Virtual Machines

Install and verify Multipass:

```bash
brew install multipass
multipass version
```

Create six VMs:

```bash
multipass launch 24.04 --name etcd1
multipass launch 24.04 --name etcd2
multipass launch 24.04 --name etcd3
multipass launch 24.04 --name pg1
multipass launch 24.04 --name pg2
multipass launch 24.04 --name pg3
```

Confirm IP assignments:

```bash
multipass list
```

---

## 3️⃣ Configure SSH Access

Generate an SSH key pair:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519
```

Add your key to each VM:

```bash
for node in etcd1 etcd2 etcd3 pg1 pg2 pg3; do
  cat ~/.ssh/id_ed25519.pub | multipass exec $node -- bash -c 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys'
done
```

Verify with Ansible:

```bash
ansible all -i inventories/testing.yml -m ping
```

All hosts should return `pong`.

---

## 4️⃣ Deploy Etcd Cluster

Run the Etcd playbook:

```bash
ansible-playbook -i inventories/testing.yml playbooks/etcd.yml
```

Validate cluster health:

```bash
ETCDCTL_API=3 etcdctl --endpoints="http://192.168.2.23:2379,http://192.168.2.24:2379,http://192.168.2.25:2379" endpoint status --write-out=table
```

Expect all three endpoints to be **healthy**.

---

## 5️⃣ Deploy Patroni + PostgreSQL

Deploy the HA PostgreSQL stack:

```bash
ansible-playbook -i inventories/testing.yml playbooks/patroni.yml
```

This step:

- Installs **PostgreSQL 16** and **Patroni**
- Creates required directories:
  - `/etc/patroni`
  - `/var/lib/postgresql/data`
  - `/var/log/patroni`
- Registers and starts the `patroni.service`
- Bootstraps the first node as cluster **Leader**

Check service status:

```bash
sudo systemctl status patroni
```

List cluster members:

```bash
sudo patronictl -c /etc/patroni/patroni.yml list
```

---

## 6️⃣ Deploy PgBouncer

Deploy the PgBouncer connection pooler:

```bash
ansible-playbook -i inventories/testing.yml playbooks/pgbouncer.yml
```

Validate:

```bash
sudo systemctl status pgbouncer
ss -ltnp | grep 6432
```

Test connectivity:

```bash
psql -h 192.168.2.26 -p 6432 -U postgres
```

---

## 7️⃣ Validate Cluster Health

Check Patroni status:

```bash
sudo patronictl -c /etc/patroni/patroni.yml list
```

Expected output:

```
+ Cluster: pg-ha (...) +-----------+----+-------------+
| Member | Host | Role         | State     |
+--------+------+--------------+-----------+
| pg1    | ...  | Leader       | running   |
| pg2    | ...  | Sync Standby | streaming |
| pg3    | ...  | Replica      | streaming |
+--------+------+--------------+-----------+
```

Test REST API health:

```bash
curl http://192.168.2.26:8008/health
curl http://192.168.2.27:8008/health
curl http://192.168.2.28:8008/health
```

Expected JSON responses:
```json
{"state":"running","role":"Leader"}
{"state":"running","role":"Replica"}
```

---

## 8️⃣ Test Failover

Simulate leader failure:

```bash
sudo systemctl stop patroni  # run on pg1
sleep 10
sudo patronictl -c /etc/patroni/patroni.yml list
```

Expected behavior:
- `pg2` becomes **Leader**
- `pg3` remains **Replica**

Restart pg1 and confirm it rejoins as a replica.

---

## 9️⃣ Reset or Re-initialize Cluster

To clean up and redeploy:

```bash
sudo systemctl stop patroni
sudo rm -rf /etc/patroni /var/lib/postgresql/data /var/lib/postgresql/data.failed /var/log/patroni
sudo rm -f /etc/systemd/system/patroni.service
sudo systemctl daemon-reload
```

Clear Patroni keys in Etcd:

```bash
ETCDCTL_API=3 etcdctl --endpoints="http://192.168.2.23:2379,http://192.168.2.24:2379,http://192.168.2.25:2379" del --prefix /service/pg-ha/
```

Re-run playbooks to rebuild the cluster.

---

## 🔟 Verification Commands

| Action | Command |
|--------|----------|
| Cluster status | `sudo patronictl -c /etc/patroni/patroni.yml list` |
| Etcd status | `etcdctl endpoint status --write-out=table` |
| Health check | `curl http://<host>:8008/health` |
| Recovery mode | `sudo -u postgres psql -c "SELECT pg_is_in_recovery();"` |
| Replication slots | `sudo -u postgres psql -c "SELECT * FROM pg_replication_slots;"` |

---

## 🏁 Final Cluster Status

```
+ Cluster: pg-ha (...) +-----------+----+-------------+
| Member | Host | Role         | State     |
+--------+------+--------------+-----------+
| pg1    | ...  | Leader       | running   |
| pg2    | ...  | Sync Standby | streaming |
| pg3    | ...  | Replica      | streaming |
+--------+------+--------------+-----------+
```

✅ Automatic failover active  
✅ Synchronous replication verified  
✅ PgBouncer serving clients  
✅ Managed entirely with Ansible

---

