# Numeric binary16/integer checkpoint — 2026-11-12

`5d2609f9a` adds flag-free `uitofp`, `sitofp`, `fptoui` and `fptosi` between
half and every integer width i1..i64. Fortnite retains its historical **4/8
observed launch gates** and
[GPU requirements alert](controller-discovery-checkpoint-20261104.md), with
no verified game frame, menu, login or playable match. The gate count does
not measure engineering completion.

Integer-to-half normalizes an unsigned magnitude and rounds directly to half,
nearest/ties to even. Overflow produces signed infinity: unsigned 65519 rounds
to 65504, while 65520 rounds to infinity. Half-to-integer uses exact integer-only
widening followed by the existing truncation/range checker. NaNs, infinities
and results outside the destination range produce poison. Range checks follow
truncation, preserving unsigned negative fractions near zero and signed i8
-128.5 becoming -128. Poison operands propagate; selected undef and nonzero
conversion flags reject. There is no host FP cast, new production allocation,
execution array or LLVM dependency. The integer-only API, budgets and ownership
contract remain unchanged. Valid IR and matching immutable indexes remain
preconditions. See [BINARY16-INTEGER.md](../../compat/ios/airbitcode/BINARY16-INTEGER.md).

Normal and ASan/UBSan units pass **18 exact integer-to-half patterns**, **27
half-to-integer patterns**, width guards and **8,188 exhaustive signed/unsigned
i1..i11 exact round trips**. Thirteen mixed-interpreter groups pass, including
decoded casts, masking, kinds/widths/steps, fractional bounds, overflow infinity,
poison/undef and flag/profile/budget guards. Existing integer units retain
1,397,052 narrow flag comparisons and 28 i64 limits.

Both normal and sanitized LLVM runs pass **9,445,376 defined-reference
comparisons**: **7,735,300 values** and **1,710,076 poison results**. All 65,536
half encodings execute through each signed/unsigned destination width, totaling
8,388,608 half-to-integer comparisons. Each of 128 integer-to-half functions
receives 8,256 edge, tie, overflow-neighbor, mixed small/sign and wide-bit inputs,
totaling 1,056,768 comparisons. Wide integer input coverage is not exhaustive.

The native integer-to-half oracle uses ordinary LLVM casts, defined even for
overflow to infinity. Half-to-integer values use exact native widening to float,
defined saturating i64 conversions and destination masking. An independent
poison reference truncates in float, then checks NaNs and exact power-of-two
bounds up to 2^64. No potentially invalid ordinary native half-to-integer
function is called. Vinix executes original cast functions, never the reference
wrappers, intrinsics or CALL instructions. Exact values, poison, kinds, widths
and two executed instructions compare. All 24 corrupted-result controls reject,
including lost poison tags. Two distinguishing host-rounding controls retain
software RNE; native calls use only the default environment.

Sanitized regressions pass **2,587,648 half arithmetic comparisons**,
**1,167,424 half precision/value-flow comparisons**, **649,216 float comparisons**,
**1,064,960 float/integer conversions** and **17,280 integer comparisons**, with
their controls. Retired half/integer rejection guards now check unsupported
conversion flags, including a flagged unused instruction. Original historical
source/evidence remain in their original bundles. LLVM/JIT/native code is not
sanitizer-instrumented. Leak detection is disabled and retained memory was not
measured.

The mixed unit executable cross-compiles and links as a static little-endian
AArch64 Linux ELF and passes header inspection. It has not run in a guest.
No AIR shader, iOS application, Metal command, GPU work or new Fortnite probe
ran. The [default Metal device](../../compat/ios/runner/metal_device.c.v) still
returns nil. Vectors, memory, intrinsics, resources, pipelines, command submission
and presentation remain unfinished.

Complete evidence is retained outside Git at:

`/Users/alex/Library/Caches/vinix-ios/air-binary16-integer-validation-20261112-r1/`

The bundle contains committed source, generated IR/bitcode, every comparison,
assembler/JIT/fenv identities, binaries, target C, logs and reproduction notes.
Builds use V `0.5.2 596e18d`; LLVM C bindings emit `usize` deprecation warnings.
Unit/AArch64 builds have empty diagnostics. Selected compiler/header identities
match the pre-build receipt and pass recheck. Full compiler, SDK, LLVM/JIT,
fenv and sanitizer dependency closures are not sealed.

The unchanged complete typed inventory checker passes for the original and
a fresh full restore under `air-binary16-integer-restoration-20261112-r1/`.
Every recorded path, byte, size, type and permission matches. Restored sanitized
conversion/mixed units and all 9,445,376 LLVM comparisons pass again, including
poison, corruption and rounding controls. Sibling logs preserve the receipts.
This qualifies scalar numeric conversion and evidence integrity only.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-binary16-integer-validation-20261112-r1.inventory.json` | `72a8878f0f95d0ea67f61a02a0d382f47ae45de8badd5a4d82f63f05f9aa2435` |
| `air-binary16-integer-validation-20261112-r1.tar.zst` | `fcdedae593c5f662a3e47d3e3193a3215658a5372f364408cddfe387731abe23` |
| `source.tar`, revision `5d2609f9a` | `9664523e4111eed94aab9b2aec99f93b22cf982e5c275b937e837bd76cde3b0b` |
| `scalar-aarch64` | `4fe472f17fccdfd02a5bcec7b20deefa42d798fb5b85fe9c1de039f0bb2b6da6` |
