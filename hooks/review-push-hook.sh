#!/bin/bash
# PreToolUse hook: scan git push diff for sensitive performance data
# Blocks push if precise benchmark numbers are detected in the diff.

set -euo pipefail

# Determine upstream ref
UPSTREAM=$(git rev-parse --abbrev-ref @{upstream} 2>/dev/null || true)
if [ -z "$UPSTREAM" ]; then
    for ref in origin/main origin/master; do
        if git rev-parse --verify "$ref" >/dev/null 2>&1; then
            UPSTREAM="$ref"
            break
        fi
    done
fi

[ -z "$UPSTREAM" ] && exit 0

# Get added lines from diff (skip diff headers)
ADDED=$(git diff "$UPSTREAM"..HEAD 2>/dev/null | grep '^+' | grep -v '^+++ ' || true)
[ -z "$ADDED" ] && exit 0

FINDINGS=""

check_pattern() {
    local label="$1" pattern="$2"
    local matches
    matches=$(echo "$ADDED" | grep -iE "$pattern" | head -10 || true)
    if [ -n "$matches" ]; then
        FINDINGS="${FINDINGS}[${label}]\n${matches}\n\n"
    fi
}

# 1. Precise timing: 123.45s, 67.89ms
check_pattern "Timing" '[0-9]+\.[0-9]+\s*(s|ms|sec(onds)?|milliseconds)\b'

# 2. Throughput: tokens/s, it/s, fps, GB/s
check_pattern "Throughput" '[0-9]+\.?[0-9]*\s*(tokens?/s|tok/s|tps|it/s|iter/s|samples?/s|fps|[gm]b/s|[gt]flops)\b'

# 3. Latency/e2e: latency: 12.3, e2e: 45.6
check_pattern "Latency/E2E" '(latency|e2e|elapsed|p[0-9]{2,3}|throughput)\s*[:=]\s*[0-9]+\.?[0-9]+'

# 4. JSON timing fields: "time": 12.34
check_pattern "JSON Perf Fields" '"(time|elapsed|latency|duration|e2e|benchmark)"\s*:\s*[0-9]+\.?[0-9]*'

# 5. Speedup: 2.3x faster, vs 4090: 85%
check_pattern "Comparisons" '[0-9]+\.?[0-9]*x\s*(faster|slower|speedup)|vs\s+[a-zA-Z0-9]+\s*:\s*[0-9]+\.?[0-9]*'

# 6. VRAM/Memory: VRAM: 12.3 GB
check_pattern "Memory Usage" '(vram|peak.?mem(ory)?)\s*[:=]\s*[0-9]+\.?[0-9]*\s*(gb|mb|gib|mib)\b'

# 7. Benchmark result files
BENCH_FILES=$(git diff --name-only "$UPSTREAM"..HEAD 2>/dev/null | grep -iE '(benchmark|_results|_perf|_bench)\.' | head -10 || true)
if [ -n "$BENCH_FILES" ]; then
    FINDINGS="${FINDINGS}[Benchmark Files]\n${BENCH_FILES}\n\n"
fi

if [ -n "$FINDINGS" ]; then
    REASON="Push diff contains potential performance data. Run /review-push for detailed review."
    CONTEXT=$(printf "Performance data detected in push diff (%s..HEAD):\n\n%b" "$UPSTREAM" "$FINDINGS")

    python3 -c "
import json, sys
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': sys.argv[1],
        'additionalContext': sys.argv[2]
    }
}))
" "$REASON" "$CONTEXT"
    exit 2
fi

exit 0
