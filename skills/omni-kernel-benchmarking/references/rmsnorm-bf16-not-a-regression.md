# Case study — how a bad protocol invents a fake 3× slowdown

A worked example of how the wrong benchmarking protocol can invent
a regression that doesn't exist. Preserved as a template for
investigating "X is suspiciously much slower than Y" reports before
blaming the kernel.

The specifics are bf16 RMSNorm on a given shape, but the
methodology transfers to any "X× faster/slower" claim.

---

## The initial (wrong) report

Using a multi-sample-with-cooldown bench protocol on one norm
shape, bf16 appears ~3× slower than fp16, with tight fp16 CI and
loose bf16 CI. Looks like a real regression or a bf16 fallback
path.

It is **neither**.

---

## Investigation steps

### Step 1 — look for dispatch fallback

Read the dispatch code. Confirm both dtypes go through the same
switch, differing only in template parameter `IT`. No dtype
branching. No fallback. Rules out the "bf16 hit a ref path"
hypothesis.

### Step 2 — grep the kernel for dtype branches

Search the kernel body for `if constexpr`, `std::is_same_v`,
`is_same<IT, ...>`. Confirm all branching is on compile-time
integer template parameters, never on `IT`. The kernel body is
pure `simd<IT, BS>` with `block_load<IT>` / `block_store<IT>` /
`slm_block_load<IT>` — no fp16-vs-bf16 logic path differs.

Rules out "bf16 has a different kernel that's slower".

### Step 3 — re-run with long cooldown and a separate measurement

5 trials, each 50 inner iters, **5 s cooldown between trials**:

- fp16: trial 0 cold, trials 1–4 at a steady plateau.
- bf16: trial 0 cold, trials 1–4 at the same steady plateau
  (within a few percent of fp16, bf16 slightly faster).

Reality: both dtypes converge to the same neighborhood. No 3×
slowdown. No regression.

### Step 4 — understand the original misreport

Dump the raw per-sample times from the original bench. Pattern:

- bf16 first few samples: **very fast**.
- bf16 later samples: **much slower**, settling at a plateau.
- bf16 median across all samples lands on the plateau.

bf16 **climbs** from low-time to high-time across samples — the
opposite of the usual "cold slow, warm fast" pattern. The
too-short cooldown didn't flush enough state to reset the warm-up
curve, but the couple-second gap between samples was enough to
partially cool the kernel. Each sample started a little cooler
and warmed toward the plateau within its 200 inner iters. The
median over 30 samples caught the plateau.

Meanwhile fp16 hits its plateau **immediately** on iter 1 and
stays flat across all samples at all cooldown settings — so fp16's
median matches its plateau exactly, while bf16's median matches
its own plateau, which happens to be several × the starting-point
value for that kernel.

The end-user reading of "46 µs fp16 vs 143 µs bf16" was born from
**too few warmup iters + too few timed iters** catching different
parts of each dtype's warm-up curve.

---

## Step 5 — the takeaway

- No kernel bug. fp16 and bf16 RMSNorm perform within a few
  percent of each other at steady state.
- **The bench's default cooldown is insufficient** for bf16
  RMSNorm's particular warm-up pattern, but sufficient for every
  other kernel in the suite (rotary, SDP, FP8, GGUF). The bf16
  RMSNorm path has a slow warm-up curve driven by something other
  than GPU clock (driver-side SLM preload suspected).
- For this specific shape, measure either with long cooldown
  (5 s) between samples **or** with 100+ warmup iterations before
  timed samples begin.

---

## What to change

- The harness's bench-runner should allow per-kernel warmup
  overrides, not a single global default.
- The norm-kernel SKILL should document the warm-up caveat so
  users don't invent regressions from default settings.

---

## Methodology rule

Next time you see "X× slower" in a bench report with **tight CI on
one side and loose CI on the other**, always check raw per-sample
times (or per-chunk times) for warmup patterns **before**
concluding the kernel is pathological.

- Tight CI on both sides with a big delta → real.
- Loose CI on one side → warmup pattern; investigate samples_ms /
  per-chunk times before blaming the kernel.
- Both sides loose → the bench protocol is too noisy; tighten it
  before drawing any conclusion.

This investigation took an hour. Blaming the kernel and re-writing
it would have taken days and ended in the same place.

---

## Related

- `omni-kernel-benchmarking/SKILL.md` — where this caveat is
  distilled into "warmup ≤ 20 iters on a < 5 ms kernel → ask for
  ≥ 1000 iters".
- `omni-norm-kernels/SKILL.md` — "bf16 warm-up curve" section.
