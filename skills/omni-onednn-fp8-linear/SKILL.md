---
name: omni-onednn-fp8-linear
description: >
  Design methodology for the omni_xpu_kernel FP8 W8A16 GEMM — a oneDNN
  matmul-based path for E4M3 / E5M2 weights × fp16/bf16 activations on
  Intel Xe2. Covers the set_scales_mask-vs-set_scales trap (silent
  fallback to the slow reference path), primitive caching keyed by shape,
  the shape-range guard, the small-M bf16 decode gap (documented but
  intentionally not patched), and E4M3 vs E5M2 trade-offs. No kernel
  source; focus on reusable patterns for oneDNN-backed kernels.
  Trigger for: onednn_w8a16_fp8, fp8 W8A16, E4M3, E5M2, fp8_cache_clear,
  jit:gemm:any, set_scales_mask, primitive caching, FP8 shape range,
  decode-bf16 vs fp16 gap.
---

# omni-onednn-fp8-linear — FP8 W8A16 GEMM design

oneDNN matmul-primitive-based FP8 W8A16 path, supporting both E4M3 and
E5M2 weights. This skill covers the design choices — shape guards,
primitive caching, the `set_scales_mask` trap, dtype selection — not
the kernel itself.

---

## API shape

```python
from omni_xpu_kernel import linear

out = linear.onednn_w8a16_fp8(x, weight, scales, bias=None)
# x:      [M, K] fp16/bf16
# weight: [N, K] float8_e4m3fn or float8_e5m2
# scales: [N]    fp32
# bias:   [N]    same dtype as x, optional
# out:    [M, N] same dtype as x
linear.fp8_cache_clear()
```

E4M3 vs E5M2 are auto-detected from the weight tensor's scalar_type.

---

## CRITICAL: set_scales_mask vs set_scales

oneDNN's matmul primitive-attr has **two scale APIs that look
identical but behave very differently**:

| API call                                               | Behavior                                          |
|--------------------------------------------------------|---------------------------------------------------|
| `attr.set_scales_mask(DNNL_ARG_WEIGHTS, mask)`         | JIT-compiled path, fast                           |
| `attr.set_scales(DNNL_ARG_WEIGHTS, mask, shape, dt)`   | **Silent fallback to reference path**, very slow  |

Always use `set_scales_mask`. After creating the primitive descriptor,
**verify** the impl name string does not contain `"ref"`:

```cpp
std::string impl = pd.impl_info_str();
if (impl.find("ref") != std::string::npos) {
    // WARNING: slow fallback path
}
```

With `OMNI_XPU_DEBUG=fp8` you can see the impl name printed at every
cache miss. If it shows `impl=ocl:ref:any` instead of `impl=jit:gemm:any`
— something is wrong.

**Why this trap exists**: the signatures differ in ways easy to miss
when copying from examples. The docs don't flag it. The only reliable
defense is inspecting `pd.impl_info_str()` programmatically.

---

## Primitive caching keyed by shape

oneDNN primitive construction is slow (millisecond-scale); execution
is fast (microsecond-scale). Cache the `memory_desc` + primitive
objects under a key of:

```
(device_index, input_dtype, M, K, N, has_bias)
```

Weight dtype (E4M3 vs E5M2) is inferred from `input_dtype` via the
tensor's scalar_type, so it's captured indirectly. If a future design
needs to separate weight dtype from activation dtype independently,
add it explicitly to the key.

On hit: reuse stored objects (~µs overhead).
On miss: full oneDNN primitive construction (~ms overhead).

Guard with a mutex around cache lookup and insertion. Expose
`fp8_cache_clear()` + `fp8_cache_stats()` so benchmarks can reset
state between runs.

**This pattern reapplies** to any oneDNN primitive, not just FP8 —
see `omni-svdq-w4a4` for the INT4 GEMM variant and `omni-norm-kernels`
for `fused_rms_norm_linear` which uses the same pattern.

---

## Shape guards

The JIT path has a tuned performance window. Outside that window, it
either falls back or produces disappointing numbers. Enforce the
window explicitly:

