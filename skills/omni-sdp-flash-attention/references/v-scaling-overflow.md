# Adaptive V-scaling for fp16 accumulator overflow

Unique safety mechanism in the omni_xpu_kernel SDP kernel: per-head
V-scaling with a cached decision, triggered adaptively only when V
values are large. Pays ~0 cost on the common case; prevents NaN on
the pathological case (Qwen Image, large-DiT variants).

The pattern generalizes beyond SDP to any kernel with a rare-but-real
numeric hazard.

---

## The problem

The ESIMD HD=128 FP16 kernel accumulates `∑ softmax_weight × V` in
fp16. For typical diffusion models, `|V|_max` is small and the
accumulator stays well below 65504. For some models, `|V|_max` can
exceed 1000 and the accumulator Inf's → NaN propagates through the
whole output.

Two obvious fixes, both bad:

- **Switch the whole kernel to fp32 accum** → costs ~20–25%
  throughput (fewer values per GRF, fewer MAC/cycle).
- **Always pre-scale V in Python** → wasted work on the 99% of
  models that don't need it, plus a GPU-CPU sync to measure max.

---

## The two-layer solution

### Layer 1 — in-kernel fp32 compensation + clamp

Historic-max compensation is computed in fp32, clamped to ±65504
before any fp16 cast. Any intermediate that would overflow gets
clamped to the fp16 representable range instead of going to Inf.
Costs a couple of fp32 ops per tile; enough to make most pathological
inputs survive.

### Layer 2 — host-side adaptive per-head V-scaling

For cases where even Layer 1 is insufficient, the host measures
`|V|_max` on a sampling interval (every RECHECK_INTERVAL calls).
If above threshold, it computes a per-head scale, pre-divides V, and
folds the inverse scale into `norm_alpha`.

Structure:

```
counter.fetch_add() % RECHECK_INTERVAL == 0:
    sample V_max (one amax + one CPU read)
    if above threshold:
        compute per-head v_scale
        cache v_scale broadcast tensor
        cache effective_alpha = norm_alpha * v_scale
```

Hot path when `needs_scaling == false`:
- 1 atomic increment + 1 atomic load
- Zero GPU work
→ effectively zero overhead on normal models.

Hot path when `needs_scaling == true`:
- One broadcast divide on V
- Kernel reads `cached_effective_alpha` instead of `norm_alpha`
- No per-call amax, no per-call repeat_interleave

The fast-path kernel variant (`sdp_fp16_fast`, no clamp) is chosen
when `needs_scaling == false` and the variant is available — skipping
Layer 1's clamp cost too.

---

## The `effective_alpha` fold-in trick

The kernel normally scales `QKᵀ` by `norm_alpha` before softmax.
If V is pre-scaled by `1/v_scale`, the attention output is
`1/v_scale × correct_attn`. Instead of touching V or the output,
rescale by folding `v_scale` into `norm_alpha`:

```
effective_alpha[h] = norm_alpha[h] × v_scale[h]
```

**Important caveat**: softmax is **not** invariant under arbitrary
input scaling (it sharpens as you scale up). This fold-in is only
acceptable because:
1. `v_scale` is **per-head scalar**, not per-KV-row — it shifts
   effective softmax temperature per head, doesn't redistribute
   per-row weights.
2. `v_scale` is chosen in a narrow range (`[1, |V|_max / baseline]`),
   so the temperature shift is small.
3. The alternative (overflow → NaN) is strictly worse; the slight
   softmax-temperature shift was empirically validated against the
   reference models where this mattered.

Do not reuse this fold-in trick when `v_scale` would be per-row, or
when the range is large — it stops being numerically acceptable.

---

## Per-head vs global scale — why per-head wins

A single global `v_scale` across all heads was tried. It regresses
numeric quality by several percent cosine similarity on the models
where V-scaling is needed. Per-head scale lets each head pick the
scale it actually needs; a head with small V pays no scaling cost,
a head with large V gets the protection it requires.

---

## Why RECHECK_INTERVAL (not per-call)

Measuring `|V|_max` every call profiled at ~50% of total SDP time
when V-scaling was active (driven by the amax reduction + scale
tensor allocation + broadcast). Caching the decision for ~hundreds
of calls recovers almost all of that cost.

The recheck cadence is empirical — too short keeps the overhead,
too long misses a mid-pipeline V-distribution change. The right
interval depends on how stable `|V|_max` is across the specific
workload; document the choice in-code.

---

## What doesn't work

- **Global v_scale (single scalar)**: regresses quality; per-head
  required.
- **Static `needs_scaling` compile-time flag**: impossible — whether
  V is large depends on the model, not the compile target.
- **Per-call amax without caching**: eats ~50% of kernel time when
  active.
- **Quantize V to int8**: different dequant/cast bugs upstream; out
  of scope for the accumulator-overflow fix.

---

## Generalizable pattern

This "detect-once / cache / fast-path-fallback" applies to any
kernel where:

1. Most real inputs are in a benign range.
2. Some rare inputs hit a hardware limit (fp16 overflow, denormal
   flush, precision loss).
3. The safety protection has nonzero cost.

Template in pseudocode:

```
static atomic<int>  counter{0};
static atomic<bool> needs_safety{false};
if (counter.fetch_add(1) % RECHECK_N == 0) {
    needs_safety.store(measure_hazard(input));
}
if (needs_safety.load()) safe_slow_path(); else fast_path();
```

The shape of the check, the recheck interval, and the cached
state are per-kernel. The structure is reusable.

---

## Related

- `failed-experiments.md` entry #5: per-call V_max without caching.
- `omni-debug-logging` — `[omni_xpu::sdp]` output for verifying
  `needs_scaling` decisions.
