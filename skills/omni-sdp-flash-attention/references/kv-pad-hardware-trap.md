# BMG/Xe2 2D block-load boundary trap

A hardware behavior on Intel Xe2 (BMG) that causes silent NaN output
without a clear error message. The fix is simple (pad host-side), but
the failure mode — garbage reads past a surface boundary — is subtle
enough that every ESIMD kernel using `lsc_load_2d` needs a deliberate
pad strategy.

---

## The behavior

ESIMD `lsc_load_2d<T, W, H, ...>` reads H rows at a time from a 2D
surface. When the read region extends past the allocated surface
height:

- **SYCL spec expectation**: out-of-bounds lanes return `0` (zero-padded).
- **BMG / Xe2 actual behavior**: out-of-bounds lanes return
  **garbage** — typically whatever is in VRAM past the surface,
  possibly NaN, possibly stale data, sometimes zero by luck.

This is a pass-through of an LSC hardware quirk, not a SYCL spec
violation you can trust the runtime to paper over.

---

## Why this causes silent NaN in SDP

The SDP kernel's QK GEMM loads 16 K-rows per tile. If `kv_len = 100`,
the last tile covers rows 96..111, where rows 100..111 are past the
surface. Garbage K values produce garbage QK scores. Even after the
softmax boundary mask zeros those positions, `exp(garbage)` may
return NaN **before** the mask applies, and NaN propagates through
subsequent reductions.

The symptom is a model that produces NaN output only on certain
sequence lengths, seemingly at random — any `kv_len % 16 != 0` is
the common factor.

---

## The fix: host-side pad to multiple of 16

Pre-compute the pad at the Python / C++ boundary, allocate zero-filled
K and V of `kv_len + pad` rows, copy the real data into the first
`kv_len` rows, and pass the **original** `kv_len` to the kernel as a
scalar so the softmax boundary mask correctly excludes the padded
rows.

Net cost: one `torch.zeros` + one `copy_` per call. For typical
workloads this is small microseconds, invisible against SDP compute.

Correctness sketch:
- Padded rows in QK GEMM → `0 × anything = 0` score
- Softmax mask also zeroes them (belt + suspenders)
- VS GEMM multiplies by zero V → contributes zero to accumulator

---

## Why not fix inside the kernel

A kernel-side solution would check `row_id < kv_len` per tile and
conditionally load. Two reasons not to:

1. **Pre-tile branching kills DPAS density.** Conditional loads in
   the K loop introduce register pressure and break the `#pragma
   unroll` prefetch pipeline that the K-prefetch-distance
   optimization depends on.
2. **Pad cost is small.** Padding a few rows at host side is cheap
   next to the kernel compute.

Keep the kernel simple; handle the pad at the boundary.

---

## Related kernel constraints

For any ESIMD kernel using `lsc_load_2d`:
- Surface height **should** be a multiple of the load tile height.
- Surface width **should** be a multiple of the load tile width.
- If not, pad at host side; pass the real extent to the kernel for
  masking.

The kernel's Q side typically doesn't need this treatment because
the Q tile is per-workgroup and doesn't loop — only the K/V tile
loop exposes the hazard.

`block_load` (1D) and `gather` on BMG follow the SYCL spec (return
zero OOB). Only `lsc_load_2d` has this quirk.

---

## Generalizable lesson

> When the SYCL spec says "returns zero out of bounds" and your GPU
> returns garbage, that's not a spec violation you can ignore — it's
> a pass-through of an LSC hardware behavior. Always pad host-side
> for 2D block loads on BMG.

Applies to any ESIMD kernel on Xe2 that uses `lsc_load_2d` against a
dimension that may not be a multiple of the tile height.

---

## Related

- SDP SKILL.md — where kv_pad is listed as a must-follow rule.
- `k-prefetch-distance.md` — why kernel-side conditionals would break
  the prefetch pipeline.
