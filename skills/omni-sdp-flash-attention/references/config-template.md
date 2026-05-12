# Compile-time hardware-config struct pattern

Zero-overhead parameterization pattern for ESIMD kernels that target
multiple Intel GPU products with different sweet-spot tile sizes. The
pattern lives in `omni_xpu_kernel/lgrf_uni/sdp_config.h`; this note
describes the methodology so the pattern can be reused for other
ESIMD kernel families.

---

## The need

Same ESIMD kernel source targets several Xe2/Xe3 products. Optimal
`WG_SIZE`, tile dimensions, SLM budget, and prefetch counts differ
per product. We want **one source tree** that compiles into different
AOT binaries per target without `#ifdef` spaghetti.

---

## The pattern

1. Define a base config struct of `static constexpr` integer members:
   ```cpp
   struct KernelConfigBase {
       static constexpr int WG_SIZE   = 16;
       static constexpr int TILE_M    = 16;
       static constexpr int TILE_N    = 64;
       // ... and derived values
       static constexpr int SLM_BYTES = 2 * TILE_N * HEAD_DIM * 2;
   };
   ```

2. One derived struct per target. Inheritance lets a target override
   just the members that need to change; everything else flows through.
   ```cpp
   struct ConfigBMG   : KernelConfigBase {};
   struct ConfigPVC   : KernelConfigBase {
       static constexpr int TILE_N = 128;   // larger SLM allowed
   };
   ```

3. Compile-time dispatch via preprocessor:
   ```cpp
   #if defined(CFG_PVC)   using ActiveConfig = ConfigPVC;
   #elif defined(CFG_LNL) using ActiveConfig = ConfigLNL;
   #else                  using ActiveConfig = ConfigBMG;
   #endif
   ```

4. Kernel code references `ActiveConfig::WG_SIZE`, etc. — never raw
   numbers.

---

## Why it compiles to zero-overhead

Every member is `static constexpr` → the compiler folds the values
into immediate operands of the machine instructions. No loads, no
indirect jumps, no runtime branching.

Verify by A/B-comparing ISA for two configs whose values are
temporarily set identical: the generated machine code must be
bit-identical. If it is, the config layer is genuinely free. A
typical verification flow:

1. Compile variant A with `-fsycl-save-spirv -DCFG_A`.
2. Compile variant B with the same source, same values, but `-DCFG_B`.
3. `ocloc disasm` each SPIR-V blob for the same target GPU.
4. `diff -r` the disassembly trees — should be empty.

---

## Why `constexpr` struct over `#define`

1. **Scoped**: `KernelConfig::WG_SIZE` — no global macro pollution.
2. **Typed**: typos become compile errors instead of silent 0s from
   a missing `#define`.
3. **Composable**: derived structs can override selectively. `#define`
   requires `#undef` + `#define` dances and is order-sensitive.

Downside: every reference has to write `ActiveConfig::` prefix. Small
price for the type safety.

---

## Adding a new target

1. Add a new struct derived from the base, overriding just what
   differs on the new hardware.
2. Add a preprocessor branch in the `ActiveConfig` select ladder.
3. In the build system, pass the new `-DCFG_<NAME>` macro when the
   user selects the new target via env var / CLI.
4. Re-benchmark, tune parameters, check for register spill, iterate.

---

## When *not* to use this pattern

- You only target one GPU family. The struct layer is overhead
  (cognitive, not runtime) for a degenerate case.
- The differences between targets are algorithmic, not parametric —
  e.g. one target needs a different kernel structure altogether.
  Then you have two kernels, not one parameterized kernel.
- Some parameters depend on runtime input (not target). Those belong
  in the dispatch layer (host code), not the compile-time config.

---

## Generalizable template

```cpp
// For any family of ESIMD kernels with hardware-dependent tiles:
struct MyKernelBase {
    static constexpr int TILE_M = 16;
    static constexpr int TILE_N = 16;
    static constexpr int TILE_K = 32;
    // ...
};
struct MyKernelBMG : MyKernelBase {};
struct MyKernelPVC : MyKernelBase {
    static constexpr int TILE_K = 64;   // larger L2 can take it
};

#if defined(MY_CONFIG_PVC)
using ActiveMyConfig = MyKernelPVC;
#else
using ActiveMyConfig = MyKernelBMG;
#endif
```

Pair with your target-selector env var in `setup.py` to automate
per-target builds.
