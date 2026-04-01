# D037: Math Enhancements — Builtin Extensions + Utility Module

**Status:** Accepted
**Depends-on:** D035 (stdlib pattern)

## Decision

Two-tier math enhancement:

1. **Extend Math builtins** (compiler changes): Add 13 new functions to the built-in `Math` class — `tan`, `asin`, `acos`, `atan`, `atan2`, `exp`, `log10`, `log2`, `trunc`, `sign`, `hypot`, `cbrt`, `fmod`.

2. **Create `lib/math.ss`** (pure SS stdlib): Higher-level utility module `MathUtil` with `clamp`, `lerp`, `inverseLerp`, `mapRange`, `toDegrees`, `toRadians`, `approxEqual`, integer utilities (`isEven`, `isOdd`, `gcd`, `lcm`, `isPowerOfTwo`), and constants (`PI()`, `E()`, `TAU()`, `EPSILON()`).

## Reasoning

The original Math class had 12 functions (sqrt, abs, floor, ceil, round, pow, log, sin, cos, min, max, random). Missing trig/exp/log functions forced users to implement workarounds. The two-tier approach separates concerns: runtime functions wrap libc math for performance, while the stdlib module provides composable pure-SS utilities.

Constants are exposed as zero-arg methods (`MathUtil.PI()`) rather than properties (`Math.PI`) because the current compiler doesn't support static property access on built-in classes — only method dispatch via `genStaticMethodCall()`.

## Interfaces

```
// New Math builtins (all double → double, except 2-arg variants)
Math.tan(x)              Math.asin(x)           Math.acos(x)
Math.atan(x)             Math.atan2(y, x)       Math.exp(x)
Math.log10(x)            Math.log2(x)           Math.trunc(x)
Math.sign(x)             Math.hypot(x, y)       Math.cbrt(x)
Math.fmod(x, y)

// MathUtil stdlib (import { MathUtil } from "@/lib/math")
MathUtil.PI()            MathUtil.E()           MathUtil.TAU()
MathUtil.clamp(v, lo, hi)                       MathUtil.lerp(a, b, t)
MathUtil.inverseLerp(a, b, v)                   MathUtil.mapRange(v, inMin, inMax, outMin, outMax)
MathUtil.toDegrees(rad)  MathUtil.toRadians(deg)
MathUtil.approxEqual(a, b, eps)
MathUtil.isEven(n)       MathUtil.isOdd(n)      MathUtil.gcd(a, b)
MathUtil.lcm(a, b)       MathUtil.isPowerOfTwo(n)
```

## Rejected Alternatives

- **Math.PI as property**: Would require member access dispatch changes for built-in classes. Deferred — `MathUtil.PI()` method is acceptable.
- **Single module for everything**: Mixing runtime functions and pure SS utilities would blur the two-tier architecture. Keeping them separate matches the existing pattern (Math builtins vs lib/ modules).

## Tensions

- **C5 (no user-facing memory syntax)**: No tension — math functions are pure computations.
- **V4 (core logic in SS)**: MathUtil is pure SS. Math builtins wrap libc, which is acceptable for low-level infrastructure per V4.
