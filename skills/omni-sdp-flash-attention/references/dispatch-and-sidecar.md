# Host-extension + AOT-ESIMD sidecar via dlopen

Architectural note on how a hybrid Python extension can confine
`-options -doubleGRF` to just one ESIMD kernel, without imposing it
on the rest of the extension. Generalizes to any project where one
kernel needs a compile-flag set that would hurt its neighbors.

---

## The problem

Intel icpx `-options -doubleGRF` changes register allocation (128 →
256 regs per thread, halves max concurrent threads). It is
**mandatory for one ESIMD kernel** (holds a big Q tile + softmax
scratch + DPAS accumulators) but **undesirable for everything else**:

- Lower thread concurrency hurts memory-bound kernels (norm / GGUF
  dequant / rotary).
- oneDNN primitives don't need doubleGRF.
- Other ESIMD kernels fit happily in 128 regs.

So `-doubleGRF` can't be a global build flag. It must scope to one
compilation unit only.

---

## The solution: two `.so` files

**Main extension (`_C.so`)** — host-compiled, JIT at first launch.
Contains all the non-doubleGRF code (bindings, dispatch, other
kernels). Compiles quickly; no `-fsycl-targets=spir64_gen`, no
`-doubleGRF`.

**Sidecar (`lgrf_sdp.so`)** — AOT-compiled for one target, with
`-fsycl-targets=spir64_gen -Xs "-device <target> -options -doubleGRF"`.
Contains only the one kernel (or kernel family) that needs doubleGRF.

Both are built by the same `setup.py` — a custom build-ext command
discriminates on extension name and picks a flag set.

The main extension **does not link against** the sidecar at build
time. It `dlopen`s it at first call.

---

## Runtime loading: dlopen + function-pointer table

Pattern:

1. Define a C function-pointer type matching the sidecar's exported
   signature (e.g. `void (*kernel_fn)(void* Q, void* K, ..., void*
   queue)`).
2. Hold a small struct of fn-pointers (one per exported kernel
   variant).
3. On first call, `std::call_once` → `dlopen` the sidecar,
   `dlsym` each entry into the struct.
4. Subsequent calls use the cached table — no repeated dlsym.

The `std::call_once` guarantees exactly one `dlopen` per process,
which matters for stream plumbing (all calls go through the same
PyTorch-owned SYCL queue).

Cross-platform:
- Linux: `dlopen` / `dlsym` / `dladdr` (to find the sidecar's path
  relative to the main extension module).
- Windows: `LoadLibrary` / `GetProcAddress` /
  `GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS, ...)`.

Wrap both behind a `#ifdef _WIN32` in one place; rest of the code
only sees the fn-pointer table.

---

## How `_C.so` finds `lgrf_sdp.so` at runtime

Both ship in the same package directory:

```
site-packages/<pkg>/
    _C.<pytag>.so
    lgrf_uni/
        lgrf_sdp.<pytag>.so
```

On Linux, `dladdr(&some_function_in_main_so, &info)` returns
`info.dli_fname` = the main extension's own `.so` path. The parent
directory is the package root; the sidecar is at a known subpath
from there.

On Windows, the equivalent is `GetModuleHandleExW` with the
`_FROM_ADDRESS` flag to get the current module's handle, then
`GetModuleFileNameW` for its path.

This keeps the sidecar location co-located with the main extension
without hard-coding install prefixes.

---

## Exported C ABI in the sidecar

The sidecar exports plain-C (unmangled) symbols so `dlsym` /
`GetProcAddress` finds them by name:

- Mark every entry `extern "C"` (no name mangling).
- Use a single header defining the function signature, shared between
  the sidecar (for compilation) and the main extension (for fn-pointer
  types).
- Handle Windows `dllexport` / `dllimport` via a macro that toggles
  based on whether a `-DBUILD_<SIDECAR>_LIB` define is set. On Linux
  with default visibility the macro can expand to nothing.

Keep the ABI surface minimal: fewer symbols = fewer chances of
breaking binary compatibility between builds.

---

## Why not Python-level dlopen

You could in principle ship the sidecar as a standalone Python
extension and import it separately. Three reasons to integrate at the
C++ layer instead:

1. **Stream plumbing**. The sidecar takes a `void* sycl_queue_ptr`;
   Python side already has `c10::xpu::getCurrentXPUStream().queue()`
   from PyTorch. Passing that via `void*` needs C++ glue anyway.
2. **Single `dlopen`**. `call_once` at the C++ layer is simpler than
   arranging Python-level import discipline.
3. **Graceful fallback**. If the sidecar fails to load (wrong AOT
   target, missing file), `_C.so` can fall back to Python SDPA
   without a Python-level exception bubbling up.

---

## When to use this pattern

Use this split when **any** of:

- One kernel family needs compile flags that measurably hurt other
  kernels in the same extension.
- You want AOT for one kernel (to avoid multi-minute JIT on first
  launch) but host-compile for the rest (to avoid bloating the
  build matrix).
- Different kernels need different AOT targets (rare, but possible
  for multi-GPU products).

Don't use it just to split large source files — that's what
translation units are for.

---

## Related

- `omni-xpu-kernel-overview` — the package-design context
- `sycl-esimd-wheel-build-linux` — the `setup.py` build-flag dispatch
- The sidecar's AOT target is picked by `OMNI_XPU_DEVICE` (see
  build skill).
