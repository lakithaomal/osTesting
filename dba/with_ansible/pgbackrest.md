# 🧭 Complete Setup Guide: pgBackRest + Patroni + Ansible

> 🎓 Beginner-to-intermediate walkthrough for setting up automated PostgreSQL HA backups  
> 🧩 Includes installation, configuration, and validation on **pg1 (leader)**, **pg2**, and **pg3**  
> 🧠 Tested on Ubuntu 22.04 with PostgreSQL 16 and Patroni  

---

## 🧩 1. What You’re Building

You’ll end up with a 3-node **PostgreSQL HA cluster** that:
- Is managed by **Patroni** (leader election, replication, failover)
- Has **pgBackRest** handling all backups and WAL (Write-Ahead Log) archiving
- Is deployed and configured **automatically** using **Ansible**

```
pg1  → Leader  →  WAL archive + Backups
pg2  → Replica →  Replays WAL from pg1
pg3  → Replica →  Replays WAL from pg1
```

---

## ⚙️ 2. What Is WAL (Write-Ahead Logging)?

Every change in PostgreSQL is written to a **WAL file** before being applied to the data files.  
This guarantees:
- **Durability:** PostgreSQL can replay WAL logs if it crashes  
- **Replication:** Replicas stay in sync by streaming WALs  
- **Backups:** pgBackRest captures these logs so you can restore to any point in time  

> 🧠 Think of WAL as a “black-box flight recorder” for your database.

If your database crashes, pgBackRest replays the WAL files to restore the last consistent state.

---

## 🧱 3. Installing pgBackRest (Manual Setup First)

Before automating with Ansible, let’s understand what happens under the hood.

### 🟩 On each node (pg1, pg2, pg3):

#### 1️⃣ Install the package
```bash
sudo apt update
sudo apt install -y pgbackrest
```

#### 2️⃣ Check installation
```bash
pgbackrest --version
```
You should see:
```
pgBackRest 2.50
```

#### 3️⃣ Create directories
```bash
sudo mkdir -p /var/lib/pgbackrest /var/log/pgbackrest /etc/pgbackrest
sudo chown -R postgres:postgres /var/lib/pgbackrest /var/log/pgbackrest /etc/pgbackrest
sudo chmod 750 /var/lib/pgbackrest /var/log/pgbackrest
```

#### 4️⃣ Create config file on **pg1** (Leader)
```bash
sudo nano /etc/pgbackrest/pgbackrest.conf
```
Example:
```ini
[global]
repo1-path=/var/lib/pgbackrest
repo1-retention-full=2
repo1-retention-diff=2
start-fast=y
log-level-console=info
log-path=/var/log/pgbackrest

[pg-ha]
pg1-path=/var/lib/postgresql/16/data
pg1-port=5432
pg1-host=localhost
pg1-user=postgres
```

#### 5️⃣ Validate permissions
```bash
sudo ls -l /etc/pgbackrest/
```
Everything should be owned by `postgres:postgres`.

---

### ⚠️ Common Issues During Manual Install

| Problem | Cause | Fix |
|----------|--------|-----|
| `Permission denied` when reading `pgbackrest.conf` | You opened as non-root | Use `sudo` |
| `Unable to open missing file '/var/lib/postgresql/data/global/pg_control'` | Wrong Postgres data directory | Set correct path (`/var/lib/postgresql/16/data`) |
| `remote process terminated unexpectedly [255]` | pgBackRest tried to SSH to itself | Use `pg1-host=localhost` in config |
| Stanza fails to create | Database not running | Ensure Postgres is running before running `stanza-create` |

---

## 🧠 4. Integrating pgBackRest with Patroni

Add under `postgresql.parameters:` in `/etc/patroni/patroni.yml`:

```yaml
parameters:
    archive_mode: 'on'
    archive_command: 'pgbackrest --stanza=pg-ha archive-push %p'
    restore_command: 'pgbackrest --stanza=pg-ha archive-get %f %p'
```

