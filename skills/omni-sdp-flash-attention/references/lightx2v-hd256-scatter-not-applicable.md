# Why the LightX2V HD=256 `lsc_slm_scatter` trick does NOT apply here

A sibling project (LightX2V / ModelTC) ships an HD=256 SDP kernel
with a signature optimization: eliminate a register-transpose by
scattering softmax scores directly into a transposed SLM layout
via `lsc_slm_scatter<u32, 2>`.

This doc records **why we do not port that trick into the HD=128
SDP kernel**, so no future session re-investigates.

---

## What LightX2V's trick solves

HD=256 on BMG runs out of GRF (register) budget when storing the
whole softmax-score tile in fp32. Their kernel therefore **spills
scores to SLM**, reads them back in a different orientation for VS
GEMM, and the re-orientation **requires a register transpose**
(strided `select<...>` gather), producing hundreds of `mov(4|M0)`
instructions in ISA.

The `lsc_slm_scatter<u32, 2>` insight: pack two adjacent KV rows
into one `u32` via `shift+OR`, then scatter into the transposed SLM
layout — the register transpose never happens. Those hundreds of
`mov` instructions vanish.

The trick requires **all three** conditions:

1. Softmax-score tile **cannot fit in registers** (→ must use SLM).
2. The SLM layout needed by VS GEMM is the **transpose** of what QK
   GEMM naturally produces.
3. A strided register-side `select<...>` gather exists in the
   current kernel.

---

## Why HD=128 does not match

### Condition 1 fails: softmax stays in registers

With HD=128 tile sizes and doubleGRF, one thread holds its entire
softmax output matrix in register file. No SLM round-trip for S.

### Condition 2 fails: VNNI pack is stride-2 write, not transpose

The HD=128 kernel's score-rearrangement is a direct VNNI-packed
register-to-register conversion — dense `select<N, 2>` stride-2
writes interleaving two fp16 columns. Same SIMD lanes, no cross-lane
gather. The compiler emits a tight sequence of simd-wide converts +
stride-2 stores, not `mov(4|M0)` transposes.

### Condition 3 fails: no strided gather

Searching the HD=128 kernel for `select<8, 16>` / `select<16, 16>`
patterns yields nothing. Strided-select patterns in the kernel are
all stride-1 (contiguous) or stride-2 (VNNI interleave), both
single-cycle SIMD shuffles with no `mov` overhead.

Where `lsc_slm_scatter` **is** used in the HD=128 kernel, it's for
V pingpong (cooperative loads of V fragments into SLM for VS GEMM).
Those writes are already in the right layout; there is no transpose
to eliminate.

---

## Conclusion

- The register-transpose bottleneck that LightX2V fixes does not
  exist in HD=128.
- Porting `lsc_slm_scatter<u32, 2>` here would *add* a SLM
  round-trip where none exists today, almost certainly regressing.
- **Only revisit this** if an HD=256 kernel is added (e.g. for a
  model that needs large head_dim). In that case, go read the
  LightX2V skill for the exact invocation — note they found that
  **element-major** SLM layout was required; address-major
  interleave produced a ~0.12 rel_rms systematic error that was
  hard to debug.

---

## Generalizable lesson

Sibling project optimizations are worth reading even when they don't
port, because:

1. You learn the technique and can apply it when conditions match.
2. You document the three conditions cleanly enough that a future
   session can decide in a minute whether the port is viable.

Recording *why* something doesn't apply is as valuable as recording
*how* something does.

---

## Where to find the LightX2V skill

`ModelTC/LightX2V`, PR #1019, skill `xe2-sdp-hd256` — includes
`references/optimization-history.md` with the full scatter-layout
discussion.
