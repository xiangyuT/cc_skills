---
description: Review git push diff for sensitive performance data that should not be pushed
---

# Review Push Diff for Performance Data

Audit the diff between the local branch and its remote tracking branch. Flag any precise performance numbers that should not be pushed to the remote repository.

## User Request

$ARGUMENTS

## Steps

### Step 1: Determine what would be pushed

```bash
# Get current branch and its remote tracking branch
git rev-parse --abbrev-ref HEAD
git rev-parse --abbrev-ref @{upstream} 2>/dev/null || echo "NO_UPSTREAM"
```

If there is no upstream, compare against `origin/main` or `origin/master` (whichever exists).

If `$ARGUMENTS` specifies a target branch or ref range, use that instead.

### Step 2: Get the diff

```bash
# Get the full diff that would be pushed
git diff <upstream>..HEAD
```

Also check:
```bash
# List the commits that would be pushed
git log --oneline <upstream>..HEAD
```

### Step 3: Scan for performance data patterns

Carefully review the diff output (added lines only, i.e., lines starting with `+`) for these categories of sensitive performance data:

#### 3.1 Precise timing numbers
- Wall-clock times: e.g., `123.45s`, `67.89ms`, `0.456 seconds`
- Latency values: e.g., `latency: 12.3ms`, `p99: 45.6ms`
- e2e times: e.g., `e2e: 89.12s`, `elapsed: 34.56`

#### 3.2 Throughput metrics
- Tokens per second: e.g., `tokens/s`, `tok/s`, `TPS`
- Iterations per second: e.g., `it/s`, `iter/s`
- Samples per second: e.g., `samples/s`
- FPS: e.g., `30.5 fps`, `FPS: 60.2`
- Bandwidth: e.g., `GB/s`, `MB/s`

#### 3.3 Benchmark result tables
- Markdown tables containing numeric performance columns
- CSV-like data with timing/throughput columns
- JSON objects with timing fields (e.g., `"time": 12.34`, `"elapsed": 56.78`)

#### 3.4 Hardware-specific benchmark comparisons
- GPU comparison numbers (e.g., `vs 4090: 85%`, `A770: 123.4s`)
- Speedup ratios with specific values (e.g., `2.3x faster`)
- Percentage comparisons (e.g., `15.2% improvement`)

#### 3.5 Resource usage metrics
- VRAM/memory: e.g., `peak VRAM: 12.3 GB`, `memory: 8192 MB`
- GPU utilization: e.g., `GPU util: 95.2%`
- FLOPS: e.g., `1.23 TFLOPS`

#### 3.6 Benchmark result files
- Files in `benchmark_results/` directory
- JSON files containing timing data
- Files named with patterns like `*_results.*`, `*_benchmark.*`, `*_perf.*`

### Step 4: Report findings

For each finding, report:
1. **File path** and **line number** in the diff
2. **Category** of performance data (from the categories above)
3. **The specific content** that was flagged
4. **Severity**: HIGH (raw benchmark numbers, result files) / MEDIUM (derived metrics like percentages) / LOW (ambiguous, might not be performance data)

### Step 5: Summary and recommendation

Provide a summary:
- Total findings count by severity
- Whether it is safe to push or not
- If there are HIGH severity findings, recommend:
  - Replacing precise numbers with relative comparisons or ranges
  - Moving benchmark data to a separate non-pushed location
  - Adding the files to `.gitignore`
  - Using `git reset HEAD~1` to undo the commit and fix

## Important Notes

- Only flag **added lines** (lines starting with `+` in the diff), not removed lines
- Do NOT flag:
  - Version numbers (e.g., `v1.2.3`)
  - Configuration values (e.g., `batch_size: 16`, `num_steps: 50`)
  - Code constants that happen to be numbers
  - Test assertions with small/obvious numbers
  - Reference data that is already public (e.g., published paper numbers)
- DO flag:
  - Internal benchmark results with precise timing
  - Performance comparison tables with real measured data
  - Profiling output
  - Hardware-specific performance numbers that could reveal competitive positioning
- When in doubt, flag it and let the user decide
