# Cache-bust: when it matters, when it doesn't

A rule of thumb for whether to rotate through multiple input
buffers when benchmarking memory-bound kernels. Distilled from a
direct measurement comparing 1-buffer vs 8-buffer protocols on
memory-bound GGUF dequant at two scales of payload.

---

## Principle

For memory-bound kernels, running the same kernel on the same
input tensor N times reports bandwidth that includes **L2 cache
hits after iter 1**. To get the true DRAM-bound number, rotate
through enough distinct input buffers that their aggregate size
exceeds L2.

BMG L2 is ~16 MB (shared across all XE cores).

---

## When rotation matters vs when it doesn't

### Small payload per call (< L2 / 4)

Input fits in L2. After one iter, the L2 holds the input. Output
writes are cache-line-wide; L2 write coalescing applies after the
first call. Second and subsequent calls can reuse L2.

**Rotation required** to avoid the L2 uplift. Without rotation, BW
numbers look significantly higher than true DRAM performance.

### Medium payload (L2 / 4 to L2)

Input partially fits. Single-buffer runs may see 10–30% L2 hit
fraction on subsequent iters. Rotation helps.

### Large payload (> L2)

Each call already exceeds L2 — data cannot live in L2 across iters
of the same buffer. Rotation is **harmless** but provides no
additional BW defense; numbers are already representative.

### Summary table (BMG, L2 ≈ 16 MB)

| Per-call I/O volume | Rotate?    | Why                                                |
|---------------------|------------|----------------------------------------------------|
| < 4 MB              | **Yes**    | Single-buffer L2 hit inflates BW materially        |
| 4 MB to 16 MB       | Recommended | Partial L2 residency across iters                  |
| > 16 MB             | Harmless    | Single buffer already cache-defeating              |

---

## Measurement counter-evidence: sometimes rotation shows no delta

Running 1-buffer vs 8-buffer on a GGUF dequant at two scales, under
a **short-run noisy protocol** (too-few iters, too-short timing):
both configurations report the same BW within each other's CI. This
is **not** evidence that rotation doesn't matter — it's evidence
that short-run timer jitter dominates, and the true rotation
signal is inside the noise.

To measure the rotation effect cleanly:
- Run 1000+ iters per sample.
- 100+ samples per configuration.
- Push stdev below ~2% via sample count before drawing conclusions.

**Lesson**: don't use a noisy protocol to "prove" a factor doesn't
matter. If your protocol can't resolve the effect at the size it
should have, the protocol is too noisy, not the effect too small.

---

## The harness API question

A bench harness can either allocate rotation buffers itself, or
expect the caller to provide them via a callable that takes the
iter index. The omni_xpu_kernel harness chose the caller-provides
approach because:

- Memory budget varies widely by kernel (tiny norm vs 1M-block
  GGUF).
- Eight buffers of a 1M-block GGUF tensor is ~144 MB on XPU — can
  OOM.
- The caller knows the right N_BUFFERS and the right construction
  function; the harness doesn't.

Recommended call pattern:

```python
N_BUFFERS = 8
bufs = [make_input() for _ in range(N_BUFFERS)]
def call(i, bufs=bufs):
    return kernel(bufs[i % N_BUFFERS])
```

---

## When to trust a number without cache-bust

- Kernel is **compute-bound**: SDP with long sequence, FP8/INT4
  GEMM at M ≥ 4096. Cache-bust effect on absolute time is typically
  small single-digit % — less than most noise floors. Rotate anyway
  for rigor; don't treat the absence as fatal if time-constrained.
- Kernel is **launch-overhead-bound**: per-call wall time under
  ~50 µs. Cache-bust is a second-order effect when timer jitter is
  first-order.

## When you MUST cache-bust

- Claiming `% of DRAM roofline`.
- Comparing two memory-bound kernels (GGUF variants, norm variants).
- Anything in a public CHANGELOG where the reader will convert to
  "GB/s".

---

## Related

- `omni-kernel-benchmarking/SKILL.md` — summary of the rotation
  rule.
- `bmg-bf16-variance.md` — the noise floor discussion that
  determines whether rotation effects are detectable.