> 🧠 Must be indented exactly **4 spaces** under `parameters:`.

---

## ⚒️ 5. Validate YAML Before Restarting Patroni

```bash
sudo python3 -c "import yaml; yaml.safe_load(open('/etc/patroni/patroni.yml')) or print('✅ YAML OK')"
```

If you get:
```
yaml.parser.ParserError: expected <block end>, but found '<block mapping start>'
```
Fix indentation under `parameters:`.

---

## 🔁 6. Restart Patroni & Verify

```bash
sudo systemctl restart patroni
sudo patronictl -c /etc/patroni/patroni.yml list
```

Expected:
```
+ Cluster: pg-cluster ----+-------------+---------+---------+
| Member | Host        | Role    | State   | TL | Lag     |
+--------+-------------+---------+---------+----+---------+
| pg1    | 192.168.2.5 | Leader  | running |  3 |         |
| pg2    | 192.168.2.6 | Replica | running |  3 | 0 bytes |
| pg3    | 192.168.2.7 | Replica | running |  3 | 0 bytes |
```

---

## 💾 7. Initialize pgBackRest (Leader Only)

On **pg1**:
```bash
sudo -u postgres pgbackrest --stanza=pg-ha --log-level-console=info stanza-create
```
Expected:
```
INFO: stanza-create command end: completed successfully
```

On **pg2 / pg3**:
```
sudo -u postgres pgbackrest info
```
Will show:
```
No stanzas exist in the repository.
```
✅ That’s fine — only pg1 creates it initially.

---

## 🤖 8. Automating with Ansible

### 🗂 Folder Layout
```
ansible-pg-ha/
├── inventory.yml
├── playbooks/pgbackrest.yml
└── roles/pgbackrest/
    ├── tasks/main.yml
    ├── templates/pgbackrest.conf.j2
    └── handlers/main.yml
```

### 🧩 inventory.yml
```yaml
all:
  children:
    pg_nodes:
      hosts:
        pg1:
          ansible_host: 192.168.2.5
        pg2:
          ansible_host: 192.168.2.6
        pg3:
          ansible_host: 192.168.2.7
```

### ⚙️ playbooks/pgbackrest.yml
```yaml
---
- name: Deploy pgBackRest across Patroni cluster
  hosts: pg_nodes
  become: yes
  vars:
    stanza_name: pg-ha
    pg_data_dir: /var/lib/postgresql/16/data
    pg_port: 5432
    patroni_config: /etc/patroni/patroni.yml
    repo_path: /var/lib/pgbackrest
    log_path: /var/log/pgbackrest
    pgbackrest_conf: /etc/pgbackrest/pgbackrest.conf

  roles:
    - pgbackrest
```

### 🧱 roles/pgbackrest/tasks/main.yml
```yaml
---
- name: Install pgBackRest
  apt:
    name: pgbackrest
    state: present
    update_cache: yes

- name: Ensure directories exist
  file:
    path: "{{ item }}"
    state: directory
    owner: postgres
    group: postgres
    mode: "0750"
  loop:
    - "{{ repo_path }}"
    - "{{ log_path }}"
    - "/etc/pgbackrest"

- name: Deploy pgBackRest config
  template:
    src: pgbackrest.conf.j2
    dest: "{{ pgbackrest_conf }}"
    owner: postgres
    group: postgres
    mode: "0640"

- name: Ensure Patroni archive_command configured
  blockinfile:
    path: "{{ patroni_config }}"
    insertafter: '^ {4}parameters:'
    marker: "    # {mark} ANSIBLE MANAGED BLOCK - pgbackrest"
    block: |
      archive_mode: 'on'
      archive_command: 'pgbackrest --stanza={{ stanza_name }} archive-push %p'
      restore_command: 'pgbackrest --stanza={{ stanza_name }} archive-get %f %p'
  notify: Restart Patroni

- name: Validate Patroni YAML
  command: python3 -c "import yaml,sys;yaml.safe_load(open('{{ patroni_config }}'))"
  register: patroni_yaml_check
  changed_when: false
  failed_when: patroni_yaml_check.rc != 0

- name: Initialize pgBackRest stanza (leader only)
  become: true
  become_user: postgres
  shell: |
    leader=$(patronictl -c {{ patroni_config }} list --format json | jq -r '.[] | select(.Role=="Leader") | .Member')
    mynode=$(hostname)
    if [ "$leader" = "$mynode" ]; then
      echo "Running stanza-create on leader $mynode"
      pgbackrest --stanza={{ stanza_name }} --log-level-console=info stanza-create
    else
      echo "Skipping stanza-create on replica $mynode"
    fi
  args:
    executable: /bin/bash
  changed_when: false
```

