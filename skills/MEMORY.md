# Intel XPU kernel skills — index

Reusable **methodology** from the `omni_xpu_kernel` project (Intel
Xe2 / BMG / Arc B-series). All specific kernel code and
performance numbers were intentionally stripped on sync — what
remains is the *why* behind the decisions: design patterns,
pitfalls, decision criteria, and failure-mode ledgers.

Start with `omni-xpu-kernel-overview` to orient, then routing
below.

| Skill                          | Scope                                                               |
|--------------------------------|---------------------------------------------------------------------|
| `omni-xpu-kernel-overview`     | Package layout, six-module map, branch discipline, build flow       |
| `sycl-esimd-wheel-build-linux` | Two-profile icpx build, AOT target knob, editable-install traps     |
| `omni-sdp-flash-attention`     | Flash Attention design: prefetch distance, V-scaling, kv_pad        |
| `omni-onednn-fp8-linear`       | FP8 W8A16 design: set_scales_mask trap, shape guards, small-M gap   |
| `omni-gguf-dequant`            | GGUF dequant design: sequential vs interleaved layout contract      |
| `omni-norm-kernels`            | Norm / fused norm design: NB-ladder dispatch, L3 fusion trick       |
| `omni-rotary`                  | RoPE design: per-row seq_idx over expanded cos/sin caches           |
| `omni-svdq-w4a4`               | SVDQuant W4A4: u4 XOR trick, preconverted weights, multiply-by-rcp  |
| `omni-debug-logging`           | Zero-overhead-when-off debug logging pattern                        |
| `omni-kernel-benchmarking`     | Continuous-run TFLOPS protocol (NOT multi-sample+cooldown)          |

---

## Conventions

- **SKILL.md** is the contract — quick rules and entrypoints.
- **references/** holds deep-dive methodology (per-optimization
  root-cause analysis, failure-mode ledgers, hardware traps,
  bench methodology).
- Failed-experiment entries live in
  `<skill>/references/failed-experiments.md` when they exist.

## Quick routing

| "I want to ..."                                        | Go here                             |
|--------------------------------------------------------|-------------------------------------|
| Understand the package structure                       | `omni-xpu-kernel-overview`          |
| Set up a build env / fix build breaks                  | `sycl-esimd-wheel-build-linux`      |
| Tune / read SDP kernel design                          | `omni-sdp-flash-attention`          |
| Add a new GGUF format or resolve a layout mismatch     | `omni-gguf-dequant`                 |
| Understand FP8 shape-guard / impl fallback             | `omni-onednn-fp8-linear`            |
| Add a new fused norm variant                           | `omni-norm-kernels`                 |
| Work on RoPE                                           | `omni-rotary`                       |
| Work on nunchaku SVDQuant integration                  | `omni-svdq-w4a4`                    |
| Turn on diagnostic printouts                           | `omni-debug-logging`                |
| Measure kernel TFLOPS defensibly                       | `omni-kernel-benchmarking`          |

## Cross-skill patterns

Several patterns recur; they're documented in whichever skill
introduces them, then referenced elsewhere:

| Pattern                                                 | Primary skill                         |
|---------------------------------------------------------|---------------------------------------|
| Two-layer `.so` split (host + doubleGRF sidecar)        | `omni-sdp-flash-attention/references/dispatch-and-sidecar.md` |
| Compile-time `constexpr` config struct + target select  | `omni-sdp-flash-attention/references/config-template.md`      |
| Detect-once / cache / fast-path-fallback                | `omni-sdp-flash-attention/references/v-scaling-overflow.md`   |
| oneDNN primitive cache keyed by shape                   | `omni-onednn-fp8-linear/SKILL.md`     |
| Host-side pad for 2D block-load boundary                | `omni-sdp-flash-attention/references/kv-pad-hardware-trap.md` |
| Continuous-run (not multi-sample) measurement           | `omni-kernel-benchmarking/SKILL.md`   |
| Document-layout-contracts at both kernel and test site  | `omni-gguf-dequant/references/q4_0-layout-bug.md`             |
