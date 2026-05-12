---
name: omni-norm-kernels
description: >
  Design methodology for the omni_xpu_kernel normalization primitives on
  Intel Xe2: RMSNorm, LayerNorm, fused Add+RMSNorm, and fused_rms_norm_linear
  (RMSNorm chained into projection matmul without a VRAM round-trip).
  Covers the runtime-NB template-dispatch ladder (why manual, not
  constexpr-if), hidden-size constraints (divisibility, max), the L3-cache
  fusion trick in fused_rms_norm_linear, and the bf16 RMSNorm warm-up
  caveat that misleads naive benchmarks.
  Trigger for: rms_norm, layer_norm, fused_add_rms_norm,
  fused_rms_norm_linear, hidden_size divisibility, L3 cache fusion,
  bf16 norm warm-up curve.
---

# omni-norm-kernels — normalization-kernel design

Four ESIMD normalization primitives on Intel Xe2, memory-bound,
targeting most of DRAM bandwidth at realistic shapes. This skill
covers the *design* — template dispatch, fusion rationale, size
constraints, benchmarking caveats.

---

## The four primitives

| Primitive                    | What it computes                                              |
|------------------------------|---------------------------------------------------------------|
| `rms_norm`                   | `out = rmsnorm(input) * weight`                               |
| `layer_norm`                 | `out = (input − mean) / sqrt(var + eps) * weight + bias`      |
| `fused_add_rms_norm`         | `residual += input; input = rmsnorm(residual) * weight` (in-place) |
| `fused_rms_norm_linear`      | `out = rmsnorm(input, norm_weight) @ proj_weight.T`           |

All accept fp32/fp16/bf16 on XPU. Shape constraints:
`hidden_size % 32 == 0`, `hidden_size ≤ 8192`.

---

## Template dispatch ladder — why manual, not `constexpr if`

Each primitive is parameterized on `(dtype, block_count, block_size)`.
`block_count` (NB) depends on `hidden_size` and varies widely
(NB = 1 for tiny hidden_sizes, NB = 32 for max). Dispatch picks the
template instantiation at runtime:

```cpp
// Pseudocode
if (nb <= 1)  return rms_norm_kernel<IT, 1,  BS>;
if (nb <= 2)  return rms_norm_kernel<IT, 2,  BS>;
if (nb <= 4)  return rms_norm_kernel<IT, 4,  BS>;
if (nb <= 8)  return rms_norm_kernel<IT, 8,  BS>;
if (nb <= 16) return rms_norm_kernel<IT, 16, BS>;
return rms_norm_kernel<IT, 32, BS>;
```

### Why this pattern and not a runtime NB loop

Each branch instantiates a **different** kernel, with NB baked in at
compile time. That lets the compiler fully unroll NB-sized inner
loops, keeping all live state in GRF without register spills. A
dynamic NB loop would spill.

### Why this pattern and not `constexpr if`

`constexpr if` needs `NB` to be a compile-time value at the call
site. It isn't — it depends on runtime `hidden_size`. The ladder
is the right mechanism for "one of a small fixed set of compile-time
shapes, picked at runtime".

### When to use this dispatch pattern

Any kernel whose inner loop count depends on input shape but whose
shape is drawn from a small known set. Reuse for shape-parameterized
dequant, shape-parameterized reductions, etc.

---

## `fused_rms_norm_linear` — the L3-cache trick

Typical unfused Python:

```python
h = rms_norm(w_norm, x)   # 1 kernel launch, writes M×K to VRAM
y = F.linear(h, w_proj)   # 1 kernel launch, reads M×K from VRAM
```

The intermediate `h` bounces through VRAM — wasted bandwidth.

Fused version chains the ESIMD RMSNorm and an oneDNN matmul in C++
with no Python round-trip. The normalized tile stays in **SLM or L3**
(not VRAM) between the two ops; only the final output is written to
VRAM.

Savings scale with K (bigger K saves more bytes per unit compute).

**Implementation constraint**: same primitive-cache pattern as
FP8 GEMM / SVDQuant (`omni-onednn-fp8-linear`) — cache the oneDNN
matmul primitive keyed by projection shape + dtype. Reusing the
fused function with many different `proj_weight` shapes fills the
cache.

### When this fusion is a win vs unfused

Always, when available — the intermediate was pure bandwidth waste
in the unfused path. The only reason to call the two ops separately
is if something between them consumes the intermediate (e.g. a
residual connection written elsewhere).

---

## `fused_add_rms_norm` — the residual in-place pattern

Transformer decoder's standard pattern:

```python
residual = residual + x
x = rms_norm(w, residual)
```

Fused in-place:

```python
norm.fused_add_rms_norm(x, residual, w, eps=1e-6)
# residual  ← residual + x
# x         ← rmsnorm(updated residual) * w
```

Saves one kernel launch **and** one VRAM round-trip (updated
residual read twice otherwise). Reusable pattern: whenever an
in-place residual accumulation precedes a normalization, fuse them.

---

## Constraints and failure modes

| Check             | Limit                                         |
|-------------------|-----------------------------------------------|
| `hidden_size`     | ≤ 8192                                        |
| `hidden_size % 32`| must be 0                                     |
| Input dtype       | fp32 / fp16 / bf16                            |
| Device            | XPU                                           |

- `hidden_size > 8192`: no NB=64 path (SLM budget). Fall back to
  PyTorch native `F.rms_norm` or split the hidden_size dimension.
- `hidden_size % 32 != 0`: block_load<T, 32> goes out of bounds.
  Pad first.

Enforce these with `TORCH_CHECK` at the binding boundary.

---

## Benchmarking gotcha: bf16 RMSNorm warm-up curve

The bf16 RMSNorm path on some shapes has an unusually slow warm-up:
kernel time can **climb** over the first 100+ calls from a low value
to a steady plateau. This is **not a performance regression** —
template is identical to fp16 (no dispatch, no fallback) and
steady-state bf16 is within a few percent of fp16.

But it means any bench with < 100 warmup iterations on bf16 RMSNorm
will **under-report steady-state latency** and may invent fake
fp16-vs-bf16 deltas.

### Rule

If you see "bf16 much faster than fp16" on RMSNorm, you're looking
at warm-up, not steady state. Add more warmup iterations (100+) and
re-measure before concluding.

The suspected cause is driver-side state (SLM preload or similar),
not GPU clock — an unusually long wall time between calls makes
this more visible, not less.

This caveat is preserved as a reference under the benchmarking
skill. See `omni-kernel-benchmarking/references/rmsnorm-bf16-not-a-regression.md`.

---

## Related skills

| Skill                         | When                                                         |
|-------------------------------|--------------------------------------------------------------|
| `omni-xpu-kernel-overview`    | Package context                                              |
| `omni-onednn-fp8-linear`      | Same primitive-cache pattern in `fused_rms_norm_linear`      |
| `omni-debug-logging`          | `OMNI_XPU_DEBUG=norm` for per-call shape logs                |
| `omni-kernel-benchmarking`    | bf16 warm-up caveat, cache-bust methodology                  |