```cpp
if (m > M_MAX || k < K_MIN || effective_n > N_MAX) {
    TORCH_CHECK(false, "FP8 GEMM shape outside efficient range ...");
}
```

Typical reasoning:
- `M ≤ M_MAX`: beyond some threshold the JIT picks an inefficient
  tiling.
- `K ≥ K_MIN`: smaller K doesn't amortize the FP8 → FP16 dequant.
- `effective_N ≤ N_MAX`: kernel's output tile is sized for this N range.

To run larger N, **split across N** (two GEMMs with N_small each).
Larger M or smaller K should fall back to a dequant → bf16 GEMM path
outside this kernel.

Rather than silently accepting out-of-range shapes and producing
bad performance, fail loudly. Downstream dispatch can catch the
exception and pick an alternative.

---

## Small-M bf16 decode — kernel-quality gap, documented but NOT patched

oneDNN's `jit:gemm:any` for `M ≤ 8` bf16 is 3–5× slower than the
fp16 path on the same shape. Both dispatch to the same impl name,
but oneDNN JIT-compiles different kernels per (src, wei, dst) tuple
— fp16 has a tall-skinny / GEMV-style variant for small M that bf16
lacks.

**This package does not patch around it**, for two reasons:

1. The package targets diffusion runtimes. FP8 GEMM is always called
   in prefill mode (M = latent token count; Flux 4096, Wan 3600,
   SDXL 4096). `M ≤ 8` never arises in these workloads.

2. The obvious fix — transparent bf16 → fp16 cast — is a correctness
   hazard. fp16's max normal is 65504; bf16 goes to ~3.4e38. Real
   LLM activations (attention logits pre-scale, SwiGLU
   intermediates, unnormalized residual streams) routinely exceed
   65504. A value finite in bf16 becomes +inf after cast, propagates
   NaN through GEMM → ruins the forward pass. Synthetic
   `torch.randn` benchmarks don't surface this because they don't
   produce the distribution tails real LLMs hit.

See `references/bf16-decode-fp16-wrap-workaround.md` for the full
M-sweep, the correctness analysis, and three call-site-level
workarounds (range-guarded cast / post-norm-only cast / wait for
upstream oneDNN fix).

---

## E4M3 vs E5M2 — when to pick which

- **E5M2 is faster** (double-digit %) than E4M3 on BMG, because E5M2's
  5-bit exponent matches fp16 — upconverting float8_e5m2 → fp16 is a
  bit reinterpret. E4M3's 4-bit exponent needs a range remap,
  compiled into extra per-element work.
- **E4M3 has better numeric range**, traded for smaller dynamic range.
- If you control the quantization recipe, prefer E5M2 for
  throughput-sensitive inference. If you're loading pretrained E4M3
  checkpoints, stick with E4M3.

---

## Typical workflow for adding a new FP8 call site

1. Ensure weight is `torch.float8_e4m3fn` / `torch.float8_e5m2` on
   XPU. Prefer E5M2 if you control quantization.
2. Ensure scales are `float32` on XPU, shape `[N]`.
3. Verify the shape is inside the guard window.
4. Cold call to populate the cache; subsequent calls hit.
5. With `OMNI_XPU_DEBUG=fp8`, confirm `impl=jit:gemm:any` (not `ref`).

---

## Related skills

| Skill                         | When                                                    |
|-------------------------------|---------------------------------------------------------|
| `omni-xpu-kernel-overview`    | Package context, branch matrix                          |
| `omni-svdq-w4a4`              | Sibling oneDNN path (INT4), same primitive-cache idea   |
| `omni-norm-kernels`           | `fused_rms_norm_linear` uses the same caching pattern   |
| `omni-debug-logging`          | `OMNI_XPU_DEBUG=fp8` cache output                       |
| `omni-kernel-benchmarking`    | Measuring FP8 TFLOPS defensibly (watch for cache MISS)  |

## References

- `references/bf16-decode-fp16-wrap-workaround.md` — why the obvious
  fp16-wrap workaround is a correctness hazard, and call-site
  alternatives.
