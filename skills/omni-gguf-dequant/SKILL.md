---
name: omni-gguf-dequant
description: >
  Design methodology for the omni_xpu_kernel GGUF weight dequantization
  path (Q4_0 / Q8_0 / Q4_K / Q6_K) on Intel Xe2. Covers the output-layout
  contract (sequential vs interleaved — the most common source of
  correctness confusion), the ESIMD block-access rationale behind
  choosing sequential layout, the `dequantize_batch` kernel-launch-
  amortization pattern, and the template for adding a new GGUF format.
  No kernel source.
  Trigger for: dequantize_q4_0, dequantize_q8_0, dequantize_q4_k,
  dequantize_q6_k, dequantize_batch, GGUF layout, ComfyUI-GGUF
  interleaved vs sequential, nibble unpacking on XPU.
---

# omni-gguf-dequant — GGUF dequantization design

ESIMD dequantization for four GGUF block formats, layout-compatible
with ComfyUI-GGUF for drop-in replacement. The skill documents the
*why* of the design — layout contract, batching rationale, format
boundaries. Kernel source lives in the upstream repo.

---

## Supported formats at a glance

| Format | Block bytes | Elements | Scale bytes | Note                                              |
|--------|-------------|----------|-------------|---------------------------------------------------|
| Q4_0   | 18          | 32       | 2 (fp16)    | 16 bytes of packed 4-bit nibbles                  |
| Q8_0   | 34          | 32       | 2 (fp16)    | 32 bytes of int8 values                           |
| Q4_K   | 144         | 256      | 2+2+12      | 128 bytes of nibbles + 12 bytes of sub-scales     |
| Q6_K   | 210         | 256      | 2           | 128+64+16 bytes                                   |

Block sizes and element counts are dictated by the GGUF spec — not
tunable here.

---

## The sequential-vs-interleaved layout contract

**This is the single most common source of correctness confusion in
the codebase.** Q4_0 packs 32 nibbles in 16 bytes, where each byte
holds low and high nibbles. After dequant, those 32 values can be
stored two ways:

- **Interleaved** (llama.cpp's `dequantize_row_q4_0` convention):
  `out[0], out[1] = low[0], high[0]; out[2], out[3] = low[1], high[1]; ...`
- **Sequential** (what our ESIMD kernel produces):
  `out[0..15] = low[0..15]; out[16..31] = high[0..15]`

**The kernel output is sequential.** This is documented in a source
comment — and must be — because both conventions are plausible and
the compiler won't catch a layout mismatch, only downstream test
failures will.

### Why sequential

ESIMD block loads are most efficient when 16 adjacent SIMD lanes
consume 16 **adjacent bytes** from one block. `packed & 0x0F` across
16 bytes → 16 low nibbles in one `SIMD<uint8, 16>`. The high half
comes from the same bytes' upper nibble: a shift-and-mask, not a
separate load.

Producing interleaved output from this intermediate would require a
stride-2 scatter or register shuffling — extra ALU for no downstream
benefit (ComfyUI-GGUF reads the whole block as a linear tensor
anyway; interleave is just a copy for humans).

If a caller truly needs interleaved, they should do the shuffle
themselves — cheap, given dequant is memory-bound.

### Lesson: document layout contracts at both sites

When a kernel has two plausible output layouts, **document the
choice at both the kernel source site and the test/reference site**.
A line like:

```cpp
// CONTRACT: output layout is [0..15]=low_nibbles, [16..31]=high_nibbles.
// Downstream callers expecting llama.cpp interleave must reshape.
```

…prevents exactly the "88% mismatch in tests, kernel is actually
correct" bug class. See `references/q4_0-layout-bug.md` for the
diagnostic trace from the real occurrence.

---

## `dequantize_batch` — kernel-launch amortization

```python
outs = gguf.dequantize_batch(
    [t1, t2, t3, t4],
    ['q4_0', 'q4_0', 'q8_0', 'q4_k'],
    torch.float16,
)
```

Implementation pattern:
1. Group input tensors by format (`{q4_0: [t1, t2], q8_0: [t3], q4_k: [t4]}`).
2. For each group, concatenate the input tensors into one flat buffer.
3. Launch one ESIMD kernel per format group.
4. Split the output buffer back to match original shape/order.

Net: reduce from N submissions to K (= number of distinct formats)
submissions. Saves per-launch latency (typically microseconds each),
which matters when a model has many small quantized tensors.

Generalizes to any ESIMD kernel family with multiple formats /
shapes that can be concatenated along the "flat elements" axis.

---

## Adding a new GGUF format — template

1. Add block-size and element-count constants (dictated by the GGUF
   spec — don't invent new sizes).
2. Write the ESIMD kernel following ComfyUI-GGUF's layout (inspect
   their `dequantize_row_<format>` as reference).
3. Register the Python binding.
4. Extend `dequantize_batch` dispatch.
5. Write correctness tests that mirror llama.cpp's reference — but
   **decide sequential vs interleaved up-front** and document the
   choice at both kernel and test site.

---

## Cache-bust during benchmarking

Dequant is memory-bound. Running the same input tensor repeatedly
lets L2 cache the data after iter 1, inflating apparent bandwidth.

For publish-grade numbers, rotate through multiple input buffers
(aggregate size > L2) when the per-call payload is smaller than L2.
When payload already exceeds L2, rotation is harmless but provides
no additional defense.

See `omni-kernel-benchmarking` for the cache-bust methodology.

---

## Related skills

| Skill                         | When                                        |
|-------------------------------|---------------------------------------------|
| `omni-xpu-kernel-overview`    | Package context, branch matrix              |
| `omni-debug-logging`          | `OMNI_XPU_DEBUG=gguf` per-call shape logs   |
| `omni-kernel-benchmarking`    | Cache-bust methodology for memory-bound     |

## References

- `references/q4_0-layout-bug.md` — diagnostic trace of a
  sequential-vs-interleaved layout confusion, plus the document-
  layout-contracts lesson.
