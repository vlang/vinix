# Software binary32 remainder checkpoint — 2026-11-12

`a0da29046` adds flag-free scalar `frem` to the mixed AIR interpreter.
Fortnite remains at **4/8 observed launch gates**, last verified at the
[GPU requirements alert](controller-discovery-checkpoint-20261104.md).
No game frame, menu, login or playable match is verified. The gate count
does not measure engineering completion.

Remainder uses integer significand reduction with at most 276 shift/subtract
iterations, followed by normalization and exact packing. It preserves the
dividend's sign, including signed zero, and exact subnormal results. Finite
inputs work even when their quotient would overflow binary32. Infinite
dividends, zero divisors and NaNs return the existing preferred quiet NaN;
poison operands propagate and selected undef errors. Fast-math flags still
reject. There is no production host FP operation, allocation, libm or LLVM
dependency. The integer-only API, execution budget and ownership contract
remain unchanged. See [BINARY32.md](../../compat/ios/airbitcode/BINARY32.md).

Normal and ASan/UBSan unit runs pass 30 exact remainder patterns, **131,072
subnormal comparisons against integer modulo**, the existing arithmetic and
comparison tests, and eleven mixed-interpreter groups. Integration checks both
operand positions for poison, undef and constants, argument masking, result
kinds/widths/steps, signed zero, invalid-input NaN, flags and budgets. Existing
1,397,052 narrow integer flag comparisons and 28 i64 limits also pass.

Both normal and sanitized LLVM runs pass **649,216 comparisons** across 30
functions. The previous 517,120 comparisons remain, with **132,096 remainder
comparisons** added: 1,024 edge pairs, 65,536 mixed-bit pairs and all 65,536
encoded-exponent pairs with mixed significands/signs. All 643,575 non-NaN-class
results compare bit for bit. The 5,641 arithmetic NaNs check the native NaN
class and exact preferred Vinix representation; native NaN payload equality
is not qualified. Remainder results also require exactly two instructions.
Seven unsupported/undef guards, five poison results, lazy select, five
corrupted-result controls and four host-rounding controls pass. Native calls
run only in the default environment. LLVM may lower native `frem` to libm;
the interpreter uses neither calls nor libm.

Sanitized regressions pass all **1,064,960 conversion comparisons** (843,042
defined values, 221,918 poison results), 24 corruption controls, two conversion
rounding controls and **17,280 integer comparisons** with their controls.
Conversion units retain 262,140 exact signed/unsigned i1..i16 round trips.
ASan/UBSan instrument V code; LLVM/JIT/libm native code is not instrumented.
Leak detection is disabled and retained memory was not measured.

The mixed unit program cross-compiles and links as a static little-endian
AArch64 Linux ELF and passes header inspection. It has not run in a guest.
No AIR shader, iOS application, Metal command, GPU work or new Fortnite probe
ran. The [default Metal device](../../compat/ios/runner/metal_device.c.v) still
returns nil. Vectors, precision conversion, memory, intrinsics, resources,
pipelines, submission and presentation remain unfinished.

Complete evidence is retained outside Git at:

`/Users/alex/Library/Caches/vinix-ios/air-binary32-remainder-validation-20261112-r1/`

The bundle contains committed source, generated IR/bitcode, every comparison,
assembler/JIT identities, binaries, target C, logs and reproduction notes.
Completed builds use V `0.5.2 596e18d`; reference builds emit existing `usize`
deprecation warnings. Initial historical frozen-toolchain attempts failed in
an int128 preprocessor header; their diagnostic C is retained separately in
the bundle. Selected installed identities pass recheck. Full compiler, SDK,
JIT/libm, fenv and sanitizer dependency closures are not sealed.

The unchanged complete typed inventory checker passes for the original and
a fresh full restore under `air-binary32-remainder-restoration-20261112-r1/`.
Every recorded path, byte, size, type and permission matches. Restored
sanitized arithmetic/mixed units and all 649,216 LLVM float comparisons pass
again, including guards and controls. Sibling logs preserve restore receipts.
This establishes evidence integrity and scalar execution coverage only.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-binary32-remainder-validation-20261112-r1.inventory.json` | `579b94ea39569f0cdbddf82f07f16489c3282b834ae37103e0b2dda1229d74af` |
| `air-binary32-remainder-validation-20261112-r1.tar.zst` | `a971d5285cb5e6bed23b03dd2cf4b51ff2aef7ebd97306ea8c8c3c37a8c430a8` |
| `source.tar`, revision `a0da29046` | `0df879a24c1a877b19a52d3b3ccd4a547ec30f25407cf8ae615bdb0ebb3b65a5` |
| `scalar-aarch64` | `fb957f82b852b119b56e4eb9130c4b5b76e6fda3807e38da2fa560c9984143ca` |
