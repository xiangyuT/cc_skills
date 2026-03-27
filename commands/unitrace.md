---
description: Profile Intel GPU applications using unitrace (Intel PTI-GPU)
---

# Unitrace GPU Profiling

Use this command to profile GPU workloads on Intel XPU using unitrace.

## Setup

Before profiling, Claude should check if unitrace is available and install it if needed.

### Step 1: Detect environment

- If `$CONTAINER` is set, all commands run via `docker exec $CONTAINER bash -c "..."`
- Otherwise run directly on host
- Check if `$UNITRACE` is set; if not, search common locations:
  - `./pti-gpu/tools/unitrace/build/unitrace`
  - `$HOME/pti-gpu/tools/unitrace/build/unitrace`
  - Workspace siblings: `../pti-gpu/tools/unitrace/build/unitrace`
  - `which unitrace`

### Step 2: Auto-install if not found

If unitrace binary is not found, install it automatically:

```bash
# 1. Clone pti-gpu (shallow)
git clone --depth 1 https://github.com/intel/pti-gpu.git

# 2. Build unitrace
cd pti-gpu/tools/unitrace
mkdir build && cd build

# If inside a container that can't access GitHub, try setting proxy:
#   export http_proxy=http://proxy-host:port
#   export https_proxy=http://proxy-host:port
# Or pre-clone on host and mount into container.

# Configure — adjust flags as needed:
#   -DBUILD_WITH_ITT=1  enables oneDNN/CCL/PyTorch profiling (requires ittapi, auto-downloaded)
#   -DBUILD_WITH_MPI=0  disable MPI if not needed
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_WITH_MPI=0 -DBUILD_WITH_ITT=1 ..

# Build
make -j$(nproc)

# Verify
./unitrace --version
```

If git clone fails (no network in container), clone on host first and mount/copy:
```bash
# On host:
git clone --depth 1 https://github.com/intel/pti-gpu.git /path/to/pti-gpu
# Then build inside container where oneAPI is available
```

After building, set `$UNITRACE` to the binary path for subsequent commands.

### Step 3: Verify

```bash
$UNITRACE --version        # Should print version
$UNITRACE --device-list    # Should list available GPUs
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

## Level 5: Roofline Analysis

Roofline model plots kernel performance (GFLOPS) vs arithmetic intensity (FLOPS/byte) against hardware ceilings.

### Method A: Official roofline.py (PVC only)

Only works if **both** `ComputeBasic` and `VectorEngine138` metric groups are supported:
```bash
# One-step: profile + roofline
python roofline.py --app <application> --device device_configs/<device>.csv --output roofline.html --unitrace $UNITRACE

# Two-step: profile first, then roofline
$UNITRACE -g ComputeBasic -q --chrome-kernel-logging -o compute.csv <application>
$UNITRACE -g VectorEngine138 -q --chrome-kernel-logging -o memory.csv <application>
python roofline.py --compute compute.metrics.*.csv --memory memory.metrics.*.csv --device device_configs/<device>.csv --output roofline.html
```

**Note:** On BMG (Arc B-series), `VectorEngine138` does not exist. The equivalent `VectorEngineProfile` group is listed but NOT supported for metric query/sampling by the driver. Method B must be used instead.

### Method B: Empirical Roofline (all devices)

When hardware metric groups are limited, use Python timing + theoretical FLOP counts:

```python
import time, torch
# Measure kernel execution time
t0 = time.perf_counter()
for _ in range(N):
    kernel_call(...)
torch.xpu.synchronize()
ms = (time.perf_counter() - t0) / N * 1000

# Calculate operational intensity
flops = <theoretical FLOPs for the kernel>  # e.g., 2*M*N*K for GEMM
bytes_accessed = <input_bytes + output_bytes>
arithmetic_intensity = flops / bytes_accessed  # FLOP/byte
achieved_gflops = flops / (ms / 1000) / 1e9
```

Then compare against device ceilings:
- **Compute ceiling**: peak GFLOPS for the dtype (FP16 XMX, BF16 XMX, FP32, etc.)
- **Memory ceiling**: `peak_memory_bw_GB_s * arithmetic_intensity`
- **Ridge point**: `peak_gflops / peak_memory_bw_GB_s` (FLOP/byte)

If `achieved_gflops` is far below the lower of the two ceilings, there's optimization headroom.

### Device Config Reference

Create device config CSV at `device_configs/<device>.csv`:
```csv
PlatformName,"<device_name>"
FP16_GFLOPS,<fp16_vector_peak>
FP16_XMX_GFLOPS,<fp16_xmx_peak>
BF16_XMX_GFLOPS,<bf16_xmx_peak>
FP32_GFLOPS,<fp32_vector_peak>
FP64_GFLOPS,<fp64_peak>
GPU_MEMORY_BW_in_GB_per_sec,<measured_gddr/hbm_bw>
L3_BW_in_GB_per_sec,<measured_l3_bw>
```

Measure peak values empirically with large GEMMs (`torch.matmul` on 8192x8192 matrices) and large memory copies.

Known device configs:
- `PVC_1tile.csv`: Intel Data Center GPU Max (Ponte Vecchio)
- `BMG_B580.csv`: Intel Arc B580 (Battlemage) — FP16 XMX ~109 TFLOPS, BF16 XMX ~108 TFLOPS, Mem BW ~403 GB/s

## Known Issues

1. **ESIMD sidecar + `--chrome-kernel-logging`**: unitrace tracing hooks may cause ESIMD kernel profiling to hang indefinitely. Use Level 1 (`-d -v -s`) or Python timing instead.
2. **Submit overhead inflation**: unitrace's Level Zero hooks add significant overhead per kernel submission. Real production launch overhead is typically 2-6us, not the 100s of us reported by unitrace.
3. **AOT device mismatch**: If ESIMD AOT-compiled kernels target a different GPU (e.g., PVC vs BMG), SYCL runtime falls back to JIT which can take 20+ minutes. Recompile with correct `-device` target.
