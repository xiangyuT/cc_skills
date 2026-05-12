# The K-prefetch-distance pattern

The single largest speedup in the omni_xpu_kernel SDP kernel came from
**moving** where the K-tile prefetch is issued — not from adding more
prefetches. This note captures the methodology so the pattern transfers
to other memory-bound hot loops on Intel GPU.

---

## TL;DR

- **Before**: `lsc_prefetch_2d` fired a handful of instructions before
  the K tile was re-consumed by the next QK GEMM. That gap is well
  under BMG's L2 miss latency, so the DPAS stalled waiting for K.
- **After**: prefetch fires right after V-load, with the entire
  softmax + compensation + V-consume window between prefetch-issue
  and K-use. Window is now well above L2 miss latency, miss fully
  hidden.
- **Mechanism**: distance, not count. More prefetches at the same
  (short) distance do not help.

---

## Why the naive placement is wrong

Prefetch hints don't magically move data — they start a load that
takes the normal L2 miss latency to return. If the hint is issued N
cycles before the consumer needs the data, and L2 miss is M cycles,
the effective wait is `max(0, M - N)` cycles of DPAS stall. Placing
the hint within tens of cycles of the use gives almost no cover;
placing it beyond the miss latency hides it entirely.

For BMG specifically, L2 miss latency is in the low hundreds of
cycles. Softmax + compensation + VNNI-pack + V pingpong together run
at hundreds of cycles — enough window to fully cover a miss if the
prefetch is issued at the start of that block.

---

## Why adding more prefetches doesn't help

The binding constraint is **the cycle gap between issue and
consumption**, not the number of in-flight loads. Related variants
that were tried and did not help:

- Adding extra `lsc_prefetch_2d` hints elsewhere: 0% gain, memory
  path wasn't oversubscribed.
- Increasing `PREFETCH_K_BLOCKS` 2 → 3: no gain, L2 queue pressure.
- Extra SLM load pipelining on V: 0% gain, V wasn't the bottleneck.

All three hold the gap constant while raising count. The gap was
always the real problem.

---

## Generalizable recipe

For any memory-bound-in-the-hot-loop kernel on Intel GPU:

1. Measure the actual L2 miss latency on your target GPU (BMG is
   different from PVC, which is different from LNL).
2. Estimate cycles between prefetch issue and consumption by summing
   the cycle cost of intervening instructions (easy to approximate
   from ISA — sum `send` / `mad` / `mul` latencies of the block
   between them).
3. If gap < miss latency, the prefetch is doing nothing. Move it
   earlier to the first independent work block that gives enough
   cover.
4. Don't add more prefetches at the same distance — you'll just
   queue-pressure L2 without hiding any stalls.

This generalizes: the same logic applies to GEMM K-loop prefetch,
GEMV weight prefetch, and any per-tile compute pipeline.

---

## When this pattern doesn't apply

- Compute-bound kernels (M × K × N large enough that DPAS density is
  the bottleneck, not memory). More prefetching won't help a
  compute-saturated kernel; look at DPAS scheduling instead.
- Kernels where intermediates are in SLM / register and never touch
  VRAM on the hot path.
- Workloads where the K tile fits in L2 across the whole iteration
  space — then the prefetch is moot after the first iter.

---

## Related

- `failed-experiments.md` — count-based prefetch variants that didn't
  help (all kept the distance constant).
- `omni-kernel-benchmarking` — measuring the delta rigorously so you
  can tell a real prefetch win from harness noise.
