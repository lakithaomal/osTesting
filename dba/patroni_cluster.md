# 🥉 Patroni + etcd + PostgreSQL + MinIO (Full HA Cluster)
> _A complete hands-on guide for deploying and understanding a PostgreSQL High-Availability (HA) cluster using Patroni, etcd, Docker, and MinIO._

---

## 🌍 1. Introduction

In this guide, we’ll build a **3-node PostgreSQL HA cluster** coordinated by **etcd** and managed by **Patroni**, complete with **automatic failover** and **streaming replication** — just like production cloud systems.  
We’ll also attach **MinIO**, an open-source S3-compatible storage service, for future integration with backup tools such as **pgBackRest** or **WAL-G**.

This exact configuration was successfully run on **macOS (Apple Silicon)** using Docker Compose, and all containers were verified to communicate correctly.

---

## 🤭 2. Why This Stack?

| Component | Purpose | Why It’s Needed |
|------------|----------|-----------------|
| 🧠 **etcd** | A distributed key-value store | Patroni uses it for leader election and coordination. It’s the “brain” of the cluster. |
| 🐘 **PostgreSQL** | The actual database engine | Stores your data, executes SQL, and provides durability and ACID compliance. |
| 🤖 **Patroni** | PostgreSQL cluster manager | Wraps PostgreSQL to provide health checks, replication setup, auto-failover, and dynamic config propagation. |
| 💿 **MinIO** | S3-compatible object storage | Simulates AWS S3 for local backups and WAL archiving. |
| ⚙️ **Docker Compose** | Multi-container orchestration | Ensures everything launches, networks, and persists predictably. |

---

## 🧱 3. Architecture at a Glance

```
                    ┌──────────────────────────────────────┐
                    │             etcd cluster             │
                    │  Keeps cluster state & leader info   │
                    │  /service/pg-cluster/...             │
                    └─────────┬─────────┬──────────────────┘
                              │         │
       ┌──────────────────────┘         └───────────────────┐
       │                                                    │
 ┌────────────┐                                        ┌────────────┐
 │ Patroni1   │                                        │ Patroni3   │
 │ PostgreSQL │                                        │ PostgreSQL │
 │ Replica    │                                        │ Replica    │
 │ REST:8008  │                                        │ REST:8012  │
 │ PG:5435    │                                        │ PG:5437    │
 └─────┬──────┘                                        └───┬────────┘
       │                      WAL streaming                │
       └───────────────────────────────────────────────────┘
                                   ▲
                                   │
                             ┌────────────┐
                             │ Patroni2   │
                             │ PostgreSQL │
                             │ Primary    │
                             │ REST:8010  │
                             │ PG:5436    │
                             └────────────┘
```

---

## 🐳 4. Docker Images That Worked (✅ Verified)

| Container | Image | Version / Digest | Description |
|------------|--------|------------------|--------------|
| 🧠 **etcd1, etcd2, etcd3** | `quay.io/coreos/etcd:v3.5.16` | ✅ `v3.5.16` | Stable etcd cluster — Raft-based consensus. |
| 🤖 **patroni1, patroni2, patroni3** | `patroni:local` | ✅ Built from `ubuntu:24.04` + `Patroni 4.1.0` + `PostgreSQL 17.6` | Custom-built container controlling Postgres. |
| 💿 **minio** | `minio/minio:RELEASE.2024-10-02T17-50-41Z` | ✅ October 2024 build | Lightweight local S3-compatible backup target. |

---

## ⚙️ 5. Build the Patroni Image

```bash
docker build -t patroni:local .
```
This image bundles **PostgreSQL 17.6**, **Patroni 4.1.0**, and etcd client utilities.

---

## 🥉 6. The Docker Compose File

```yaml
version: "3.9"

services:
  # etcd cluster definition ...
  # patroni nodes definition ...
  # minio storage definition ...

volumes:
  minio_data:
networks:
  pgnet:
```
*(See full file in repo for details — defines 7 containers total.)*

---

## 🚀 7. Bring It All Up

```bash
docker compose up -d
docker ps
```

Expected running containers:
```
etcd1, etcd2, etcd3, patroni1, patroni2, patroni3, minio
```

---

## 🤩 8. Validation Steps

### ✅ etcd Health
```bash
docker exec -it etcd1 etcdctl endpoint health --cluster
```

### ✅ Patroni Roles
```bash
curl http://localhost:8008 | jq '.role'
curl http://localhost:8010 | jq '.role'
curl http://localhost:8012 | jq '.role'
```
Expected output:
```
"replica"
"primary"
"replica"
```

### ✅ PostgreSQL Check
```bash
psql -h localhost -p 5436 -U postgres -c "SELECT pg_is_in_recovery();"
```
`f` = primary, `t` = replica.

---

## ⚡ 9. Failover Test

```bash
docker stop patroni2
sleep 10
curl http://localhost:8008 | jq '.role'
curl http://localhost:8010 | jq '.role'
curl http://localhost:8012 | jq '.role'
```
🚀 A new node will automatically become primary.

---

## 🛠️ 10. Cluster Introspection

List Patroni keys in etcd:
```bash
docker exec -it etcd1 etcdctl get /service/pg-cluster --prefix
```
Sample output:
```
/service/pg-cluster/initialize
/service/pg-cluster/leader
/service/pg-cluster/members/patroni1
/service/pg-cluster/members/patroni2
/service/pg-cluster/members/patroni3
```

---

## 💿 11. Optional: MinIO Interface
Access:
- Web Console: http://localhost:9001  
- API Endpoint: http://localhost:9000  
Credentials:
```
admin / password
```

---

## 🥳 12. Cleanup
```bash
docker compose down -v
docker system prune -f
```

---

## 🔍 13. Summary Table (Verified Build)

| Service | Container | Image | Role | Ports | Status |
|----------|------------|--------|-------|--------|---------|
| etcd1 | etcd1 | quay.io/coreos/etcd:v3.5.16 | Cluster member | 2379–2380 | ✅ Healthy |
| etcd2 | etcd2 | quay.io/coreos/etcd:v3.5.16 | Cluster member | 2379–2380 | ✅ Healthy |
| etcd3 | etcd3 | quay.io/coreos/etcd:v3.5.16 | Cluster member | 2379–2380 | ✅ Healthy |
| patroni1 | patroni1 | patroni:local | Replica | 5435 / 8008 | ✅ Streaming |
| patroni2 | patroni2 | patroni:local | Primary | 5436 / 8010 | ✅ Leader |
| patroni3 | patroni3 | patroni:local | Replica | 5437 / 8012 | ✅ Streaming |
| minio | minio | minio/minio:RELEASE.2024-10-02T17-50-41Z | S3 Backup Target | 9000–9001 | ✅ Running |

---

## 🧠 14. Key Takeaways

| Concept | Explanation |
|----------|--------------|
| **Patroni** | Adds self-healing logic to PostgreSQL using DCS coordination. |
| **etcd** | Fault-tolerant KV store (Raft protocol) where Patroni stores leadership leases. |
| **Streaming Replication** | Replicas continuously stream WAL logs from the leader. |
| **Automatic Failover** | Triggered when Patroni loses etcd leadership heartbeat. |
| **Docker Networking** | All nodes share the `pgnet` overlay network, simulating a LAN. |
| **MinIO Integration** | Enables safe S3-style testing for backup and restore tools. |

---

**End of Guide**  
_Developed and verified on macOS + Docker Engine 27.0_

