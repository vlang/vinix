# Software binary16 precision checkpoint — 2026-11-12

`8becc05d2` adds flag-free `fptrunc float ... to half` and `fpext half ... to
float`, plus half/i16 bitcasts and half values in arguments, constants, return,
select, PHIs and `fneg`. `IRScalarKind` appends a `binary16` kind, and
`IRScalarRun` reports 16-bit half results. Existing enum values and the
integer-only API are stable.
Fortnite retains its historical **4/8 observed launch gates** and
[GPU requirements alert](controller-discovery-checkpoint-20261104.md), with
no verified game frame, menu, login or playable match. The gate count is not
an engineering completion percentage.

Narrowing uses integer significands and guard/round/sticky bits, rounding to
nearest/ties to even with gradual underflow and signed overflow to infinity.
Widening is exact for every finite half value. Precision-conversion NaNs
choose the preferred positive quiet NaN; copies, bitcasts, select and PHIs
preserve NaN bits, and negation changes only the sign. Poison propagates;
selected undef and fast-math flags reject. Half arithmetic/comparisons and
numeric half/integer conversions reject, including in unvisited blocks.
Production conversion adds no host FP operation, allocation, execution array
or LLVM dependency. Valid IR, matching immutable indexes and the existing
budget/ownership contract remain preconditions. See
[BINARY16.md](../../compat/ios/airbitcode/BINARY16.md).

Normal and ASan/UBSan units pass 14 exact widening patterns, 32 exact narrowing
patterns and **65,536 half-encoding round trips**. Twelve mixed-interpreter
groups pass, including kinds/widths/steps, input masking, constants, poison,
undef, signaling-NaN negation, budget and profile guards. Existing integer
units retain 1,397,052 narrow flag comparisons and 28 i64 limits.

Both normal and sanitized LLVM runs pass **1,167,424 comparisons** across
twelve functions. Ten half/i16-input cases each cover all 65,536 encodings.
Two float-input cases each cover 65,536 mixed-bit inputs, 32 fixed edges and
190,464 signed rounding-boundary samples: every half midpoint and both
immediate float neighbors, including underflow, the subnormal/normal transition
and overflow. Test-only native LLVM independently computes exact float
midpoints; Vinix never executes that generator or the native ABI wrappers.

All **1,162,800 results outside conversion NaN-class cases** compare bit for
bit, including signaling NaNs in non-conversion operations. The **4,624
conversion NaNs** check native NaN class and Vinix's exact preferred pattern;
native NaN payload/sign equality is not qualified. Eleven rejecting guards,
three poison results, lazy select, five corrupted-result controls and two
distinguishing host-rounding controls pass. Native calls use only the default
environment. LLVM/JIT native code is not sanitizer-instrumented; leak detection
is disabled and retained memory was not measured.

Sanitized regressions pass all **649,216 float comparisons**, **1,064,960
numeric conversion comparisons** and **17,280 integer comparisons**, with
their existing controls. Arithmetic units retain 131,072 subnormal remainder
checks against integer modulo. The old unsupported half conversion guard now
checks still-unsupported bfloat conversion; historical source/evidence remain
in their original archives.

The mixed unit executable cross-compiles and links as a static little-endian
AArch64 Linux ELF and passes header inspection. It has not run in a guest.
No AIR shader, iOS application, Metal command, GPU work or new Fortnite probe
ran. The [default Metal device](../../compat/ios/runner/metal_device.c.v) still
returns nil. Half arithmetic, vectors, memory, intrinsics, resources,
pipelines, command submission and presentation remain unfinished.

Complete evidence is retained outside Git at:

`/Users/alex/Library/Caches/vinix-ios/air-binary16-casts-validation-20261112-r1/`

The bundle contains committed source, generated IR/bitcode, every comparison,
assembler/JIT/fenv identities, binaries, target C, logs and reproduction notes.
Builds use V `0.5.2 596e18d`; LLVM C bindings emit `usize` deprecation warnings.
Unit/AArch64 builds have empty diagnostics. Selected compiler/header identities
match the pre-build receipt and pass recheck. Full compiler, SDK, LLVM/JIT,
fenv and sanitizer dependency closures are not sealed.

The unchanged complete typed inventory checker passes for the original and
a fresh full restore under `air-binary16-casts-restoration-20261112-r1/`.
Every recorded path, byte, size, type and permission matches. Restored sanitized
conversion/mixed units and all 1,167,424 LLVM half comparisons pass again,
including guards and controls. Sibling logs preserve the receipts. This
qualifies scalar precision conversion/value flow and evidence integrity only.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-binary16-casts-validation-20261112-r1.inventory.json` | `80074d9bbbcf4cfe7c6999c80a0eeec72f07169ba44c29de46e505740859c4aa` |
| `air-binary16-casts-validation-20261112-r1.tar.zst` | `b9d9b408e0bb2e8d797120ca97c7b5592cfe09ac0b0b8823774b3f0ae2a158f5` |
| `source.tar`, revision `8becc05d2` | `b1ed14a26ef3f308da148c0a18810acc611f315995bb4f526a8d5ca1a89ac9ce` |
| `scalar-aarch64` | `c4278de865f8623d36194d3b2b2d3947e5fc495e5cb09cd8c744e8a7cac11034` |
