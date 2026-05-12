---
name: omni-sdp-flash-attention
description: >
  Design rationale for the omni_xpu_kernel SDP / Flash Attention kernel on
  Intel Xe2 (BMG / Arc B-series). Covers the methodology behind its
  optimizations, not the ISA: K-prefetch-distance as the dominant win,
  adaptive V-scaling to prevent fp16 accumulator overflow without regressing
  the common case, kv_len padding to 16 as a hardware-trap workaround, the
  fast/safe kernel-variant split, and the compile-time config-struct pattern
  for multi-target ESIMD kernels. No kernel source; see references for
  generalizable sub-topics.
  Trigger for: flash attention on XPU, K prefetch, V-scaling, fp16
  accumulator overflow, kv_pad, 2D block load boundary, sdp_fp16_fast vs
  sdp_fp16, sdp_config.h, zero-overhead hardware config, doubleGRF.
---

# omni-sdp-flash-attention — design rationale

ESIMD Flash Attention for Intel Xe2 with doubleGRF register allocation.
Shipped as a `dlopen`-ed sidecar from the main host extension. This
skill covers the *why* of the key design decisions. The kernel source
itself lives in the upstream repo.

**Input contract** (stable across revisions): `q, k, v = [B, L, H, D]`
fp16/bf16 on XPU, `B == 1`, `D ∈ {64, 128}`. Anything else falls back
to PyTorch's `scaled_dot_product_attention`.

---

## Must-follow rules

1. **B == 1.** The kernel has no batch loop; batch > 1 must be
   externally flattened into L or looped in Python.
2. **D ∈ {64, 128}.** Other head_dims fall back to PyTorch. Adding a
   new head_dim means writing a new template instantiation and a new
   config struct — see `references/config-template.md`.
3. **`kv_len` is padded to a multiple of 16 at the Python/C++
   boundary.** Do not remove this pad — BMG 2D block loads past the
   surface boundary return **garbage**, not zero (unlike what the SYCL
   spec suggests). See `references/kv-pad-hardware-trap.md`.
4. **V-scaling is automatic, adaptive, and cached.** Most models never
   trigger it; models with `|V|_max ≥ threshold` get a per-head scale
   folded into the softmax temperature. Zero overhead on the common
   path. See `references/v-scaling-overflow.md`.
5. **doubleGRF applies only to the sidecar `.so`**, not the main
   extension. That's why they are separate libraries. See
   `references/dispatch-and-sidecar.md`.

---

## The dominant optimization: K-prefetch distance

The single largest speedup on BMG came from **moving** the K-tile
prefetch — not from adding more prefetches. The original kernel issued
`lsc_prefetch_2d` right before the K tile was re-consumed (tens of
cycles of warning); moving the prefetch to fire right after V-load gives
the full softmax + compensation + V-load window to hide the L2 miss
(hundreds of cycles).

Why this matters: on BMG, L2 miss latency is in the low hundreds of
cycles. Prefetch hints issued less than that many cycles before use
are effectively useless — the DPAS still stalls. Prefetches issued
well beyond that window are fully hidden.

**Generalizable lesson**: for any memory-bound-in-the-hot-loop kernel
on Intel GPU, measure L2 miss latency on the target GPU, count cycles
between prefetch-issue and consumption, and place the prefetch at the
first independent work block that gives you ≥ miss-latency of cover.
Adding more prefetches when the distance is insufficient does not
help. See `references/k-prefetch-distance.md` for the full analysis.

---

## Protecting against fp16 accumulator overflow

The ESIMD HD=128 FP16 variant accumulates `∑ softmax_weight × V` in
fp16. For most diffusion models, `|V|_max` is small and the
accumulator stays well below 65504. For some models (large-DiT,
Qwen-style), `|V|_max` can exceed 1000 and the accumulator Inf's → NaN
propagates through the whole output.

Two layers of protection, both paying ~0 cost on the common case:

1. **In-kernel fp32 compensation + clamp** — intermediate compensation
   is computed in fp32 and clamped to ±65504 before the fp16 cast.
2. **Host-side adaptive per-head V-scaling** — on a sampled interval
   (e.g. every N calls), measure `|V|_max`. If above threshold, compute
   a per-head scale, pre-scale V, and fold the inverse into
   `norm_alpha`. Cache the decision + the scaled-alpha tensor.

When `needs_scaling == false` and a no-clamp `sdp_fp16_fast` variant
ships, dispatch skips the clamp too. Net: zero overhead for normal
models, numerically safe for pathological ones.

See `references/v-scaling-overflow.md` for the `effective_alpha`
fold-in math, why per-head (not global) scale is required, and the
"detect-once / cache / fast-path-fallback" pattern that generalizes
beyond this kernel.

---

## The kv_len = multiple of 16 hardware trap

ESIMD `lsc_load_2d<T, W, 16, ...>` reads 16 rows at a time. If
`kv_len = 100`, the last tile covers rows 96..111 — rows 100..111 are
past the surface. The SYCL docs suggest OOB lanes return zero; BMG
actually returns **neighboring VRAM contents**, producing NaN outputs
in the attention computation.

The fix is host-side: pad K and V to a multiple of 16 with zeros,
pass the **original** `kv_len` to the kernel so the softmax boundary
mask correctly excludes the padded rows. Pad cost is negligible next
to SDP compute.

