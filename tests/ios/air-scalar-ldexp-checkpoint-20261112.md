# Scalar power-of-two scaling checkpoint — 2026-11-12

`ccf5d9f2c` adds `llvm.ldexp.f16.i32` and `llvm.ldexp.f32.i32`: a floating
input/result with a signed i32 exponent. Admission now verifies mixed operand
types while preserving the existing strict name, precision, signature, direct
declaration identity, header and attribute checks. Other exponent widths,
precisions, vectors, flagged/constrained/general calls and AIR aliases reject.
Valid LLVM IR and matching immutable indexes remain preconditions.

Evaluation adjusts an integer significand's exponent and packs once, rounding
to nearest/ties to even with gradual underflow. Rounded zero and overflow
infinity retain the input sign; zeros and infinities remain unchanged. NaNs
choose the existing preferred positive quiet representation. Bounds outside
-512..512 resolve every nonzero finite input before exponent addition, including
INT_MIN/MAX; normalization takes at most 23 shifts. No host FP, libm, LLVM,
allocation or native invocation participates. See [the scaling contract](../../compat/ios/airbitcode/SCALAR-LDEXP.md).

Poison in either operand propagates; selected undef errors. Calls cost one
instruction. Generated AArch64 C confirms the twenty-eight-entry declaration
cache is fixed stack storage. The existing three owned execution arrays and
cleanup remain unchanged; retained allocation was not measured.

Normal and ASan/UBSan units pass **48 exact scaling values** and name/arity
guards. Legacy intrinsic units pass their 28 intrinsic/88 extrema/32 square-root
values, 327,680 integer root checks and attribute guards. Mixed-scalar units
pass thirteen groups, including 1,397,052 narrow flag cases and 28 i64 limits.

Normal and sanitized reference runs each pass **10,029,632 comparisons** over
36 functions: **8,604,902 exact results** and **1,424,730 math NaN-class cases**,
checking Vinix's exact preferred representation for native NaNs. Every half
case receives all 65,536 encodings; float cases receive 32 edges, 65,536 mixed-bit
and 65,536 midpoint/neighbor inputs. New scaling sweeps cross all half encodings
and 65,536 float patterns with sixteen signed exponents, including INT_MIN/MAX,
for **2,097,152 scaling boundary pairs**. The scaling wrappers check exact
three-step accounting for exponent truncation, intrinsic call and return.

Eight new poison/undef, two exponent-type and four distinguishing underflow
rounding controls pass alongside all existing guards, poison/lazy select,
budget/integer isolation, eight metadata/two declaration/five result-corruption
controls. All fourteen host-rounding controls pass. Native reference calls run
only in LLVM's default environment. The prior [half `copysign` discrepancy](air-scalar-intrinsics-checkpoint-20261112.md)
retains its 65,536 native LLVM integer-oracle comparisons and diagnostic;
the remaining **9,964,096 comparisons use native floating-point wrappers**,
including all new scaling cases. No payload check was weakened.

Sanitized regressions pass **1,505,792 FMA**, **2,587,648 half arithmetic** and
**649,216 float** comparisons and their controls. Unchanged numeric-conversion,
half-precision, half/integer and standalone integer LLVM suites were not rerun.
LLVM/JIT/native code is not sanitizer-instrumented and leak detection is disabled.

Mixed-scalar and scaling units cross-compile/link as static little-endian
AArch64 Linux ELFs and pass header inspection. Neither ran in a guest. No AIR
shader, application, Metal command, GPU work or new Fortnite probe ran. The
[default Metal device](../../compat/ios/runner/metal_device.c.v) remains nil;
no new frame or launch gate is verified.

Complete evidence is retained outside Git:

`/Users/alex/Library/Caches/vinix-ios/air-scalar-ldexp-validation-20261112-r1/`

The bundle contains committed source, fixtures/IR/bitcode, every comparison,
binaries, target C, identities, logs and reproduction notes. Builds use V
`0.5.2 596e18d` and LLVM `23.1.5`, retaining existing `usize` C FFI warnings.
Selected compiler/header/library identities match their pre-build receipt.
Full compiler/SDK/LLVM/JIT/fenv/sanitizer dependency closures are not sealed.

The unchanged complete typed inventory checker passes for the original and
a fresh restore under `air-scalar-ldexp-restoration-20261112-r1/`, matching every
path, byte, size, type and permission. Full decoding to a tar file and extraction
both exit zero. Restored sanitized units and all 10,029,632 reference comparisons
pass again with their guards and controls. Receipts remain beside the bundles.
These checks qualify scalar execution and evidence integrity only.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-scalar-ldexp-validation-20261112-r1.inventory.json` | `481f0c4f3237224126204ed027cc87b9f2b4e5b74d59b38f9c83f8feb7c6f804` |
| `air-scalar-ldexp-validation-20261112-r1.tar.zst` | `8ee2798bd222b2b0c3650c987757a26681b86976f1f5d17da0514b4a76b3ef03` |
| `source.tar`, revision `ccf5d9f2c` | `b8e6b05fbde5f01722d607aaef932a7c04dff4db975882ef2dcd0d399aa1b68d` |
| `scalar-aarch64` | `ab2247f6ef80beeac58ba5e661dcd71b43e38feb38471bd79f7b96699877d13a` |
| `ldexp-aarch64` | `2208963ac391d54338dcd7848c3dbf222a45207071f1edb243661b0332c2e138` |
