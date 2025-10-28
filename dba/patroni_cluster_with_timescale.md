# 🧩 Patroni + etcd + PostgreSQL + TimescaleDB (+ MinIO)
_A Complete Hands-On Guide for Building a High-Availability, Time-Series-Ready PostgreSQL Cluster with Patroni 4.1.0, PostgreSQL 17.6, TimescaleDB 2.x, and etcd 3.5.16_

---

## 🏗️ 1. Overview

This guide extends the original **Patroni + etcd + PostgreSQL + MinIO** cluster to include **TimescaleDB** for native time-series support — preserving full Patroni HA behavior (leader election, streaming replication, and automatic failover).  
All builds and tests were verified on **macOS (Apple Silicon)** using **Docker Compose v2.29+**.

---

## ⚙️ 2. Core Components

| Component | Role | Notes |
|------------|------|-------|
| 🧠 **etcd (×3)** | Distributed key-value store | Patroni stores cluster state and elects leaders here |
| 🤖 **Patroni (×3)** | Cluster manager | Wraps PostgreSQL, manages replication/failover/config |
| 🐘 **PostgreSQL 17.6 + TimescaleDB 2.x** | Database engine | Primary + replica topology; time-series extension enabled |
| 💾 **MinIO (optional)** | S3-compatible object storage | For backups (pgBackRest / WAL-G future use) |
| 🐋 **Docker Compose** | Orchestration | One command to deploy the full HA stack |

---

## 🧱 3. Architecture

```
┌──────────────────────────────┐
│         etcd cluster         │
│  /service/pg-cluster/...     │
│  3 nodes, Raft consensus     │
└────────────┬─────────────────┘
             │
   ┌─────────┼─────────────┐
   │                       │
┌──────────────┐     ┌──────────────┐
│ Patroni1     │     │ Patroni3     │
│ PostgreSQL   │     │ PostgreSQL   │
│ Replica      │     │ Replica      │
│ REST 8008 PG 5435 │ REST 8012 PG 5437 │
└──────┬────────────┘ └──────┬──────────┘
       │  WAL streaming      │
       └──────────┬──────────┘
                  │
            ┌──────────────┐
            │ Patroni2     │
            │ PostgreSQL   │
            │ **Primary**  │
            │ REST 8010 PG 5436 │
            └──────────────┘
```

---

## 🐳 4. Verified Images

| Service | Image | Version / Digest | Platform | Status |
|----------|--------|-----------------|-----------|---------|
| etcd1–3 | `quay.io/coreos/etcd:v3.5.16` | v3.5.16 | linux/arm64 | ✅ |
| patroni1–3 | `patroni:local-timescale` | PostgreSQL 17.6 + TimescaleDB 2.x + Patroni 4.1.0 | linux/arm64 | ✅ |
| minio | `minio/minio:RELEASE.2024-10-02T17-50-41Z` | Oct 2024 build | linux/arm64 | ✅ |

---

## 🧩 5. Building the Timescale-Enabled Patroni Image

### Step 1 — Clone Patroni

```bash
git clone https://github.com/zalando/patroni.git
cd patroni
```

### Step 2 — Create `Dockerfile.timescale`

```dockerfile
# =============================================================================
# Patroni + PostgreSQL 17 + TimescaleDB build (ARM64/AMD64)
# =============================================================================
ARG PG_MAJOR=17
FROM postgres:${PG_MAJOR}

ARG ETCDVERSION=3.3.13
ARG PGHOME=/home/postgres
ARG PGDATA=$PGHOME/data
ENV LC_ALL=C.UTF-8 LANG=C.UTF-8

# --- System setup + TimescaleDB install --------------------------------------
RUN set -ex  && export DEBIAN_FRONTEND=noninteractive  && apt-get update -y  && apt-get install -y wget gnupg ca-certificates lsb-release curl locales  && wget -qO- https://packagecloud.io/timescale/timescaledb/gpgkey | gpg --dearmor -o /usr/share/keyrings/timescale.gpg  && echo "deb [signed-by=/usr/share/keyrings/timescale.gpg] https://packagecloud.io/timescale/timescaledb/debian/ $(lsb_release -cs) main"       > /etc/apt/sources.list.d/timescaledb.list  && apt-get update -y  && apt-get install -y postgresql-${PG_MAJOR}-timescaledb  && apt-get install -y vim curl jq haproxy sudo python3-pip net-tools iputils-ping dumb-init busybox  && pip3 install --no-cache-dir psycopg[binary] --break-system-packages  && locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8  && mkdir -p "$PGHOME" /patroni /run/haproxy  && curl -sL "https://github.com/coreos/etcd/releases/download/v${ETCDVERSION}/etcd-v${ETCDVERSION}-linux-$(dpkg --print-architecture).tar.gz"       | tar xz -C /usr/local/bin --strip=1 --wildcards --no-anchored etcd etcdctl  && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# --- Copy Patroni source and config ------------------------------------------
COPY patroni /patroni/
COPY patroni*.py docker/entrypoint.sh /
RUN sed -i 's/env python/&3/' /patroni*.py && chmod +x /entrypoint.sh
USER postgres
ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
```