### Template (`templates/pgbackrest.conf.j2`)
```ini
[global]
repo1-path={{ repo_path }}
repo1-retention-full=2
repo1-retention-diff=2
start-fast=y
log-level-console=info
log-path={{ log_path }}

[{{ stanza_name }}]
pg1-path={{ pg_data_dir }}
pg1-port={{ pg_port }}
pg1-host=localhost
pg1-user=postgres
```

### Handler (`handlers/main.yml`)
```yaml
---
- name: Restart Patroni
  systemd:
    name: patroni
    state: restarted
```

---

## 🚀 9. Running the Playbook

```bash
ansible-playbook -i inventory.yml playbooks/pgbackrest.yml
```

Expected summary:
```
PLAY RECAP
pg1 : ok=7 changed=2 failed=0
pg2 : ok=7 changed=2 failed=0
pg3 : ok=7 changed=2 failed=0
```

---

## 🧪 10. Verify Everything

### Cluster state
```bash
sudo patronictl -c /etc/patroni/patroni.yml list
```

### Backup info
```bash
sudo -u postgres pgbackrest info
```

✅ pg1 shows:
```
stanza: pg-ha
status: ok
```

✅ pg2/pg3 may show:
```
No stanzas exist in the repository.
```

Sync repo manually:
```bash
sudo rsync -avz pg1:/var/lib/pgbackrest/ /var/lib/pgbackrest/
```

---

## 🩺 11. Troubleshooting Recap

| Issue | What Happened | Fix |
|-------|----------------|-----|
| YAML parser error | `parameters:` block misaligned | Ensure 4-space indentation |
| Patroni won’t start | Duplicate blockinfile entries | Delete extra blocks manually |
| `chmod: invalid mode 'A+user:postgres:rx:allow'` | sudo bug | Use both `become: true` and `become_user: postgres` |
| `No stanzas exist` | Only pg1 created stanza | Sync or shared repo |
| `remote process ... Permission denied` | Missing localhost host | Add `pg1-host=localhost` |
| pgBackRest missing | Template applied before install | Ensure apt runs first |

---

## 🧭 12. Node-by-Node Summary

| Step | pg1 (Leader) | pg2 | pg3 |
|------|---------------|------|------|
| Install pgBackRest | ✅ | ✅ | ✅ |
| Patch Patroni YAML | ✅ | ✅ | ✅ |
| Restart Patroni | ✅ | ✅ | ✅ |
| Create stanza | ✅ | ❌ | ❌ |
| Run backup | ✅ | ❌ | ❌ |
| Verify YAML | ✅ | ✅ | ✅ |

---

## 🏁 13. Final Verification

On **pg1**:
```bash
sudo -u postgres pgbackrest check
sudo -u postgres pgbackrest info
sudo python3 -c "import yaml; yaml.safe_load(open('/etc/patroni/patroni.yml')) or print('✅ YAML OK')"
sudo patronictl -c /etc/patroni/patroni.yml list
```

✅ If all pass: you now have **automated PostgreSQL backups, live WAL archiving, and a self-healing HA cluster** ready for production.

