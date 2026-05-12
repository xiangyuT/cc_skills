---
name: omni-xpu-kernel-overview
description: >
  Top-level map of the omni_xpu_kernel package — a pip-installable bundle of
  ESIMD / SYCL / oneDNN kernels for Intel Xe2 (BMG / Arc B-series), shared by
  ComfyUI, SGLang Diffusion, and Xinference under llm-scaler-omni. This skill
  documents the *design of the package itself*: what modules exist, how the
  two-layer build splits host code from doubleGRF ESIMD code, the AOT-target
  knob, the branch discipline, and how to route to deeper skills. No kernel
  source, no TFLOPS numbers — purely methodology and structure.
  Trigger for: omni_xpu_kernel, llm-scaler-omni, how is this package organized,
  what modules does it ship, how do I build it, what's doubleGRF for, what's
  the sidecar pattern.
---

# omni_xpu_kernel — package-design overview

The omni_xpu_kernel package bundles a family of Intel Xe2 kernels behind a
single `pip install`. Consumers are diffusion runtimes (ComfyUI / SGLang
Diffusion / Xinference), so the shapes exercised are prefill-style
(M ≥ 1000s), never single-token decode.

This skill covers only the *meta-design*. Per-kernel rationale lives in
the sibling skills below.

---

## Six submodules

| Module    | Purpose                                                               | Skill                      |
|-----------|-----------------------------------------------------------------------|----------------------------|
| `sdp`     | ESIMD Flash Attention, HD={64,128}, fp16/bf16, B==1                   | `omni-sdp-flash-attention` |
| `linear`  | FP8 W8A16 GEMM via oneDNN (E4M3 and E5M2)                             | `omni-onednn-fp8-linear`   |
| `gguf`    | GGUF dequant (Q4_0 / Q8_0 / Q4_K / Q6_K), ComfyUI-GGUF layout         | `omni-gguf-dequant`        |
| `norm`    | RMSNorm / LayerNorm / fused_add_rms / fused_rms_norm_linear           | `omni-norm-kernels`        |
| `svdq`    | SVDQuant W4A4 (nunchaku): INT4 unpack, oneDNN INT4 GEMM, post-fusion  | `omni-svdq-w4a4`           |
| `rotary`  | Fused bf16↔f32 + RoPE, HD={64,128}                                    | `omni-rotary`              |

Each submodule has its own binding, its own primitive-cache (where
applicable), and its own debug-logging channel (see `omni-debug-logging`).

---

## Two-layer build architecture

The package ships **two** shared libraries per Python extension:

```
site-packages/omni_xpu_kernel/
├── _C.<pytag>.so            ← main extension (host-compiled, no doubleGRF)
└── lgrf_uni/
    └── lgrf_sdp.<pytag>.so  ← AOT ESIMD sidecar (doubleGRF only here)
```

Why split? `-options -doubleGRF` (256 regs × 64 B per thread) is mandatory
for the Flash Attention kernel (which holds a big Q tile + softmax
scratch + DPAS accumulators) but **hurts everything else** — it halves
thread concurrency, which penalizes memory-bound norm / GGUF / rotary.

Rather than a global compile flag, the doubleGRF scope is confined to a
single sidecar `.so` that's `dlopen`-ed at first call. The main `_C.so`
is host-compiled without doubleGRF and contains all five non-SDP modules.

See `omni-sdp-flash-attention/references/dispatch-and-sidecar.md` for
the full `dlopen` + function-pointer-table pattern, including how the
sidecar is located relative to `_C.so` (`dladdr` on Linux,
`GetModuleHandleExW` on Windows).

---

## AOT target knob: one env var controls everything

```bash
OMNI_XPU_DEVICE=bmg    # Arc B580/B770 (default)
OMNI_XPU_DEVICE=pvc    # Data Center GPU Max
OMNI_XPU_DEVICE=ptl-h  # Panther Lake (Xe3)
OMNI_XPU_DEVICE=lnl    # Lunar Lake
```

This single variable dispatches the right `-fsycl-targets=spir64_gen
-Xs "-device <target>"` combination inside `setup.py`. The trap here is
severe and silent — wrong target compiles cleanly but falls back to
**JIT at first kernel launch** (minutes on BMG with a `-device pvc`
binary). See `sycl-esimd-wheel-build-linux` skill for the full
diagnostic.

**Rule**: if first kernel call takes more than ~10 s, you likely
built with the wrong `OMNI_XPU_DEVICE`.

---

## Branch discipline

Not all branches ship all submodules. A typical pitfall: someone pins
their workflow to a feature branch and later wonders why a submodule
isn't exposed. The mitigation is to introspect the binary itself:

```python
import omni_xpu_kernel._C as m
# Check which submodules are actually bound in this build
print(sorted(a for a in dir(m) if not a.startswith("_")))
```

If `linear` / `svdq` / etc. is missing, that build was made from a branch
that didn't define it, not a broken install. Do not attempt to work
around with monkeypatching — rebuild from the correct branch.

---

## Debug surface

Every module opts into a single unified logger:

```bash
OMNI_XPU_DEBUG=1              # all modules
OMNI_XPU_DEBUG=sdp,fp8        # selective
OMNI_XPU_DEBUG=norm           # single module
```

Zero runtime cost when unset. Output format is `[omni_xpu::<module>]
<message>`, stderr-synchronous, machine-greppable. See
`omni-debug-logging`.

---

## Design patterns reused across submodules

| Pattern                                   | Appears in                                  |
|-------------------------------------------|---------------------------------------------|
| Primitive cache keyed by (device, dtype, M, K, N, bias) | `linear`, `svdq`, `norm.fused_rms_norm_linear` |
| Compile-time `constexpr` config struct + `using ActiveConfig = ...` | `sdp` |
| Detect-once + cache + fast-path/safe-path | `sdp` V-scaling                             |
| Host-side padding for hardware 2D-block-load boundary | `sdp` (kv_pad)              |
| Host dispatch ladder by runtime-picked template instantiation | `norm` (nb dispatch), `sdp` (hd64 vs hd128, fp16 vs bf16) |

Each is documented under the relevant skill.

---

## Related skills

| Skill                             | When                                                                 |
|-----------------------------------|----------------------------------------------------------------------|
| `omni-sdp-flash-attention`        | Writing / tuning SDP; K-prefetch distance; V-scaling; kv_pad         |
| `omni-onednn-fp8-linear`          | FP8 shapes, set_scales_mask trap, E4M3 vs E5M2, small-M decode gap   |
| `omni-gguf-dequant`               | GGUF block layouts, sequential-vs-interleaved output contract        |
| `omni-norm-kernels`               | RMSNorm / LayerNorm / fused_rms_norm_linear; L3-cache trick          |
| `omni-rotary`                     | RoPE design: per-row seq_idx instead of pre-expanded cos/sin         |
| `omni-svdq-w4a4`                  | nunchaku SVDQuant: u4 XOR trick, post-op fusion primitives           |
| `sycl-esimd-wheel-build-linux`    | Build flags, doubleGRF sidecar, AOT knob, editable-install rebuild   |
| `omni-debug-logging`              | OMNI_XPU_DEBUG selectors and log format                              |
| `omni-kernel-benchmarking`        | Rigorous TFLOPS measurement (NOT multi-sample+cooldown)              |
