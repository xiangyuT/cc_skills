---
name: omni-svdq-w4a4
description: >
  Design methodology for the omni_xpu_kernel SVDQuant W4A4 path (nunchaku)
  on Intel Xe2. Ships INT4 weight unpack, per-group activation quant,
  oneDNN INT4 GEMM variants (vanilla, preconverted, fp32-accum, append_sum),
  and fused post-processing primitives. Key methodology: the signed-INT4
  to u4 XOR trick, the preconverted-weights pattern, and the
  multiply-by-reciprocal preference over GPU divide. No kernel source.
  Trigger for: SVDQuant, W4A4, nunchaku, oneDNN INT4 GEMM,
  onednn_int4_gemm_preconverted, packed XOR 0x88, u4 vs signed INT4,
  fused_smooth_mul_convert, fused_convert_add.
---

# omni-svdq-w4a4 — SVDQuant W4A4 design

INT4 weight × INT4/FP16 activation GEMM path for nunchaku SVDQuant
models on Intel Xe2. Combines ESIMD dequant/quantize with oneDNN u4
matmul and fused post-op primitives. This skill covers the design
choices — no kernel source.

---

## Data layout (nunchaku convention)

```
Packed weight: [N, K/2] uint8    low_nib = weight[n, 2k], high_nib = weight[n, 2k+1]
Scales:        [num_groups, N]   bf16 or fp16     (num_groups = K / group_size)
group_size:    64 (hardcoded)
Signed INT4:   range [-8, 7]
```

Dequant formula: `result[n, k] = int4_val[n, k] * scale[k / group_size, n]`.

---

## Key methodology: signed INT4 → u4 XOR trick

oneDNN's INT4 matmul primitive accepts **unsigned** 4-bit (u4, range
`[0, 15]`). Nunchaku stores **signed** 4-bit (range `[-8, 7]`). The
conversion is `packed ^= 0x88`:

```
signed 4-bit bits (at nibble position)   u4 bits
-8   = 1000                               0000  (flip sign bit)
-7   = 1001                               0001
-1   = 1111                               0111
 0   = 0000                               1000
 7   = 0111                               1111
```

Flipping bit 3 (`^ 0x08` per nibble) converts signed to unsigned.
A byte holds two nibbles, so `byte ^= 0x88` does both at once.
oneDNN's u4 GEMM internally re-interprets and the `-8` bias folds
implicitly through scale.

**Generalizable lesson**: when two encodings differ only by an
additive bias on each element and the bias is representable as a
bit-level XOR, a one-pass bitwise op is vastly cheaper than an
arithmetic `+/-` loop. Recognize this pattern when integrating any
sign-conventioned quantization with an unsigned-convention math
library.

---

## Four oneDNN INT4 GEMM variants

| Variant                                   | When to use                                              |
|-------------------------------------------|----------------------------------------------------------|
| `onednn_int4_gemm` (vanilla)              | Development / one-off — does `packed ^= 0x88` + bf16→fp16 scales per call |
| `onednn_int4_gemm_preconverted`           | **Production default** — per-model `prepare_onednn_weights()` amortizes conversions to zero |
| `onednn_int4_gemm_fp32acc`                | Slightly slower, better numeric precision                |
| `onednn_int4_gemm_add_to_output`          | Fused residual-add via oneDNN's `append_sum` post-op     |

**`_preconverted` is always preferred in production.** `packed ^= 0x88`
and `bf16 → fp16 scales` are conceptually trivial but measurable
per-call overhead; doing them once per model instead of per-call is
free.

---

## Per-call post-op fusion: multiply-by-reciprocal over divide

Common pattern around GEMM:

```
act_f16 = (act_bf16 / smooth_factor_bf16).to(fp16)
out_f16 = int4_gemm(act_f16, ...)
dst_bf16 = out_f16.to(bf16) + residual_bf16
```

Fused kernels replace the unfused Python with ESIMD primitives:

| Function                                   | What it does                                 |
|--------------------------------------------|----------------------------------------------|
| `fused_smooth_convert(x, smooth_factor)`   | `(x / smooth_factor).to(fp16)` — **divide**  |
| `fused_smooth_mul_convert(x, rcp_smooth)`  | `(x * rcp_smooth).to(fp16)` — **multiply**   |
| `fused_convert_add(out, result, residual)` | `out = bf16(result) + residual`              |

**The multiply variant is preferred.** GPU divide runs ~10–20×
slower than multiply per element. Callers pre-compute `rcp_smooth
= 1.0 / smooth_factor` once per model and then use multiply-by-
reciprocal forever after.

### Generalizable lesson

When a per-element operation contains a reciprocal-expressible
divide by a value that doesn't change across many calls, hoist the
reciprocal to per-model setup and use multiply in the hot path.
Appears in many SIMD patterns (norm layers, scale-apply dequant,
per-group temperature scaling, etc.).

---

## Typical nunchaku integration

Per-model setup:

```python
packed_u4, scales_f16 = svdq.prepare_onednn_weights(packed, wscales)
rcp_smooth = (1.0 / smooth_factor).to(torch.float16)
```

Per-call:

```python
act_bf16 = ...                                                 # from previous layer
act_f16  = svdq.fused_smooth_mul_convert(act_bf16, rcp_smooth)  # ESIMD fused
out_f16  = svdq.onednn_int4_gemm_preconverted(act_f16, packed_u4, scales_f16)
svdq.fused_convert_add(dst_bf16, out_f16, residual_bf16)        # ESIMD fused, optional
```

No per-call `packed ^ 0x88`, no per-call scale dtype conversion, no
per-call divide.

---

## Constraints / gotchas

- `group_size == 64` is hardcoded. Other group sizes need a
  different scale-broadcast pattern and a separate kernel.
- `packed` must be contiguous uint8. Non-contiguous → rejected.
- `signed=True` for `unpack_svdq_int4` gives `[-8, 7]`;
  `signed=False` gives `[0, 15]`. Default is signed (nunchaku
  convention).
- `fused_convert_add` supports slicing from result (`Mo ≤ Mr,
  No ≤ Nr`), letting the caller fold a crop into the add.

---

## Related skills

| Skill                         | When                                                    |
|-------------------------------|---------------------------------------------------------|
| `omni-xpu-kernel-overview`    | Package context                                         |
| `omni-onednn-fp8-linear`      | Sibling oneDNN path — same primitive-caching pattern    |
| `omni-debug-logging`          | `OMNI_XPU_DEBUG=svdq` (if implemented)                  |
