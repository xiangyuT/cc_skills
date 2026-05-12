# BMG ESIMD run-to-run variance: fp16 vs bf16

A finding about **run-to-run variance** of ESIMD kernels on BMG
(Arc B-series): same shape, same kernel template, fp16 vs bf16 I/O
only — bf16 consistently shows higher variance across samples than
fp16.

This matters for *reporting* (how big a delta can you reliably
detect?) and for *diagnosing* (don't interpret bf16 noise as a
regression).

---

## The pattern (qualitative)

Under the rigorous protocol (single continuous warmup + single
continuous timed run, internally chunked for stats):

- **fp16 rel stdev** settles to small values (typically sub-1%).
- **bf16 rel stdev** settles to noticeably larger values (typically
  2–3%), on the **same shape and same kernel template**.

Both dtypes have clean drift (near zero). Both are in steady state.
The difference is spread of per-chunk times around the mean.

---

## What this means for reporting

### Detection threshold

The minimum detectable delta (for "this change is a real speedup,
not noise") scales with stdev. If bf16 stdev is roughly ~3× fp16
stdev, then:

- An fp16 claim of 2% speedup may be detectable (CI excludes 1.0).
- A bf16 claim of 2% speedup may not — you need ~5% delta to claim
  detection at the same confidence.

Account for this when designing A/B tests: either increase sample
count for bf16 (variance shrinks as `1/sqrt(n)`) or set a higher
delta threshold before calling something a "real" improvement.

### Don't invent regressions

If bf16 ms on this commit is ~3% higher than bf16 ms on the
previous commit but the CIs overlap, that's **not a regression**;
it's expected variance. The same comparison on fp16 at the same
delta *would* be a regression.

---

## Hypotheses for the source of bf16 noise

Not separately confirmed, ordered by likelihood:

1. **BF16 ALU scheduling**: bf16 → fp32 upconvert for accumulator
   adds variable XVE pressure; any scheduling jitter shows up more.
2. **Cross-SG SLM traffic**: bf16 kernel's V-load path uses a
   different cooperative SLM scatter pattern; more sensitive to
   other-SG timing.
3. **Memory subsystem sensitivity**: bf16 I/O is half the bytes of
   fp32 but double fp16's quirks with memory subsystem timing at
   long sequences.

The right next step to pin this down would be ISA-level timing of
the bf16 vs fp16 variants on matched shapes, which is out of scope
for most measurement work.

---

## "Big delta between runs" — almost always different binaries

A common failure mode: two different numbers reported on the same
shape on consecutive days, with a delta much larger than observed
variance would permit. In these cases the cause is almost always
**different binaries**, not variance:

- Different branch
- Different build flags (e.g. `OMNI_XPU_DEVICE` mismatch silently
  JIT-compiling)
- Different driver / oneDNN / oneAPI version

**Rule**: any claim of regression or improvement larger than
observed variance requires **re-running both sides with the same
binary**, not comparing numbers pulled from old logs or memory.

---

## Methodology note

A thermal-throttling check belongs in every rigorous run. Read
`xpu-smi dump -d 0 -m 0` (when available) during the timed run and
confirm the device frequency is steady. If it drops mid-run, the
measurement is contaminated and should be re-done on a cooler
machine or with a longer pre_sleep.

---

## Related

- `omni-kernel-benchmarking/SKILL.md` — where this variance
  observation is summarized as a reporting threshold.
- `cache-bust-evidence.md` — a second kind of "measurement looks
  different from measurement" story, with a different root cause.
