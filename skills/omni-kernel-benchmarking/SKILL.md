---
name: omni-kernel-benchmarking
description: >
  Rigorous methodology for measuring Intel XPU (BMG / Arc B-series) ESIMD
  kernel performance. Based on LightX2V's perf-testing protocol: **one
  continuous long warmup + one continuous long timed run**, NOT segmented
  samples with cooldown. Covers why the naive multi-sample-with-cooldown
  approach misleads (destroys GPU warmed-up state between samples),
  cache-busting via input rotation, drift detection via first-half vs
  second-half comparison, and what to publish / what not to publish. No
  harness source — the methodology is what transfers.
  Trigger for: benchmark, TFLOPS measurement, thermal steady state,
  run-to-run variance, kernel timing, cache busting, paired delta, GPU
  warmup, performance regression protocol.
---

# omni-kernel-benchmarking — measuring XPU kernels correctly

Methodology for defensible kernel TFLOPS / GB/s measurements on Intel
Xe2. Based on LightX2V's `xe2-esimd-gemm/references/perf-testing.md`
and adapted for `omni_xpu_kernel`. This skill covers only the
methodology — the bench harness source lives upstream.

If you're going to claim a kernel runs at N TFLOPS, the number must be
defensible against: naive timing, cold kernel, L2 cache artefacts,
launch-overhead dominance, thermal drift, and run-to-run variance.

---

## The one correct protocol

```
pre_sleep  ─────▶  warmup (continuous)  ─────▶  timed run (continuous)
   ~5 s            ≥ 1000 iters ∧ ≥ 2 s       ≥ 2000 iters ∧ ≥ 3 s
                   single loop, no pauses      single loop, no pauses
                                                internally chunked for stats
```

Key rule: **one long timed loop, not N samples with cooldown**. Any
cooldown *during* the timed run lets the GPU drop out of warmed-up
state; when execution resumes, the first iters re-warm and bias the
measurement.

The timed run is internally chunked into ~20 segments *only for stats*
(stdev, drift, p5/p95). These are chunks of a single continuous run,
not independent samples.

---

## Why NOT multi-sample + cooldown

This is the intuitive approach and it is wrong for this kind of GPU
work.

Qualitative pattern observed on BMG: back-to-back 50-iter batches with
zero cooldown reach steady-state kernel time within the first batch
and stay flat thereafter. The same kernel, same shape, but with a
few-second cooldown between 50-iter samples, starts near steady state
and then **climbs** sample-over-sample to a plateau several times
worse than the true steady state.

The cooldown destroys some warmed-up state (SLM preload / driver
cache / clock state — exact mechanism not fully pinned down). Each
sample's 50 iters can't fully re-warm before timing ends. Reported
median on the cooled-sample protocol is far off the real kernel time.

**Upshot**: any "30 samples with cooldown" bench is not the same
measurement as the documented single-continuous protocol. They are
**not** equivalent and do not produce compatible numbers.

---

## Cache-busting (input rotation)

For memory-bound kernels, running the same input tensor every iter
lets L2 cache the data after iter 1, inflating apparent bandwidth.
For compute-bound kernels the effect is smaller but non-zero.
**Always rotate.**

Pattern in the timed-run callable:

```python
N_BUFFERS = 8
buffers = [make_input() for _ in range(N_BUFFERS)]
def call(i, bufs=buffers):
    return kernel(bufs[i % N_BUFFERS])
```

Rule of thumb for BMG (L2 ≈ 16 MB):

| Per-call I/O volume | Rotate? | Why                                                    |
|---------------------|---------|--------------------------------------------------------|
| < L2 / 4            | **Yes** | Single-buffer L2 hit inflates BW materially            |
| L2 / 4 to L2        | Yes     | Single-buffer may see 10–30% L2 hit on 2nd iter        |
| > L2                | Harmless | Rotation doesn't change much; single buffer already cache-defeating |

The harness doesn't allocate buffers itself because memory budget
varies per kernel — 8 buffers of a 1M-block GGUF tensor can OOM the
XPU. The caller knows the right count.

---

## Drift detection (thermal / cache / allocator)

Split the single timed run into ~20 chunks. Report:

```
drift_pct = (second_half_mean − first_half_mean) / first_half_mean
```

| Drift       | Meaning                                                              |
|-------------|----------------------------------------------------------------------|
| ≤ 1%        | Steady state. Trust the number.                                      |
| 1–3%        | Mild drift; thermal probably fine; check in long runs.               |
| > 3%        | Kernel not in steady state; increase warmup, check thermal/allocator. |
| > 10%       | Almost always a measurement bug. Inspect per-chunk times directly.   |

Drift > 1% **invalidates** any paired-ratio claim (`ratio_a / ratio_b`)
because the denominator or numerator was still moving during measurement.

---

## Run-to-run variance on BMG ESIMD

Empirical observation from the rigorous protocol:

- **fp16 steady-state rel stdev is small** — any claimed speedup of a
  few % is detectable (CI excludes 1.0 with sample sizes the
  protocol produces).
