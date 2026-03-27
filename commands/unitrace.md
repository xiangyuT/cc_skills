---
description: Profile Intel GPU applications using unitrace (Intel PTI-GPU)
---

# Unitrace GPU Profiling

Use this command to profile GPU workloads on Intel XPU using unitrace.

## Setup

Before using, ensure the following:
1. unitrace is built from https://github.com/intel/pti-gpu (tools/unitrace)
2. Set `$UNITRACE` to the path of the unitrace binary
3. If running inside a container, set `$CONTAINER` to the container name (commands will use `docker exec $CONTAINER`)
4. If running directly on host, leave `$CONTAINER` empty

If unitrace is not yet built, build it:
```bash
# Inside container or on host with oneAPI installed:
cd pti-gpu/tools/unitrace && mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_WITH_MPI=0 -DBUILD_WITH_ITT=1 ..
make -j$(nproc)
# Binary at: ./unitrace
```

## User Request

$ARGUMENTS

## Profiling Workflow

Based on user's request, choose the appropriate profiling level:

### Level 1: Quick Summary (find hotspots)

```bash
$UNITRACE -d -v -h -s <application>
```

Flags:
- `-d` device kernel timing summary
- `-v` show kernel shapes (strongly recommended, different shapes have different perf)
- `-h` host API timing summary
- `-s` kernel queue/submit/execute breakdown

### Level 2: Timeline Analysis (concurrency & bottlenecks)

```bash
$UNITRACE --chrome-kernel-logging --chrome-dnn-logging -o <output>.csv <application>
```

Generates `.json` timeline file viewable at https://ui.perfetto.dev/

Key options:
- `--chrome-kernel-logging` traces host-device interactions and dependencies
- `--chrome-dnn-logging` traces oneDNN (for PyTorch workloads)
- `--chrome-sycl-logging` traces SYCL runtime
- `--chrome-ccl-logging` traces oneCCL (distributed)
- `--chrome-call-logging` traces Level Zero / OpenCL host calls

**Warning:** `--chrome-kernel-logging` may hang with ESIMD sidecar kernels. If profiling ESIMD kernels, use Level 1 instead or Python `time.perf_counter()`.

### Level 3: Hardware Metrics (deep kernel analysis)

```bash
# Metric query per kernel instance
$UNITRACE -q --chrome-kernel-logging -o <output>.csv <application>

# Time-based sampling (for longer kernels)
$UNITRACE -k -i 20 --chrome-kernel-logging -o <output>.csv <application>
```

- `-q` metric query mode
- `-k` time-based sampling mode
- `-i <us>` sampling interval (default 50us, use 20us for short kernels)
- `-g <group>` metric group (default ComputeBasic), list all with `--metric-list`

### Level 4: Selective Profiling (reduce overhead)

```bash
# Only specific kernels
$UNITRACE -d -v --include-kernels gemm,matmul <application>

# Exclude uninteresting kernels
$UNITRACE -d -v --exclude-kernels fill,copy <application>

# Runtime control via session
$UNITRACE --chrome-kernel-logging --session mysession --start-paused <application>
# In another terminal: $UNITRACE --resume/--pause/--stop mysession
```

### PyTorch-specific

Code must wrap profiled region with:
```python
with torch.autograd.profiler.emit_itt():
    # code to profile
```

Or use env var control:
```python
os.environ["PTI_ENABLE_COLLECTION"] = "1"  # start
os.environ["PTI_ENABLE_COLLECTION"] = "0"  # stop
```

Launch with `--start-paused` for env var control to work.

## Instructions

1. Determine what the user wants to profile from `$ARGUMENTS`
2. If `$ARGUMENTS` is empty or says "help", explain the available profiling modes
3. If the user provides an application path, run the appropriate profiling level
4. If `$CONTAINER` is set, run via `docker exec $CONTAINER bash -c "..."`, otherwise run directly
5. After profiling completes, **analyze the results**:
   - Identify the hottest kernels from Device Timing Summary
   - Check Kernel Properties for occupancy issues (SLM, spill, private memory)
   - Compare Submit vs Execute times (note: unitrace tracing hooks add overhead to Submit, real overhead is much smaller)
   - Highlight any anomalies in the Host API timing
6. Provide actionable optimization suggestions based on findings
7. If timeline JSON is generated, remind user to open it in https://ui.perfetto.dev/

## Key Metrics to Analyze

| Metric | Meaning | Red Flag |
|--------|---------|----------|
| SLM Per Work Group | Shared local memory per work group | Too large hurts occupancy |
| Private Memory Per Thread | Thread private memory | Non-zero = not in registers |
| Spill Memory Per Thread | Register spill | Non-zero = performance loss |
| Submit >> Execute time | Host submission overhead | May be unitrace artifact; verify with Python timing |
| XVE_STALL[%] | Execution unit stalls | High = pipeline stalls |
| XVE_THREADS_OCCUPANCY_ALL[%] | Thread occupancy | Low = underutilization |
| Compiled (JIT/AOT) | Compilation mode | JIT ESIMD kernels may have long first-call latency |

## Known Issues

1. **ESIMD sidecar + `--chrome-kernel-logging`**: unitrace tracing hooks may cause ESIMD kernel profiling to hang indefinitely. Use Level 1 (`-d -v -s`) or Python timing instead.
2. **Submit overhead inflation**: unitrace's Level Zero hooks add significant overhead per kernel submission. Real production launch overhead is typically 2-6us, not the 100s of us reported by unitrace.
3. **AOT device mismatch**: If ESIMD AOT-compiled kernels target a different GPU (e.g., PVC vs BMG), SYCL runtime falls back to JIT which can take 20+ minutes. Recompile with correct `-device` target.
