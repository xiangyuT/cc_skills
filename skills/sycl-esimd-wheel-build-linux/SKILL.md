---
name: sycl-esimd-wheel-build-linux
description: >
  How to build a hybrid host-extension + AOT-ESIMD-sidecar Python package on
  Linux with Intel oneAPI (icpx). Covers the two-compilation-profile pattern
  (host-compile `_C.so` + AOT-compile `lgrf_sdp.so` with doubleGRF), the
  single OMNI_XPU_DEVICE environment knob that picks the AOT target, the
  silent-JIT-fallback trap when the AOT target mismatches the actual GPU,
  editable-install rebuild pitfalls, and diagnostic recipes for typical
  icpx / oneDNN / PyTorch-XPU setup failures. Methodology only — no
  build-flag lists meant to be copy-pasted.
  Trigger for: pip install -e, setup.py build_ext, OMNI_XPU_DEVICE, AOT JIT
  fallback, -fsycl-esimd-force-stateless-mem, -options -doubleGRF, editable
  install, sidecar library build, icpx 2025.x.
---

# sycl-esimd-wheel-build-linux — two-profile build methodology

This skill describes the **build pattern** used to ship a hybrid Python
extension where most of the code compiles host-side (JIT at first launch)
but one ESIMD kernel needs AOT compilation with `-options -doubleGRF`.
Applies to `omni_xpu_kernel`, and reusable for any ESIMD-heavy extension.

---

## The two compilation profiles

The package ships two shared libraries from the same `setup.py`:

1. **Main extension (`_C.so`)** — all the pybind11 bindings and the
   non-ESIMD kernels. Host-compiled (no `-fsycl-targets=spir64_gen`),
   JIT-compiles the SYCL kernels at first-launch on the actual device.
   Compiles in seconds regardless of the target GPU.

2. **ESIMD sidecar (`lgrf_sdp.so`)** — only the Flash Attention ESIMD
   kernel (and any other kernel that requires doubleGRF). AOT-compiled
   via `-fsycl-targets=spir64_gen -Xs "-device <target> -options -doubleGRF"`.

The host extension **does not link against** the sidecar. Instead, at
first SDP call it `dlopen`s the sidecar (or `LoadLibrary` on Windows)
and grabs a function-pointer table via `dlsym`. See
`omni-sdp-flash-attention/references/dispatch-and-sidecar.md` for the
full pattern.

`setup.py`'s custom `ICPXBuildExt` inspects the extension name and picks
one of two flag sets. The discriminator is just a string compare
(`ext.name.endswith("lgrf_sdp")`).

---

## Why split — a short re-statement

`-options -doubleGRF` changes register allocation from 128 → 256 regs
per thread. It is **mandatory for the SDP kernel** (holds a large Q
tile + softmax scratch + DPAS accumulators) but **hurts everything
else** in the package because lower thread concurrency penalizes the
memory-bound norm / GGUF / rotary kernels and adds no benefit to the
oneDNN primitives.

Therefore doubleGRF must scope to the SDP kernel only. Two `.so` files,
one compile flag set each, is the simplest way to achieve that on Intel
GPU (no finer-grained `__attribute__` for doubleGRF exists for ESIMD at
the function level).

---

## The `OMNI_XPU_DEVICE` knob — the single most dangerous variable

One env var picks the AOT target for the sidecar:

| Value   | GPU family                       | Example parts        |
|---------|----------------------------------|----------------------|
| `bmg`   | Xe2-HPG / Battlemage             | Arc B580, B770       |
| `pvc`   | Xe-HPC / Ponte Vecchio           | Data Center GPU Max  |
| `ptl-h` | Xe3 / Panther Lake-H             | PTL iGPU             |
| `lnl`   | Xe2-LPG / Lunar Lake             | Core Ultra 200V iGPU |

The trap: a mismatch **does not error**. oneAPI compiles the binary
for the wrong target, then at first kernel launch silently falls back
to **JIT recompilation** — which can take minutes for an ESIMD kernel.
An AOT-correct build takes seconds; an AOT-wrong build takes
*significantly* longer on first call.

**Diagnostic heuristic**: if the first SDP call takes more than ~10 s
on a warm machine, re-check `OMNI_XPU_DEVICE`.

---

## Editable-install rebuild trap

`pip install -e .` sometimes skips `build_ext` when it thinks the
`.so` is up to date — but doesn't check source mtime correctly across
the two-profile split. The symptom: source edit appears to do nothing
at runtime.

Force a full rebuild by deleting the compiled artifacts and the build
directory, then running `python setup.py build_ext --inplace` (plus the
right `OMNI_XPU_DEVICE`). Never trust the editable install to pick up
sidecar-only changes without this.

---

## Common failure modes

| Symptom                                        | Likely cause                                                        |
|------------------------------------------------|---------------------------------------------------------------------|
| `_C has no attribute '<module>'`               | Wrong branch — that branch never defined the submodule. Rebuild from the branch that does. |
| Build "succeeds" but behavior matches old code | Editable install skipped rebuild. Force rebuild as above.           |
| First SDP call takes minutes                   | `OMNI_XPU_DEVICE` mismatch. Rebuild with the right target.          |
| `lgrf_sdp.so not found`                        | Sidecar didn't build. Check `-fsycl-targets=spir64_gen` support in your icpx (≥ 2024.2 required). |
| `invalid argument '-fsycl-esimd-force-stateless-mem'` | icpx too old. Upgrade oneAPI to ≥ 2024.2.                     |
| `undefined reference to c10::xpu::XPUStream`   | PyTorch built without XPU. Reinstall with `--index-url https://download.pytorch.org/whl/xpu`. |
| In-container code doesn't match host git       | Container is bind-mounting a different sub-tree. Inspect with `docker inspect` and adjust. |

---

## Verification recipe

After a rebuild, sanity-check the binary before running any downstream
workflow:

1. Import the extension and list its submodules. Compare against the
   expected set for your branch. A missing submodule means you built
   from the wrong branch (or the rebuild was skipped).
2. Run a single call on a representative shape. Time it. If it takes
   > 10 s you likely have an AOT mismatch.
3. `OMNI_XPU_DEBUG=<module> <your script>` — confirm the module's
   cache-miss / first-use log line prints, and that `impl=jit:...`
   (not `impl=ocl:ref:...`).

The above is a 30-second check that catches almost every build mistake
before you waste time debugging benchmarks.

---

## Related skills

- `omni-xpu-kernel-overview` — why two `.so`s, branch matrix
- `omni-sdp-flash-attention/references/dispatch-and-sidecar.md` — the
  `dlopen` + function-pointer-table pattern itself (cross-platform)
- `omni-debug-logging` — verifying what the kernel actually did after build
