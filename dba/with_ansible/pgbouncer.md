# ⚙️ Instructable: Deploying and Managing pgBouncer in a Patroni Cluster

## 🧠 Overview

This guide explains how to **install, configure, and manage pgBouncer** across all nodes in a Patroni-based PostgreSQL HA cluster.  
pgBouncer acts as a **lightweight connection pooler** between clients and PostgreSQL instances, improving performance and reducing connection overhead.

We’ll use **Ansible** to ensure consistent deployment and management across all nodes (`pg1`, `pg2`, `pg3`).

---

## 🧾 Why pgBouncer?

PostgreSQL spawns a new backend process per connection. In high concurrency systems, this causes memory and CPU overhead.  
pgBouncer pools connections, reuses backends, and maintains lightweight client sessions, providing:

- Faster connection establishment  
- Improved resource efficiency  
- Load balancing and HA-friendly failover  
- Integration with Patroni for seamless topology changes  

---

## 🧱 Prerequisites

- A running **Patroni HA cluster** (`pg1`, `pg2`, `pg3`)  
- Ansible control node configured with SSH access to all DB servers  
- Passwordless SSH or proper key-based authentication  
- Inventory file containing host groups (`pg_nodes`)  

---

## 📦 Step 1 — Create the Ansible Playbook

Create `playbooks/pgbouncer.yml`:

```yaml
---
- name: Deploy pgBouncer across Patroni nodes
  hosts: pg_nodes
  become: yes
  tasks:
    - name: Install pgBouncer
      apt:
        name: pgbouncer
        state: present
        update_cache: yes

    - name: Ensure pgBouncer config directory exists
      file:
        path: /etc/pgbouncer
        state: directory
        owner: postgres
        group: postgres
        mode: "0755"

    - name: Deploy pgbouncer.ini
      copy:
        dest: /etc/pgbouncer/pgbouncer.ini
        content: |
          [databases]
          postgres = host=127.0.0.1 port=5432 dbname=postgres user=postgres password=postgres

          [pgbouncer]
          listen_addr = 0.0.0.0
          listen_port = 6432
          auth_type = md5
          auth_file = /etc/pgbouncer/userlist.txt
          logfile = /var/log/pgbouncer/pgbouncer.log
          pidfile = /var/run/pgbouncer/pgbouncer.pid
          admin_users = postgres
          pool_mode = transaction
          max_client_conn = 500
          default_pool_size = 100
          reserve_pool_size = 20
          reserve_pool_timeout = 5
          server_idle_timeout = 30
          server_reset_query = DISCARD ALL

    - name: Deploy userlist.txt
      copy:
        dest: /etc/pgbouncer/userlist.txt
        content: |
          "postgres" "postgres"

      mode: "0600"
      owner: postgres
      group: postgres

    - name: Ensure log and pid directories exist
      file:
        path: "{{ item }}"
        state: directory
        owner: postgres
        group: postgres
        mode: "0755"
      with_items:
        - /var/log/pgbouncer
        - /var/run/pgbouncer

    - name: Enable and start pgBouncer
      systemd:
        name: pgbouncer
        enabled: yes
        state: started
```

---

## 🗂 Step 2 — Inventory Example

Example `inventory.yml`:
```yaml
all:
  children:
    pg_nodes:
      hosts:
        pg1: { ansible_host: 192.168.2.5, ansible_user: ubuntu }
        pg2: { ansible_host: 192.168.2.6, ansible_user: ubuntu }
        pg3: { ansible_host: 192.168.2.7, ansible_user: ubuntu }
  vars:
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no"
```

---

## ▶️ Step 3 — Run the Playbook

From the control node:
```bash
ansible-playbook -i ../inventory.yml pgbouncer.yml
```

You’ll see output like:
```
TASK [Install pgBouncer] ... ok
TASK [Deploy pgbouncer.ini] ... changed
TASK [Enable and start pgBouncer] ... ok
```

---

## 🧩 Step 4 — Troubleshooting common issues

### 1️⃣ Missing directories
If you see:
```
FATAL Cannot open logfile: '/var/log/pgbouncer/pgbouncer.log': No such file or directory
```
Create required directories:
```bash
sudo mkdir -p /var/log/pgbouncer /var/run/pgbouncer
sudo chown postgres:postgres /var/log/pgbouncer /var/run/pgbouncer
sudo systemctl restart pgbouncer
```

### 2️⃣ Service failure on start
Run:
```bash
sudo journalctl -xeu pgbouncer.service | tail -n 30
```
Look for permission or configuration path issues.

### 3️⃣ Check service status
```bash
sudo systemctl status pgbouncer -l
```

---

## 🧪 Step 5 — Verify pgBouncer functionality

Check listening port:
```bash
sudo ss -tulpn | grep 6432
```
Expected:
```
LISTEN 0 128 0.0.0.0:6432 *:* users:(("pgbouncer",pid=12345,fd=3))
```

Connect through pgBouncer:
```bash
psql -h 127.0.0.1 -p 6432 -U postgres
```

Inside psql:
```sql
SHOW VERSION;
SHOW POOLS;
SHOW CLIENTS;
```

---

## 🔁 Step 6 — Integrate with Patroni

pgBouncer does **not** interfere with Patroni leadership election but should always point to the **virtual IP, HAProxy, or DNS entry** that routes to the current leader.  
Alternatively, each node’s pgBouncer can serve **local applications** pointing to localhost:6432.

You can include a dynamic configuration section in `/etc/pgbouncer/pgbouncer.ini` such as:
```
postgres = host=pg1 port=5432 user=postgres password=postgres
```

and later automate DNS updates for failover.

---

## 🧾 Step 7 — Rolling Restart with Ansible

To restart pgBouncer on all nodes safely:
```bash
ansible -i ../inventory.yml pg_nodes -m systemd -a "name=pgbouncer state=restarted"
```

This ensures minimal downtime across all nodes.

---

## ✅ Summary

| Step | Action | Description |
|------|---------|-------------|
| 1 | Create playbook | Define Ansible pgBouncer deployment |
| 2 | Configure inventory | List Patroni nodes |
| 3 | Run deployment | Install and configure pgBouncer |
| 4 | Fix startup issues | Handle log/pid directory setup |
| 5 | Verify service | Confirm it listens on port 6432 |
| 6 | Integrate with Patroni | Point pgBouncer to leader or local DB |
| 7 | Rolling restart | Manage updates safely via Ansible |

---

## 🧠 Notes
- Use **pool_mode = transaction** for most workloads.  
- Adjust `max_client_conn` and `default_pool_size` based on hardware capacity.  
- pgBouncer logs are stored under `/var/log/pgbouncer/pgbouncer.log`.  
- Always validate after Patroni topology changes with:
  ```bash
  patronictl -c /etc/patroni/patroni.yml list
  ```

---
