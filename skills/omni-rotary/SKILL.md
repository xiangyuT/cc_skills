---
name: omni-rotary
description: >
  Design methodology for the omni_xpu_kernel rotary position embedding
  (RoPE) kernel on Intel Xe2. Fuses bf16 ↔ f32 promote/demote with
  rotation in one ESIMD kernel. Key design decision: **per-row seq_idx
  lookup** instead of host-side cos/sin expansion to [B*S*heads,
  head_dim/2] — saves the per-call cost of expanding cos/sin.
  Trigger for: rotary_emb, RoPE on XPU, cos/sin cache expansion,
  freqs_cis, fused bf16 f32 rotary, head_dim 64 vs 128.
---

# omni-rotary — rotary embedding design

Fused RoPE kernel on Intel Xe2. One ESIMD kernel does: read
bf16/fp16/fp32 input, promote to f32 internally (precision), apply
rotation, demote back to input dtype, write output. Supports
`head_dim ∈ {64, 128}`.

This skill documents design decisions; kernel source lives upstream.

---

## API shape

```python
out = rotary.rotary_emb(
    x,           # [total_rows, head_dim] bf16/f16/f32 on XPU
    cos_cache,   # [seq_len, head_dim/2] f32
    sin_cache,   # [seq_len, head_dim/2] f32
    seq_len,     # int
    heads,       # int
)
```

**Row-layout convention**: `total_rows = B * S * heads` flattened.
For row `i`, `seq_idx = (i / heads) % S`. Caller reshapes input
from `[B, S, heads, head_dim]` to `[B*S*heads, head_dim]`
contiguous before calling.

---

## Key design decision: unexpanded cos/sin cache

### The naive approach — host-side expansion

An obvious wrapper:

1. Reshape `x` to `[B*S*heads, head_dim]`.
2. Expand `cos/sin` from `[S, head_dim/2]` to `[B*S*heads, head_dim/2]`
   via `repeat_interleave(heads).repeat(B)`.
3. Call a kernel that takes two same-shape `[row, head_dim/2]` caches.

The problem: the expanded cache can be tens of MB **per call**. For
a Wan-style config (B=1, S=3600, heads=40, head_dim=128): ~72 MB of
alloc-and-free per RoPE call. Pure bandwidth waste for something
the kernel could compute itself with two integer ops per row.

### The chosen design — per-row seq_idx compute

Kernel takes the **unexpanded** `[S, head_dim/2]` cos/sin caches
plus `seq_len` and `heads` as scalars. Each work-item computes its
own `seq_idx = (row_id / heads) % S` in-kernel and reads the
correct cos/sin row directly. No expansion, no allocation.

Per work-item cost: one integer divide + one modulo. Both are cheap
on Intel GPU, vastly cheaper than `repeat_interleave`'s DRAM-to-DRAM
copy.

### Generalizable lesson

When an obvious preprocessing step produces a buffer that's
tens-of-MB and could be computed from tiny scalars inside the
kernel — compute it inside. The "preprocessing" is often a mental
artifact of how humans describe the op, not an actual perf
requirement.

---

## Supported head_dims

- `head_dim = 64` — SD3.5, z-Image, LTX-Video
- `head_dim = 128` — Flux, Wan, Qwen Image, standard LLMs

Other head_dims are not supported (TORCH_CHECK rejects). Adding
one:

1. Kernel dispatches on compile-time `HEAD_DIM` constant; add a new
   template instantiation.
2. Add a dispatch branch at the Python binding.
3. `head_dim` must be a power of 2 (or at least a multiple of 32)
   for `block_load` efficiency.

---

## Alternative designs considered (and rejected)

- **Process flat `[B*S*heads, head_dim]` without seq_idx lookup** —
  requires expanded cos/sin. Rejected, per above (25+ MB alloc
  per call).
- **Store cos/sin as complex64** (often how `torch.polar` exposes
  them). Kernel would need to deinterleave cos/sin into separate
  SIMD registers — extra per-element ALU. Callers already have
  separate cos/sin in most call sites, so the complex64 layout
  would be a minor inconvenience.
- **Per-sequence-position kernel launch** (one launch per seq
  index). Kernel launch overhead is microseconds; for S=3600 that's
  tens of ms of pure launch cost. Catastrophic.

Chosen: single launch over flat `[B*S*heads]` rows, per-row
seq_idx compute.

---

## Typical integration

RoPE is the step right before Q/K enter SDP. The caller computes
Q/K projections → reshapes to `[B*S*heads, head_dim]` → calls
`rotary_emb(q, cos, sin, S, heads)` and same for K → reshapes back
to `[B, S, heads, head_dim]` → calls `sdp.sdp(q, k, v)`.

There is no per-step broadcast allocation, no complex64
manipulation, and no per-position launch overhead.

---

## Related skills

| Skill                         | When                                                 |
|-------------------------------|------------------------------------------------------|
| `omni-xpu-kernel-overview`    | Package context                                      |
| `omni-sdp-flash-attention`    | Consumer of the rotated Q/K                          |
| `omni-debug-logging`          | `OMNI_XPU_DEBUG=rotary` shape logs                   |
