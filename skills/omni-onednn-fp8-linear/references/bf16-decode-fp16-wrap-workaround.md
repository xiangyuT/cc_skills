# Small-M bf16 FP8 GEMM — kernel-quality gap, and why we don't wrap

## The observation

For FP8 W8A16 GEMM on decode-style shapes (`M ≤ 8`, large K, large
N), bf16 input runs significantly slower than fp16 input on the
same shape. Ratio widens toward the smallest M and converges as M
grows. Around `M ≈ 64` the two dtypes crossover; by `M ≥ 256` they
equalize within a few percent.

## Root cause

With `ONEDNN_VERBOSE=all`, both dtypes dispatch to the same impl name
`jit:gemm:any` — no reference fallback. But oneDNN JIT-compiles a
different kernel per `(src_dtype, wei_dtype, dst_dtype)` tuple, and
the per-call exec times reported by oneDNN itself show the
disparity is **inside oneDNN**: the fp16 path has a tall-skinny /
GEMV-style variant that handles `M ≤ 8` efficiently; the bf16 path
lacks that variant and falls back to a general-purpose kernel that
doesn't tile well for small M.

This is an **upstream oneDNN kernel-quality gap**, not an
omni_xpu_kernel bug. Filing an issue upstream is the right
long-term fix.

## Why we do NOT patch this in the package

### 1. The package never hits M ≤ 8 in its target workloads

The package targets diffusion runtimes (ComfyUI / SGLang Diffusion /
Xinference). FP8 GEMM is called per-layer on the full latent token
buffer:

- Flux: M ≈ 4096
- Wan: M ≈ 3600
- SDXL: M ≈ 4096

These are **always prefill**. No autoregressive single-token
generation in a diffusion forward pass. At `M ≥ 256` the gap is
small-single-digit %, well inside measurement uncertainty, and the
published numbers for realistic shapes are already close to peak.
Fixing the decode path adds code complexity for **zero diffusion
benefit**.

### 2. The obvious fix is a correctness hazard

The obvious fix — transparently cast bf16 → fp16 before calling
oneDNN, cast back on return — works for synthetic tensors
(`torch.randn`, values in ~[-3, 3]). But:

- **fp16's max normal is 65504; bf16 goes to ~3.4e38.**
- Real LLM activations (especially attention logits before 1/√d
  scaling, SwiGLU intermediates, unnormalized residual streams)
  **routinely exceed 65504**.
- A value finite in bf16 becomes `+inf` after the cast. The oneDNN
  GEMM propagates `inf → NaN` into the output → ruins the whole
  forward pass.
- Synthetic-random benchmarks don't surface this because they don't
  produce the distribution tails that real LLM decode hits.

So the wrap is "faster and correct, usually" — exactly the bug
shape that causes rare NaN bursts in production. Users depending on
this package's bf16 semantics should get the real bf16 oneDNN
result, not a silent cast.

## If you hit this anyway (LLM decode on XPU)

Options, safest to most aggressive:

### A. Cast at the call site with a range guard

```python
def my_call(x_bf16, w_fp8, scales):
    if x_bf16.shape[-2] <= 8 and x_bf16.abs().max().item() < 65000:
        y = linear.onednn_w8a16_fp8(
            x_bf16.to(torch.float16), w_fp8, scales
        )
        return y.to(torch.bfloat16)
    return linear.onednn_w8a16_fp8(x_bf16, w_fp8, scales)
```

The `.abs().max().item()` is a GPU → CPU sync (~tens of µs), eating
most of the speedup at M=1. Worth it only when the sync cost is
small relative to the GEMM savings, e.g. with a KV cache of
known-bounded activation magnitude.

### B. Unconditional cast, scoped to post-norm layers

If you know the GEMM is called right after an RMSNorm / LayerNorm,
activations are bounded by `weight × input_rms / eps`, typically
well below 65504 for standard LLM hyperparameters. Cast
unconditionally at those specific call sites only — never as a
package-level default.

### C. Wait for upstream oneDNN fix

The right long-term fix is in oneDNN: the bf16 small-M path should
route through the same tall-skinny variant that fp16 uses. File an
issue upstream with the M-sweep evidence.

## Summary for the package

- Kernel is correct as shipped. Don't patch.
- Document the gap here for users who hit it outside diffusion.
- Open an upstream oneDNN issue when there's bandwidth.

## Generalizable lesson

When benchmarks show a dtype gap on a kernel the package doesn't
actually exercise, the right move is often **document, don't
patch**. Patches for phantom use cases cost complexity and can
introduce real correctness hazards (like fp16 range underflow on
realistic activations) for zero real benefit.

## Related

- `omni-onednn-fp8-linear/SKILL.md` — where this gap is summarized.
- `omni-kernel-benchmarking` — how to measure this rigorously
  without being fooled by warmup curves.
