---
name: omni-debug-logging
description: >
  Design pattern for unified, zero-overhead-when-off debug logging across a
  multi-module kernel package. Uses a single environment variable with
  module-name selectors, stderr-synchronous output, fixed-key message format
  for greppability, and a runtime check guarded by a cheap env-var read.
  Trigger for: OMNI_XPU_DEBUG, debug logging, diagnostic env var, per-module
  log selector, zero-overhead debug macro.
---

# omni-debug-logging — diagnostic logging pattern

A unified debug-logging mechanism for a multi-module kernel package,
disabled by default (zero runtime cost when off), opt-in per module
via an environment variable. The pattern generalizes to any native
library with several orthogonal debugging surfaces.

---

## Basic usage

```bash
# All modules
OMNI_XPU_DEBUG=1 python your_script.py

# Single module
OMNI_XPU_DEBUG=sdp python your_script.py

# Multiple (comma-separated, no spaces)
OMNI_XPU_DEBUG=sdp,fp8 python your_script.py
```

Output format:
```
[omni_xpu::sdp] call #0: V_max=4.9 threshold=256 needs_scaling=0 q=[1,4096,24,128]
[omni_xpu::fp8] cache MISS: impl=jit:gemm:any (M=4096 K=4096 N=12288 wtype=10)
```

Sent to stderr by default.

---

## Design principles

### 1. Single env var, module selectors

One env var governs the entire package. Selectors are comma-
separated module names (`sdp`, `fp8`, `norm`, `gguf`, `rotary`,
`svdq`), plus a wildcard `1` / empty. This is simpler for users
than per-module env vars and avoids coordinating multiple toggles
when debugging cross-module interactions.

### 2. Zero overhead when off

Debug checks are a fast, cached lookup of `OMNI_XPU_DEBUG` (parsed
once per process into a bitmask). The macro expands to:

```cpp
if (__builtin_expect(module_enabled(MODULE), 0)) {
    fprintf(stderr, "[omni_xpu::%s] " fmt "\n", MODULE, __VA_ARGS__);
}
```

With the `__builtin_expect` hint (or its compiler equivalent), the
branch predictor always assumes "off", so the runtime cost of
disabled logging is ~one load + one predicted-not-taken branch — no
string formatting, no system call.

### 3. Fixed keys, machine-greppable

Every log line has a fixed module prefix and key-value fields
separated by spaces:

```
[omni_xpu::fp8] cache MISS: impl=jit:gemm:any (M=4096 K=4096 N=12288 wtype=10)
                            ^^^^                ^^^^^^^^^ ^^^^^^^^ ^^^^^^^^ ^^^^^^^^^^
                            grep-friendly keys — stable across versions
```

This lets users grep / sed / count without parsing prose. Example
workflows:

- `grep 'impl=ref' log`: find slow-fallback cache misses.
- `grep 'needs_scaling=1' log | wc -l`: count V-scaling triggers.
- `grep 'cache MISS' log | awk '{print $5}' | sort -u`: unique
  shape keys that missed the cache.

Avoid prose-style "log looks like English" formats — they're
un-greppable.

### 4. stderr-synchronous

`fprintf(stderr, ...)` with implicit flush. Guarantees log lines
appear in order, don't interleave, and survive process crashes.

### 5. Opt-in log points, not noisy default

Log only **decisions** and **rare events** (cache miss, first use,
shape change, fallback taken). Not every kernel call. Users turn
on logging when investigating something; a flood of per-call spam
defeats the purpose.

---

## Per-module conventions

| Module     | What's logged                                                               |
|------------|-----------------------------------------------------------------------------|
| `sdp`      | V-scaling recheck decisions (at the recheck interval, not per call)         |
| `fp8`      | Cache hit/miss with `impl=` string and shape key                            |
| `norm`     | Per-call shape info (fused variants especially)                             |
| `gguf`     | Per-format element count and output shape                                   |
| `rotary`   | Per-call shape + dtype                                                      |
| `svdq`     | Cache behavior (when implemented)                                           |

Most useful when:
- **SDP**: `needs_scaling` unexpectedly flipping to 1 (→ fast-path
  disabled, check the model).
- **FP8**: `impl=ocl:ref:any` instead of `impl=jit:gemm:any`
  (→ slow fallback, investigate).

---

## Generalizable template

For any native library with multiple debug surfaces:

1. Parse `<LIB>_DEBUG` once at process start → bitmask.
2. One macro, branch-predictor-hinted, module-aware.
3. Fixed keys, stderr-synchronous.
4. Document each module's log vocabulary at the site where the
   module lives.

Avoid:

- Multiple env vars for different subsystems (users forget them).
- Always-on debug build with "just comment out the printfs"
  (prevents users from turning it on).
- Pretty-printed output with ANSI colors — breaks pipes and
  machine parsing.

---

## When not to enable

Debug logging is stderr-synchronous. Enabling it during a tight
inner loop (e.g. training with 10k SDP calls per epoch) adds
measurable overhead — the stderr write itself blocks. Keep
disabled in production; the zero-overhead-when-off design lets
this be the default forever.

For a single inference pass or a debug session, it's fine.

---

## Related skills

- `omni-xpu-kernel-overview` — where the debug pattern fits in the
  package architecture
- Individual module skills — each documents its own log vocabulary