- **bf16 steady-state rel stdev is noticeably larger** than fp16 on
  the same shape. Need a bigger delta to claim detection; smaller
  deltas require more samples (variance shrinks as `1/sqrt(n)`).

Hypotheses for the bf16 > fp16 stdev (not separately confirmed, in
order of likelihood):
1. bf16 → fp32 upconvert for accumulator adds variable XVE pressure;
   scheduling jitter shows more.
2. Cross-SG SLM traffic pattern differs; more sensitive to other-SG
   timing.
3. Memory subsystem sensitivity at long sequences.

---

## Reporting results — what to publish

Required fields when claiming a kernel TFLOPS number:

- Hardware + AOT target (e.g. "Arc B580, -device bmg -options
  -doubleGRF")
- Harness settings or link to the protocol doc
- Mean ms, stdev, drift percentage
- Ratio + CI (for vs-baseline claims)

Minimal publishable form (template — fill with your own numbers):

```
<kernel> <shape> on <device> (<AOT target>)
  omni  fp16: <ms> (stdev <ms>, <%>, drift <%>)  → <TFLOPS>
  torch fp16: <ms> (stdev <ms>, <%>, drift <%>)  → <TFLOPS>
  ratio torch_ms / omni_ms: <r>× CI95% [<lo>, <hi>]  → <speedup>×
```

### What NOT to publish

- **Minimum time as headline** ("cherry-pick").
- **Any number without drift report.**
- **Speedup ratio without CI.**
- **Anything from a single run with no warmup.**

---

## The shipping / quick benches are for CI only

Most projects' shipping benches do something like:

```python
for _ in range(WARMUP=5..10):  kernel()
for _ in range(ITERS=100):     kernel()
```

Problems with this pattern for publication-grade numbers:

1. Warmup of 5–10 iters is too short. BMG frequency + kernel state
   need more iters for small kernels (< 5 ms).
2. No drift check. A kernel that slows during timing reports a
   misleading "average".
3. Single input buffer → L2 cache reuse on memory-bound kernels.
4. No `pre_sleep` → thermal state variable.

Use the rigorous protocol above for any bench meant for publication,
regression investigation, or comparison. Keep the shipping benches
for CI regression-trend sanity only.

---

## When to use a short-preset

A half-length preset (half warmup + half timed iters) is acceptable
for:

- Dev smoke during kernel iteration.
- CI regression comparing to a moving average (not a single
  reference).

Not acceptable for:

- Publishing a TFLOPS number.
- Claiming a regression of less than ~5%.
- Any "% of peak" claim.

---

## Quick failure-mode checklist

When someone reports a TFLOPS number, ask:

| Check                                              | Fail response                            |
|----------------------------------------------------|------------------------------------------|
| Multi-sample with cooldown?                        | Redo with continuous run.                |
| No drift reported?                                 | Ask for first-half / second-half.        |
| Single input buffer on memory-bound kernel?        | Redo with rotation.                      |
| Warmup ≤ 20 iters on a < 5 ms kernel?              | Ask for ≥ 1000 iters warmup.             |
| Reports "min" as headline?                         | Ask for mean.                            |
| No CI on speedup claim?                            | Redo with bootstrap `paired_delta`.      |
| Compares numbers from different builds / branches  | Re-measure both sides with same binary.  |

---

## External tools

- `xpu-smi dump -d 0 -m 0` — device frequency / throttle state during
  a run. Useful for confirming thermal steady state.
- `ONEDNN_VERBOSE=1` — oneDNN primitive dispatch (for FP8 / INT4
  kernels). Confirms `impl=jit:...` vs `impl=ocl:ref:...`.
- `OMNI_XPU_DEBUG=<module>` — per-kernel shape and cache decisions.
- VTune GPU Compute Hotspots — diagnostic only; its overhead
  disqualifies it for steady-state numbers.

---

## Related skills

| Skill                             | When                                                        |
|-----------------------------------|-------------------------------------------------------------|
| `omni-xpu-kernel-overview`        | Package context; which kernels need which protocol nuances  |
| `omni-sdp-flash-attention`        | V-scaling state affects which kernel variant is timed       |
| `omni-onednn-fp8-linear`          | Shape-range guards; confirm `impl=jit:...` during bench     |
| `omni-gguf-dequant`               | Memory-bound; cache-bust is mandatory                       |
| `omni-debug-logging`              | Verify what the kernel actually did                         |

## References

- `references/bmg-bf16-variance.md` — empirical fp16 vs bf16 stdev
  on BMG ESIMD and reporting implications.
- `references/cache-bust-evidence.md` — when rotation matters, when
  it's harmless, and how to decide per-kernel.
- `references/rmsnorm-bf16-not-a-regression.md` — case study of
  how a wrong cooldown protocol invented a fake 3× slowdown.

## Source

LightX2V `xe2-esimd-gemm/references/perf-testing.md` — the upstream
protocol this skill adapts. Read that first if you want the full
context, then come back here for the omni_xpu_kernel-specific
adaptations.
