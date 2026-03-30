---
description: Run ComfyUI e2e benchmark workflows and collect performance data
---

# ComfyUI E2E Benchmark

Run ComfyUI API workflow benchmarks, collect e2e timing, and generate a comparison table.

## User Request

$ARGUMENTS

## Setup

### Step 1: Detect environment

- ComfyUI should be running and accessible via API (default: `http://127.0.0.1:8188`)
- If inside a container, set `$CONTAINER` to the container name
- If ComfyUI is running on a different host/port, set `$COMFYUI_URL`
- Workflow JSON files should be in the workspace or provided by user

### Step 2: Verify ComfyUI is running

```bash
# Check if ComfyUI API is accessible
curl -s http://127.0.0.1:8188/system_stats | python3 -m json.tool
# Should return system info including GPU device name
```

If ComfyUI is not running:
```bash
# Inside container:
cd /path/to/ComfyUI
python3 main.py --listen 0.0.0.0 --port 8188 &
# Wait for "To see the GUI go to: http://..."
```

## Benchmark Execution

### Step 1: Run a single workflow

Submit workflow JSON to ComfyUI API and measure wall-clock time:

```python
import json, time, urllib.request, urllib.parse

COMFYUI_URL = "http://127.0.0.1:8188"

def run_workflow(workflow_json_path, warmup=0, runs=1):
    """Run a ComfyUI workflow and return e2e times."""
    with open(workflow_json_path) as f:
        workflow = json.load(f)

    times = []

    for i in range(warmup + runs):
        # Queue the prompt
        data = json.dumps({"prompt": workflow}).encode('utf-8')
        req = urllib.request.Request(f"{COMFYUI_URL}/prompt", data=data,
                                      headers={'Content-Type': 'application/json'})
        resp = json.loads(urllib.request.urlopen(req).read())
        prompt_id = resp['prompt_id']

        # Poll for completion
        t0 = time.time()
        while True:
            history = json.loads(urllib.request.urlopen(
                f"{COMFYUI_URL}/history/{prompt_id}").read())
            if prompt_id in history:
                break
            time.sleep(0.5)
        elapsed = time.time() - t0

        if i >= warmup:
            times.append(elapsed)
            print(f"  Run {i-warmup+1}/{runs}: {elapsed:.2f}s")

    return times
```

### Step 2: Run all benchmark workflows

For each workflow JSON in the benchmark suite:
1. Run with warmup=1, runs=3 (or as specified)
2. Record median time
3. Compare against reference data (4090, last release)

### Step 3: Generate comparison table

Output format (markdown):

```
| Workflow | GPU | Size | Frames | Steps | QType | e2e (s) | vs 4090 | vs Last Release |
|----------|-----|------|--------|-------|-------|---------|---------|-----------------|
| ...      | ... | ...  | ...    | ...   | ...   | ...     | ...     | ...             |
```

## Instructions

1. Parse `$ARGUMENTS` for:
   - Workflow JSON paths (one or more)
   - Number of runs (default: 3)
   - Warmup runs (default: 1)
   - Reference data (4090 times, last release times)
   - ComfyUI URL (default: http://127.0.0.1:8188)

2. If `$ARGUMENTS` is empty or "help", show available workflows and usage

3. If `$ARGUMENTS` contains "all", run all workflows in the benchmark directory

4. For each workflow:
   - Verify the JSON is valid and contains a prompt
   - Submit to ComfyUI API
   - Wait for completion (poll /history endpoint)
   - Record wall-clock time
   - Check for errors in the output

5. After all runs, generate the comparison table with:
   - e2e time (median of runs)
   - vs 4090: `e2e_b60 / e2e_4090 * 100`%
   - vs last release: `(last_release - current) / last_release * 100`%

6. Save results to a timestamped JSON file for future comparison

## Benchmark Metadata

Each workflow benchmark should include metadata either in the JSON filename or a companion config:

```json
{
    "name": "Wan 2.2 T2V 14B",
    "gpu_nums": 1,
    "size": "640x640",
    "frames": 81,
    "inference_steps": 4,
    "qtype": "fp8",
    "optimization": "4steps LoRA",
    "reference": {
        "4090": 57.24,
        "last_release": 169.27
    }
}
```

## Reference Data

Known baseline times for comparison:

| Workflow | 4090 (s) | Last Release B60 (s) |
|----------|----------|---------------------|
| Qwen Image 2512 fp8 | 117.44 | 320.79 |
| Z Image Turbo | 4.74 | 12.13 |
| Wan 2.2 TI2V 5B | 175.76 | 466.85 |
| Wan 2.2 T2V 14B (4step) | 57.24 | 169.27 |
| LTX-2 fp8 T2V | 88.87 | 196.12 |

## Result Storage

Save results to `benchmark_results/` directory:

```
benchmark_results/
├── 2026-03-30_b60_results.json    # Raw timing data
├── 2026-03-30_b60_report.md       # Markdown table
└── history/                        # Historical results for trend tracking
```

## Profiling Mode

If `$ARGUMENTS` contains "profile", additionally collect:
- Per-step timing (if ComfyUI exposes it)
- GPU utilization during the run
- Peak VRAM usage
- Breakdown: text_encode / denoise / vae_decode (via ComfyUI progress messages)

Use websocket connection for real-time progress monitoring:
```python
import websocket
ws = websocket.WebSocket()
ws.connect(f"ws://127.0.0.1:8188/ws?clientId=benchmark")
# Listen for progress updates to get per-step timing
```

## Known Issues

- ComfyUI may need model warmup on first run (JIT compilation, model loading)
- Always do at least 1 warmup run before timing
- VRAM-limited workflows may trigger model swapping — this is part of the real e2e time
- Some workflows require specific custom nodes to be installed
- Check ComfyUI console for errors if a workflow fails silently
