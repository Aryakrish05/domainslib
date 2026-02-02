# Performance Profiling Guide: Finding Hotspots in OCaml Code

This guide walks you through profiling parallel OCaml code using `perf` to identify performance bottlenecks.

---

## Prerequisites

- Linux system with `perf` installed
- Compiled binary (ideally with debug symbols: `-g` flag)
- Basic understanding of your code structure

---

## Step 1: Record Performance Data

**Goal**: Capture CPU samples while your program runs.

### Basic Recording
```bash
perf record ./your_program args
```

**Example from this project:**
```bash
perf record ./_build/default/test/test_hb_simple.exe 4 24
```

This creates a `perf.data` file containing performance samples.

### Recording Options

- **With call stacks (frame pointers):**
  ```bash
  perf record -g ./your_program args
  ```

- **With DWARF unwinding (when frame pointers unavailable):**
  ```bash
  perf record --call-graph dwarf ./your_program args
  ```

- **Specific event (e.g., cache misses):**
  ```bash
  perf record -e cache-misses ./your_program args
  ```

- **Higher sampling frequency:**
  ```bash
  perf record -F 999 ./your_program args
  ```

**Tip**: For OCaml/multicore programs, compile with `-g` for better symbol resolution.

---

## Step 2: View the Report Interactively

**Goal**: Get a quick overview of hotspots.

```bash
perf report
```

### Navigation in Interactive Mode
- **Arrow keys**: Navigate up/down
- **Enter**: Drill into a symbol to see callers/callees
- **+**: Expand call graph entries
- **-**: Collapse call graph entries
- **a**: Annotate the selected symbol (shows assembly)
- **q**: Quit

### What to Look For
- **Overhead column**: Percentage of samples in that function
- Functions with >3-5% overhead are usually worth investigating
- Look for your own code (not just library/kernel code)

**Example from our data:**
```
5.50%  caml_atomic_fetch_add_field          ← Hotspot!
4.53%  Domainslib.Multi_channel.recv_poll_loop_658
4.25%  Domainslib.Heartbeat.fork2join_342
4.23%  Saturn.Ws_deque.steal_as_585
```

---

## Step 3: Export Text Reports

**Goal**: Save reports for detailed analysis or sharing.

### Full Report
```bash
perf report --stdio > perf_report.txt
```

### Detailed Trace (all samples with stacks)
```bash
perf script > perf_script.txt
```

### Filter by Symbol
```bash
perf report --stdio --symbol=my_function > my_function_report.txt
```

---

## Step 4: Analyze Hotspots

### 4.1 Identify the Top Functions

Open `perf_report.txt` and look at the overhead column:

```
Overhead  Command          Symbol
5.50%     test_hb_simple   caml_atomic_fetch_add_field
4.53%     test_hb_simple   Domainslib.Multi_channel.recv_poll_loop_658
```

**Questions to ask:**
1. Is this function part of my application code or runtime/library?
2. What is this function doing?
3. Is the time spent here expected or surprising?

### 4.2 Find Source Location

Use `addr2line` or `nm` to map symbols to source:

```bash
# Find symbol address
nm -C your_binary | grep function_name

# Map address to source line
addr2line -f -p -e your_binary 0xADDRESS
```

**Example:**
```bash
$ nm -C _build/default/test/test_hb_simple.exe | grep caml_atomic_fetch_add_field
00000000000dbdc0 T caml_atomic_fetch_add_field

$ addr2line -f -p -e _build/default/test/test_hb_simple.exe 0x00dbdc0
caml_atomic_fetch_add_field at /home/arya/Heartbeat/ocaml/runtime/memory.c:388
```

### 4.3 Understand Call Context

Look at `perf_script.txt` to see call stacks:

```bash
grep -A10 "function_name" perf_script.txt | less
```

This shows:
- Who is calling the hot function
- What else is happening in the same context

**From our data:**
```
caml_atomic_fetch_add_field+0x34
    ↑ called from
Saturn.Ws_deque.steal_as_585+0x31
Domainslib.Multi_channel.recv_poll_loop_658+0xec
```