Keep the kernel simple. Do not try to handle this inside the kernel
— pre-tile branching kills DPAS density. See
`references/kv-pad-hardware-trap.md`.

---

## Compile-time hardware config pattern

Same ESIMD source targets multiple Xe2/Xe3 products (BMG / PVC / LNL /
PTL) with different sweet-spot tile sizes. Rather than `#ifdef` branches,
use a `constexpr` struct-per-target and a preprocessor-selected `using
ActiveConfig = ...`. Inheritance lets HD=64 configs override just
`HEAD_DIM` and related derived constants.

Because every member is `static constexpr`, the compiler folds values
into immediate operands — the generated ISA is bit-identical across
configs that resolve to the same values. Zero-overhead hardware
parameterization, verifiable by A/B-comparing disassembly.

See `references/config-template.md` for the full pattern plus a generic
template you can copy for other ESIMD kernel families.

---

## Failed experiments — keep as a ledger

Several seemingly-reasonable optimizations were tried and did not work.
Short list:

- **Add more `lsc_prefetch_2d` hints** elsewhere in the loop → 0%.
  Memory side was never oversubscribed.
- **Replace `exp2` with a polynomial `fast_exp2`** → ~16% regression.
  GPU EM (math) unit and XVE run in parallel; moving transcendentals
  onto XVE collapses that concurrency.
- **Increase KV_TILE or Q_PER_THREAD** → register spill under
  doubleGRF's 16 KB/thread budget.
- **Per-call V_max measurement without caching** → ~50% of SDP time
  spent in the safety check. Motivated the recheck-interval cache.

Full ledger with root-cause analysis: `references/failed-experiments.md`.
**Rule**: when adding a new optimization idea here, record the result
(success or failure) in that file so nobody re-discovers a dead-end.

---

## Two-layer architecture (Python / C++ / ESIMD sidecar)

```
Python         C++ (_C.so)                    ESIMD sidecar (lgrf_sdp.so)
sdp.sdp(q,k,v) ─▶ kv_pad ─▶ V-max sample ─▶   dlopen'd fn-pointer table
                  cache v_scale / alpha        (one entry per dtype/HD)
                  dispatch fast vs safe
```

Five C entry points in the sidecar (HD=128 fp16 / HD=128 bf16 io /
HD=128 fp16 fast / HD=64 fp16 / HD=64 bf16 io). Caller picks one
based on input dtype, HD, and V-scaling state. `dlopen` runs exactly
once via `std::call_once`.

See `references/dispatch-and-sidecar.md` for cross-platform `dlopen` /
`LoadLibrary` mechanics.

---

## Why the LightX2V HD=256 `lsc_slm_scatter` trick does **not** apply

A sibling project (LightX2V) ships an HD=256 SDP kernel that eliminates
a register-transpose by scattering softmax scores directly into a
transposed SLM layout (`lsc_slm_scatter<u32, 2>`). That optimization
depends on three conditions — softmax tile spills to SLM, VS GEMM
needs transposed layout, and the kernel currently has a strided-gather.
**None of those three hold for HD=128 in this package**: softmax stays
in registers, VNNI pack is a contiguous stride-2 write, and no strided
gather exists to eliminate.

Porting the trick here would *add* a SLM round-trip where none exists.
Recorded as a no-op to prevent re-investigation. See
`references/lightx2v-hd256-scatter-not-applicable.md`.

---

## When *not* to touch this kernel

- Proposing bigger tiles without accounting for doubleGRF's per-thread
  register budget → will spill.
- Proposing a polynomial replacement for a `math` transcendental → will
  collide with DPAS/ALU co-scheduling.
- Proposing to defer V-scaling safety to "users who care" → V overflow
  produces NaN that silently propagates; cannot be opt-in.
- Proposing to remove kv_pad because "real models are multiples of 16"
  → flux-self-4096 is, wan-self-1560 isn't; the pad handles both.

---

## Related skills

| Skill                             | When                                                               |
|-----------------------------------|--------------------------------------------------------------------|
| `omni-xpu-kernel-overview`        | Package-level context: why two `.so`s, where this fits             |
| `sycl-esimd-wheel-build-linux`    | Build flags, OMNI_XPU_DEVICE, editable-install trap                |
| `omni-debug-logging`              | `[omni_xpu::sdp]` output decoding, enabling selectively            |
| `omni-kernel-benchmarking`        | How to measure SDP TFLOPS defensibly                               |

## References (in this skill)

| File                                                | What's in it                                                         |
|-----------------------------------------------------|----------------------------------------------------------------------|
| `references/k-prefetch-distance.md`                 | The dominant optimization: distance > count                          |
| `references/v-scaling-overflow.md`                  | fp16 accumulator protection; detect-once/cache pattern               |
| `references/kv-pad-hardware-trap.md`                | BMG 2D block load OOB behavior; host-side pad rationale              |
| `references/failed-experiments.md`                  | Optimizations tried and why they didn't work                         |
| `references/dispatch-and-sidecar.md`                | `dlopen` + fn-pointer table, cross-platform                          |
| `references/config-template.md`                     | Compile-time hardware config struct pattern (reusable)               |
| `references/lightx2v-hd256-scatter-not-applicable.md` | Why a sibling project's HD=256 trick doesn't port to HD=128        |
