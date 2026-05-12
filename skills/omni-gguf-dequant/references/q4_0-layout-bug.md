# Q4_0 sequential-vs-interleaved layout confusion

A case study of the most common correctness-confusion mode for
GGUF dequant kernels: two plausible output layouts, chosen
differently at the kernel site and the reference site, resulting
in tests that fail even though the kernel is correct.

This is a methodology doc, not a bug tracker. The fix is two
lines; the lesson is organizational.

---

## The shape of the failure

A GGUF Q4_0 dequant kernel passes a hand-sanity-check at one site
and **fails its own correctness test** with ~88% of elements
mismatching. Output magnitudes look right; the pattern is
scrambled.

Typical triage misfires:

- "Must be an ESIMD alignment bug" — no; kernel output is
  consistent across runs.
- "Must be a dtype bug" — no; Q8_0 and Q4_K/Q6_K pass their
  correctness tests on the same commit.
- "Must be a scale-extraction bug" — no; pulling the first few
  elements shows the right magnitudes in the right rough
  positions, just wrong order.

The actual cause: the kernel emits **sequential** layout while the
test reference emits **interleaved** (or vice versa). Both are
valid GGUF layouts; llama.cpp's `dequantize_row_q4_0` uses
interleaved, ESIMD block-load efficiency favors sequential, and
the two were chosen independently.

---

## Bisect recipe: kernel vs reference

Run the kernel and **both** plausible reference layouts side by
side:

```python
out       = gguf.dequantize_q4_0(t, torch.float16).cpu()
ref_seq   = reference_dequantize_q4_0(t, sequential=True).cpu()
ref_intr  = reference_dequantize_q4_0(t, sequential=False).cpu()
print('match seq  :', torch.allclose(out, ref_seq))
print('match intr :', torch.allclose(out, ref_intr))
```

If one layout matches exactly and the other has ~88% mismatch: the
kernel is fine, the test is comparing against the wrong reference.

This bisect takes five minutes and rules out the entire class of
"is the kernel broken" hypotheses.

---

## Why sequential wins on Intel GPU

ESIMD block loads are most efficient when 16 adjacent SIMD lanes
consume 16 **adjacent bytes** from one block:

- `packed & 0x0F` across 16 bytes → 16 low nibbles in one
  `SIMD<uint8, 16>` register.
- High nibbles: shift-and-mask on the same 16 bytes, no new load.

Producing interleaved output from this intermediate requires a
stride-2 scatter or cross-lane shuffle — extra ALU work that
buys nothing downstream (consumers treat the block as linear
anyway).

**Sequential is the natural layout for ESIMD on this problem.**
llama.cpp chose interleaved because their CPU implementation does
byte-by-byte processing where interleaved output is natural — a
reasonable choice for their hardware, a bad fit for ours.

---

## Fix: two-line edit plus a layout contract

Fix the test reference to match the kernel:

```python
# In the correctness test
reference = reference_dequantize_q4_0(q4_0_data, sequential=True)
```

Rewrite the bench reference to emit sequential too
(`torch.cat([low, high], dim=1)` instead of
`torch.stack([low, high], dim=2).view(...)`).

**Then add the layout contract as a persistent comment** at both
sites:

```cpp
// CONTRACT: output layout is [0..15] = low_nibbles,
//           [16..31] = high_nibbles. Downstream callers expecting
//           llama.cpp's interleaved layout must reshape.
```

---

## The organizational lesson

When a kernel has two plausible output layouts:

1. **Decide up front**, before writing the reference implementation.
2. **Document the choice in source**, at both the kernel site and
   the test/reference site.
3. **Include a brief rationale** (ESIMD block-load efficiency, in
   this case).

Doing this during the initial kernel review takes seconds. Not
doing it costs a day of "is the kernel broken" debugging the
first time someone unfamiliar with the codebase touches the
tests.

Generalizes beyond GGUF: the same rule applies to any kernel with
a layout choice (row-major vs col-major outputs, VNNI vs flat,
grouped vs ungrouped scales). Make the contract explicit.

---

## Related

- `omni-gguf-dequant/SKILL.md` — where the sequential-layout
  rationale is summarized.
- `omni-kernel-benchmarking` — cache-bust for memory-bound dequant
  benches (watch for L2-hit-inflated "GB/s").