### Step 3 — Build the image
```bash
docker build -t patroni:local-timescale -f Dockerfile.timescale .
```

---

## 🪲 6. Issues Encountered & Fixes

| Problem | Root Cause | Fix Applied |
|----------|-------------|-------------|
| PEP 668 – “externally-managed environment” | Debian 12 blocks `pip install` system-wide | Added `--break-system-packages` flag |
| `localedef: translit_neutral missing` | Locale files pruned too aggressively | Relaxed locale cleanup, retained UTF-8 data |
| `data directory has wrong ownership` | `/tmp/pgtest` owned by root | Re-`chown` to postgres |
| `invalid permissions (0755)` | `initdb` demands 0700 or 0750 | Fixed with `chmod 0700 /tmp/pgtest` |
| `not a valid data directory (PG_VERSION missing)` | Attempted to start before `initdb` | Added explicit `initdb -D /tmp/pgtest` |
| `CREATE EXTENSION` fails on replica | Replicas are read-only | Executed only on the leader (primary) |
| Patroni “waiting for leader to bootstrap” | Race during etcd quorum formation | Restarted containers after etcd ready |
| File exists `/home/postgres/data/..` | Stale data directory between runs | Added `docker compose down -v` before redeploy |

---

## 🧰 7. Updated Docker Compose File

Includes `PATRONI_POSTGRESQL_PARAMETERS_SHARED_PRELOAD_LIBRARIES=timescaledb` in each Patroni node.

---

## 🚀 8. Deployment

```bash
docker compose up -d
docker ps
```

Expected containers:
```
etcd1, etcd2, etcd3, patroni1, patroni2, patroni3, minio
```

---

## ✅ 9. Validation & Testing

### Cluster roles
```bash
curl -s http://localhost:8008/role
curl -s http://localhost:8010/role
curl -s http://localhost:8012/role
```

Output:
```
replica
primary
replica
```

### Timescale preload check
```bash
psql -h localhost -p 5435 -U postgres -c "SHOW shared_preload_libraries;"
```
→ `timescaledb`

### Create TimescaleDB extension (on leader only)
```bash
psql -h localhost -p 5437 -U postgres -c "CREATE EXTENSION IF NOT EXISTS timescaledb;"
```

### Verify installation
```bash
psql -h localhost -p 5437 -U postgres -c "\dx"
```

Expected:
```
 Name | Version | Schema | Description
------+----------+--------+-----------------------------
 timescaledb | 2.x.x | public | Enables scalable inserts...
```

### Test hypertable
```bash
psql -h localhost -p 5437 -U postgres -d postgres -c "
CREATE TABLE metrics(time timestamptz, value double precision);
SELECT create_hypertable('metrics','time');
INSERT INTO metrics VALUES (now(),42.0);
SELECT * FROM metrics;"
```

Replica check:
```bash
psql -h localhost -p 5435 -U postgres -d postgres -c "SELECT * FROM metrics;"
```

---

## 💡 10. Failover Demo

```bash
docker stop patroni3
sleep 10
curl http://localhost:8008/role
curl http://localhost:8010/role
curl http://localhost:8012/role
```

A replica automatically promotes to primary.

---

## 🧠 11. Lessons Learned

1. Always include `shared_preload_libraries=timescaledb` for all nodes.  
2. Only the leader can execute `CREATE EXTENSION`.  
3. On macOS ARM64, use the official Timescale `packagecloud` repo.  
4. For pip installs inside Debian 12 containers, use `--break-system-packages`.  
5. Keep UTF-8 locales intact; avoid removing `/usr/share/i18n`.  
6. Clear persistent volumes before redeploy (`docker compose down -v`).  
7. Verify roles via REST before DDL operations.  

---

## 📊 12. Final Cluster State

| Node | Role | Ports | Timescale Enabled | Notes |
|------|------|--------|------------------|-------|
| patroni1 | Replica | 5435 / 8008 | ✅ | Streaming |
| patroni2 | Replica | 5436 / 8010 | ✅ | Streaming |
| patroni3 | Primary | 5437 / 8012 | ✅ | Leader |
| etcd1–3 | DCS | 2379–2380 | — | Healthy quorum |
| minio | Storage | 9000–9001 | — | Optional S3 backend |

---

## 🧾 13. Cleanup

```bash
docker compose down -v
docker system prune -f
```

---

**End of Guide**  
_Developed and verified on macOS + Docker Engine 27.0 (ARM64)_  
_Based on Patroni 4.1.0  |  PostgreSQL 17.6  |  TimescaleDB 2.x  |  etcd 3.5.16  |  MinIO RELEASE.2024-10-02_
