# Intel XPU kernel skills (methodology-only)

These skills distill reusable **methodology and design rationale** from
building ESIMD / SYCL / oneDNN kernels on Intel Xe2 (BMG / Arc B-series)
for the `omni_xpu_kernel` package (diffusion runtime backend shared by
ComfyUI, SGLang Diffusion, Xinference).

**Intentionally excluded from this sync**: kernel source, benchmark
harness code, and specific performance numbers (TFLOPS / GB/s / timings).
Those live in the upstream repo alongside the kernels they describe.
What remains here is the *why* — patterns, pitfalls, and decision
criteria that transfer to any Intel-GPU kernel project.

| Skill                          | Scope                                                              |
| ------------------------------ | ------------------------------------------------------------------ |
| omni-xpu-kernel-overview       | Package layout pattern, branch-matrix discipline, build flow       |
| sycl-esimd-wheel-build-linux   | icpx + oneAPI build, AOT target knob, editable-install traps       |
| omni-sdp-flash-attention       | SDP ESIMD design rationale: prefetch distance, V-scaling, kv_pad   |
| omni-gguf-dequant              | GGUF dequant design: sequential vs interleaved output contract     |
| omni-onednn-fp8-linear         | oneDNN W8A16 FP8 shape guards, set_scales_mask trap, small-M gap   |
| omni-norm-kernels              | Fused norm design; bf16 warm-up caveat for benchmarking            |
| omni-rotary                    | Per-row seq_idx over expanded cos/sin — why & when                 |
| omni-svdq-w4a4                 | SVDQuant W4A4 pipeline, u4 XOR trick, post-op fusion               |
| omni-debug-logging             | Debug-log module selectors, zero-overhead-when-off design          |
| omni-kernel-benchmarking       | Continuous-run TFLOPS protocol (NOT multi-sample+cooldown)         |

Pattern index (common to several skills):
- **Detect-once-cache-fast-path-fallback** — SDP V-scaling (`omni-sdp-flash-attention`)
- **Primitive cache keyed by shape** — oneDNN FP8 / SVDQuant (`omni-onednn-fp8-linear`, `omni-svdq-w4a4`)
- **Compile-time config struct + template select** — SDP `sdp_config.h` pattern (`omni-sdp-flash-attention/references/config-template.md`)
- **Two-layer `.so` split** — host extension + AOT ESIMD sidecar via dlopen (`omni-sdp-flash-attention/references/dispatch-and-sidecar.md`)
- **Host-side pad for 2D block load boundary** — BMG hardware trap (`omni-sdp-flash-attention/references/kv-pad-hardware-trap.md`)
- **Long-warmup + continuous-timed measurement** — never multi-sample+cooldown (`omni-kernel-benchmarking`)

## Import into a project

Via `/import-skills` with this registry entry:

```yaml
- name: omni-xpu-kernel-skills
  repo: https://github.com/xiangyuT/cc_skills.git
  branch: main
  type: skills
  path: skills
  includes:
    - "omni-*"
    - "sycl-*"
```

Or copy the relevant subdir directly into your repo's `.claude/skills/`.
