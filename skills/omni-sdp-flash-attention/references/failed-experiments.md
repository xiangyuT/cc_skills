# SDP kernel — failed-experiment ledger

A record of optimizations that **were tried and did not work**. Saving
them here is the only thing that prevents someone later from
re-discovering the same dead end.

For contrast with what **did** work, see `k-prefetch-distance.md`,
`v-scaling-overflow.md`, and the main SKILL.md.

---

## 1. Extra SLM load pipelining — 0% gain

**Hypothesis**: V is loaded cooperatively into SLM before VS GEMM.
Double-buffer the SLM load so V[k+1] is loading while V[k] feeds
DPAS.

**Result**: no measurable change in any bench.

**Why**: the kernel already double-buffers V (pingpong). Further
pipelining on top of that doesn't help because the limiting factor
is not the V load path — it's the K prefetch distance
(`k-prefetch-distance.md`).

**Moral**: profile first. "Memory-bound so more pipelining helps"
isn't always the bottleneck.

---

## 2. Replace `exp2` with polynomial `fast_exp2` — regression

**Hypothesis**: `exp2f(x)` maps to a `math` send on Intel GPU (EM
unit). A polynomial approximation runs on XVE ALUs and should be
faster in bulk.

**Result**: softmax throughput dropped noticeably; total SDP
regressed.

**Why**: GPU EM (math) unit and XVE operate **in parallel**.
Transcendentals on EM while XVE handles surrounding `mad/mul` keeps
both busy. A polynomial runs entirely on XVE, conflicting with
surrounding DPAS/mad instructions for XVE issue slots. Co-scheduling
collapses.

**Evidence**: the polynomial variant shows XVE pipe utilization
near saturation with MAD stalls; the `exp2` variant shows XVE +
EM both busy concurrently.

**Moral**: on Intel GPU, "move work from special-function unit to
ALU" can be a pessimization. Keep transcendentals on EM if
DPAS/ALU is already heavily used.

---

## 3. Increase `KV_TILE` 64 → 128 — infeasible (GRF spill)

**Hypothesis**: larger K/V tile = fewer loop iterations, better
DPAS density, amortize softmax overhead.

**Result**: compile-time spill warnings; runtime regression due to
stack access.

**Why**: doubleGRF gives 256 regs × 64 B = 16 KB per thread. Holding
a larger Q tile plus softmax max/sum accumulators, DPAS output
tiles, and compensation scratch pushes past 16 KB.

**Moral**: when a plan says "bigger tile", sum up **all** live
register footprint first. GRF budget is the hard wall.

---

## 4. Increase `Q_PER_THREAD` 16 → 32 — same GRF spill

Same root cause as #3.

---

## 5. Per-call V_max measurement without caching — ~50% overhead

Not a compile failure — an overhead failure.

`v.abs().amax(...)` + scale tensor allocation + broadcast profiles
at ~50% of total SDP call time when run every call. Motivated the
RECHECK_INTERVAL + cached broadcast pattern. See
`v-scaling-overflow.md`.

**Moral**: a correctness fix shipped without caching can re-introduce
a performance problem as big as the one you just solved.

---

## 6. Double-buffered softmax compensation across iterations — neutral

**Hypothesis**: pre-compute iteration k+1's compensation factor
during iteration k's VS GEMM, hide scalar-heavy compensation work.

**Result**: neutral.

**Why**: the compensation already runs in parallel with other XVE
work. Cross-iteration pipelining is blocked by the SLM-write barrier
for cross-SG max reduction — deferring across that barrier doesn't
reduce critical-path cycles because the barrier itself is the
bottleneck of the handoff.

---

## 7. Prefetch K with `L2_cached` instead of `(cached, cached)` — minor regression

Tried `(L1H=streaming, L2H=cached)` → slightly slower. Keep
`(cached, cached)` per Xe2 LSC guidance: prefetch is specifically
designed to warm both L1 and L2 because K is consumed multiple
times across sub-tiles.

---

## Template for adding entries here

When you try a new optimization, record the result — success or
failure — with at least:

1. The hypothesis (what you thought would help and why).
2. The result qualitatively (regression / neutral / win).
3. The root cause, if identified.
4. A one-line moral, if there's a generalizable lesson.

Dead-end-avoidance compounds over a project's lifetime more than any
single micro-optimization does.