---

## Step 5: Annotate Hot Functions

**Goal**: See which lines/instructions within a function are expensive.

```bash
perf annotate -s function_name --stdio
```

**Example:**
```bash
perf annotate -s caml_atomic_fetch_add_field --stdio
```

**Output shows:**
- Assembly instructions
- Percentage of samples per instruction
- Source lines (if debug info available)

**What to look for:**
- Lock contention: high % on atomic ops (lock cmpxchg, lock add)
- Memory stalls: high % on loads/stores
- Branch misprediction: high % on conditional jumps

---

## Step 6: Generate Flamegraphs (Visual Analysis)

**Goal**: Visualize the entire call stack profile.

### Install FlameGraph Tools
```bash
git clone https://github.com/brendangregg/FlameGraph
cd FlameGraph
```

### Generate Flamegraph
```bash
# From your project directory
perf script > out.perf
/path/to/FlameGraph/stackcollapse-perf.pl out.perf > out.folded
/path/to/FlameGraph/flamegraph.pl out.folded > flame.svg
```

### View
```bash
firefox flame.svg
# or
xdg-open flame.svg
```

**Reading flamegraphs:**
- X-axis: Alphabetical ordering (NOT time!)
- Y-axis: Stack depth (caller → callee going up)
- Width: Percentage of samples
- Click to zoom in
- Look for wide "plateaus" = hotspots

---

## Step 7: Interpret Results for Parallel Code

### Common Hotspots in Multicore OCaml

#### 1. Atomic Operations
**Symptom:** High % in `caml_atomic_fetch_add_field`, `caml_atomic_cas`, etc.

**Meaning:** Contention on shared data structures

**Fix options:**
- Reduce sharing (use domain-local data)
- Batch updates (update less frequently)
- Use lock-free algorithms differently
- Consider coarser-grained parallelism

#### 2. CPU Relax / Spinning
**Symptom:** High % in `caml_ml_domain_cpu_relax`, `Domain.cpu_relax`

**Meaning:** Threads spinning waiting for work

**Fix options:**
- Better work distribution
- Adjust number of domains
- Use blocking primitives instead of spinning
- Check if problem size is too small

#### 3. Channel/Queue Operations
**Symptom:** High % in `Multi_channel.recv_poll_loop`, `Chan.recv_poll`

**Meaning:** Time spent coordinating between domains

**Fix options:**
- Reduce communication frequency
- Batch messages
- Use different communication pattern
- Consider task-based vs channel-based approach

#### 4. Work Stealing
**Symptom:** High % in `Ws_deque.steal_as`, `Ws_deque.pop_as`

**Meaning:** Workers stealing tasks from each other

**Fix options:**
- Adjust task granularity (more coarse-grained tasks)
- Better work distribution
- Check if overhead exceeds parallel benefit

#### 5. GC/Memory Operations
**Symptom:** High % in `caml_alloc_*`, `caml_call_gc`, `minor_collection`

**Meaning:** Memory allocation/collection overhead

**Fix options:**
- Reduce allocations in hot paths
- Use in-place updates where possible
- Adjust GC parameters
- Consider pooling objects

---

## Step 8: Example Analysis Workflow

### Our Current Profile

**Top hotspots:**
1. `caml_atomic_fetch_add_field` (5.5%) - Atomic field updates
2. `Multi_channel.recv_poll_loop_658` (4.5%) - Channel polling
3. `Heartbeat.fork2join_342` (4.25%) - Fork/join coordination
4. `Ws_deque.steal_as_585` (4.2%) - Work stealing

**Analysis:**
```
Total synchronization overhead: ~18%
- Atomic operations: 5.5%
- Channel coordination: 4.5%
- Heartbeat/fork-join: 4.25%
- Work stealing: 4.2%
```

**Interpretation:**
- ~18% of time spent on parallel coordination
- This is reasonable for parallel code but could be reduced
- The actual computation (fib_heartbeat, Random.int, etc.) is scattered

