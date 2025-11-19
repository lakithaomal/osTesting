# Sysbench Lua Workloads

This guide summarizes how Sysbench executes Lua-based workload scripts, the functions it expects, and the exact call order across the **prepare**, **run**, and **cleanup** phases.

---

## 🧭 Phases and Execution Order

### **1. Prepare Phase — Setup and Seed Data**
**Sysbench calls these functions in order:**
1. `sysbench.hooks.before_test()` — optional  
2. `prepare()` — **required**: defines how to create and seed data  
3. `sysbench.hooks.after_test()` — optional  

**Typical responsibilities:**
- Establish database connections.  
- Create required schema, tables, and indexes.  
- Insert seed data (using loops or prepared statements).  
- Release any global resources.

---

### **2. Run Phase — Benchmark Execution**
**Sysbench performs these actions:**
1. Loads the Lua script and command-line options.  
2. Spawns worker threads (`--threads=N`).  
3. For **each thread**, Sysbench calls:  
   - `thread_init()` — setup per-thread state or DB connection.  
   - Repeatedly calls `event()` — executes one logical transaction per call.  
   - `thread_done()` — cleans up thread resources.  
4. After all threads complete, Sysbench aggregates and reports results.  
5. Optionally runs `sysbench.hooks.after_test()` once after all threads finish.

**Typical responsibilities:**
- `thread_init()`: prepare statements and connections.  
- `event()`: perform one operation per transaction (insert, read, update, etc.).  
- `thread_done()`: close prepared statements and connections.

**Stop conditions (managed by Sysbench):**
- `--time=<seconds>` — stops after elapsed time.  
- `--events=<count>` — stops after a total number of executed events.  
- `--rate=<n>` — throttles event rate if specified.

Sysbench automatically loops `event()` across threads until the test duration or event limit is reached.

---

### **3. Cleanup Phase — Tear Down**
**Sysbench calls these functions in order:**
1. `sysbench.hooks.before_test()` — optional  
2. `cleanup()` — **required**: defines how to remove test data or schema.  
3. `sysbench.hooks.after_test()` — optional  

**Typical responsibilities:**
- Connect to the database.  
- Drop or truncate test tables.  
- Close resources and reset the environment.

---

## 🔍 Recognized Lua Function Names

| Function | Phase | Scope | Purpose |
|-----------|--------|--------|----------|
| `sysbench.hooks.before_test()` | prepare / run / cleanup | Once per phase | Global setup (e.g., connect, initialize state) |
| `prepare()` | prepare | Once | Define schema creation and seeding logic |
| `thread_init()` | run | Once per thread | Per-thread initialization |
| `event()` | run | Many per thread | Defines one transaction or logical event |
| `thread_done()` | run | Once per thread | Per-thread cleanup |
| `sysbench.hooks.after_test()` | prepare / run / cleanup | Once per phase | Finalize phase-wide tasks |
| `cleanup()` | cleanup | Once | Drop or remove artifacts created in prepare |

> Sysbench automatically skips any function not defined in your script.

---

## 🧩 Common Implementation Patterns

### **A. Self-contained scripts**
You define all the functions (`prepare`, `event`, `cleanup`, etc.) directly in a single Lua file.  
Run with:
```bash
sysbench my_script.lua prepare|run|cleanup
```
**Pros:** Simple and clear.  
**Cons:** Each workload must implement its own schema and setup logic.

---

### **B. Modular or Command-Mapped Scripts**
Workload scripts can `require()` a shared helper that registers command mappings, for example:

```lua
sysbench.cmdline.commands = {
  prepare = { my_prepare_function, sysbench.cmdline.PARALLEL_COMMAND },
  run     = { my_run_function, ... },
  cleanup = { my_cleanup_function, ... }
}
```

The shared module handles table creation and cleanup, while each workload script focuses on transaction logic (the `event()` behavior).

**Pros:** Easier reuse across multiple workloads.  
**Cons:** More abstract and slightly harder to follow.

---

## ⚙️ Runtime Controls (Sysbench CLI)

| Option | Description |
|---------|--------------|
| `--threads=N` | Number of worker threads during `run`. |
| `--time=SECS` | Duration of the benchmark (0 = run indefinitely). |
| `--events=N` | Total number of transactions to execute. |
| `--rate=N` | Throttle the transaction rate (optional). |
| `--db-driver=DRIVER` | Database driver (`pgsql`, `mysql`, etc.). |
| Custom options | Declared via `sysbench.cmdline.options` in your Lua script. |

Sysbench manages threading, timing, and metrics collection automatically.  
Your script only defines what **one event** does and how resources are set up and cleaned up.

---

## 🧱 Generic Pseudocode Example

```lua
# prepare phase
before_test()     -- optional: connect or init resources
prepare()         -- required: create schema and seed data
after_test()      -- optional: finalize or close

# run phase
spawn threads:
  thread_init()   -- per-thread: open connection, prepare statements
  repeat until time/events stop:
    event()       -- defines one transaction
  thread_done()   -- per-thread: close statements/connections
after_test()      -- optional: finalize or summarize

# cleanup phase
before_test()     -- optional
cleanup()         -- required: remove test tables or artifacts
after_test()      -- optional
```

---

## 🧩 Mental Model Cheat Sheet

- **You define**: the functions and SQL actions (`prepare()`, `event()`, `cleanup()`, etc.).  
- **Sysbench controls**: the timing, threading, and function call order.  
- **Metrics**: Sysbench automatically reports TPS, latency percentiles, and errors after the run phase.

---

**Result:** a predictable, modular test lifecycle for any database or workload type — easy to extend, automate, and reproduce.