**Next steps:**
1. Check if task granularity is appropriate
2. Profile with fewer/more domains
3. Compare heartbeat vs non-heartbeat versions
4. Look for unnecessary atomics in hot paths

---

## Step 9: Compare Before/After

### Record Baseline
```bash
perf record -o perf_baseline.data ./your_program args
```

### Make Changes

### Record Optimized Version
```bash
perf record -o perf_optimized.data ./your_program args
```

### Compare
```bash
# View both
perf report -i perf_baseline.data
perf report -i perf_optimized.data

# Or use perf diff
perf diff perf_baseline.data perf_optimized.data
```

---

## Step 10: Advanced Techniques

### Profile Specific Events

**Cache misses:**
```bash
perf record -e cache-misses,cache-references ./your_program
perf report
```

**Branch mispredictions:**
```bash
perf record -e branches,branch-misses ./your_program
```

**Context switches:**
```bash
perf record -e context-switches,cpu-migrations ./your_program
```

### Statistical Analysis
```bash
# Run multiple times and use perf stat
perf stat -r 10 ./your_program args
```

### Record System-Wide (requires root)
```bash
sudo perf record -a -g ./your_program args
```

### Filter by Time Range
```bash
perf script --time start,stop > filtered.perf
```

---

## Common Pitfalls

1. **No debug symbols**: Compile with `-g` flag
2. **Restricted kernel symbols**: See `kptr_restrict` warnings - not critical for user-space
3. **Too short runs**: Profile for at least 1-2 seconds
4. **Optimization affects behavior**: Profile release builds, not debug
5. **Small sample counts**: Use `-F` to increase sampling rate if needed

---

## Checklist for Profiling Session

- [ ] Compile with debug info (`-g`)
- [ ] Run program long enough to gather samples (1+ seconds)
- [ ] Record with call graphs (`-g` or `--call-graph dwarf`)
- [ ] Export reports to files
- [ ] Identify top 3-5 hotspots
- [ ] Find source locations
- [ ] Understand call context
- [ ] Annotate hot functions
- [ ] Generate flamegraph
- [ ] Interpret results in context of your algorithm
- [ ] Make targeted optimizations
- [ ] Profile again to verify improvements

---

## Quick Reference Commands

```bash
# Record
perf record ./program args
perf record -g ./program args                    # with stacks
perf record --call-graph dwarf ./program args    # DWARF unwinding

# View
perf report                                       # interactive
perf report --stdio > report.txt                  # text export
perf script > script.txt                          # detailed trace

# Analyze specific symbol
perf report --symbol=my_function
perf annotate -s my_function --stdio

# Find source
nm -C binary | grep symbol
addr2line -f -p -e binary 0xaddress

# Flamegraph
perf script | stackcollapse-perf.pl | flamegraph.pl > flame.svg
```

---

## Resources

- `man perf-record`
- `man perf-report`
- `man perf-annotate`
- https://brendangregg.com/perf.html
- https://brendangregg.com/flamegraphs.html

---

## Your Current Data Summary

**File**: `perf.data` (from `test_hb_simple.exe 4 24`)

**Top hotspots found:**
- 5.5% atomic operations (synchronization cost)
- 4.5% channel polling (communication overhead)
- 4.25% heartbeat fork/join (coordination)
- 4.2% work stealing (load balancing)

**Recommendations:**
1. Run with different domain counts to see scaling
2. Compare with non-heartbeat version
3. Measure actual computation time vs coordination time
4. Consider task granularity adjustments

**Next command to run:**
```bash
perf annotate -s caml_atomic_fetch_add_field --stdio > atomic_annotate.txt
```

This will show exactly which assembly instructions are hot within the atomic function.


# Commonly used commands
- nm -C _build/default/test/test_hb_simple.exe | grep -w caml_modify
- grep -r "caml_modify" /home/arya/Heartbeat/ocaml/runtime/*.c | head -20
- grep -n "void caml_modify" /home/arya/Heartbeat/ocaml/runtime/memory.c
- sed -n '209,240p' /home/arya/Heartbeat/ocaml/runtime/memory.c
- Use addr2line also sometimes - learn these things
