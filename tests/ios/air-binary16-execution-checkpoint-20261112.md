# Software binary16 arithmetic checkpoint — 2026-11-12

`731dbe2e4` adds flag-free half `fadd`, `fsub`, `fmul`, `fdiv`, `frem` and
all sixteen `fcmp` predicates to the mixed scalar AIR interpreter. Fortnite
retains its historical **4/8 observed launch gates** and
[GPU requirements alert](controller-discovery-checkpoint-20261104.md), with
no verified game frame, menu, login or playable match. The gate count does
not measure engineering completion.

Arithmetic operates on integer half significands/exponents and rounds directly
to half, nearest/ties to even with gradual underflow. Products fit 22 bits;
division uses at most 25 numerator bits and a sticky remainder. Remainder uses
at most 39 exponent steps and returns an exact result with the dividend's sign.
Precision conversion shares the half packer. Comparisons use integer-only
classification after exact widening. Constant true/false predicates ignore
poison/undef operands. Other arithmetic/comparisons propagate poison; selected
undef and fast-math flags reject. Invalid arithmetic produces the preferred
quiet NaN. No rounded float arithmetic, production host FP operation, new
allocation, execution array or LLVM dependency is introduced. The integer-only
API, budgets and ownership contract remain unchanged. Valid IR and matching
immutable indexes remain preconditions. See
[BINARY16.md](../../compat/ios/airbitcode/BINARY16.md).

Normal and ASan/UBSan units pass **41 exact arithmetic patterns**, every
predicate and **131,072 subnormal remainders against integer modulo**. Twelve
mixed-interpreter groups pass, including decoded half arithmetic/comparisons,
precision conversions, flags, result kinds/widths/steps, constants and budgets.
Existing integer units retain 1,397,052 narrow flag comparisons and 28 i64
limits. Sanitized precision units retain all 65,536 half-encoding round trips.

Both normal and sanitized LLVM runs pass **2,587,648 comparisons** across
31 functions: five primitive arithmetic operations, sixteen predicates, seven
bit/value-flow cases and three arithmetic/control-flow cases. Each function
receives 1,024 edge pairs and every half encoding once in operand A, paired
with mixed-bit B. The eight arithmetic/flow functions also receive 65,536
independent mixed-bit pairs. This is not exhaustive pair coverage. Accumulation
loops round each addition to half; parallel PHIs retain simultaneous swaps.
Primitive arithmetic results require exactly two executed instructions.

**2,525,468 results compare bit for bit**, including NaNs in non-arithmetic
operations. **62,180 arithmetic NaNs** check native NaN class and Vinix's exact
preferred representation; native NaN sign/payload equality is not qualified.
Seven rejecting guards, five poison results, lazy select/constant predicates,
five corrupted-result controls and four host-rounding controls pass. Native
calls run only in the default environment. LLVM/JIT/native libm code is not
sanitizer-instrumented. Leak detection is disabled and retained memory was not
measured.

Sanitized regressions pass all **1,167,424 half precision/value-flow
comparisons**, **649,216 float comparisons**, **1,064,960 numeric conversion
comparisons** and **17,280 integer comparisons**, with their controls. Retired
half arithmetic/comparison guards now check unsupported dead double precision
and fast comparison flags. Original historical sources/evidence remain in
their original bundles.

The mixed unit executable cross-compiles and links as a static little-endian
AArch64 Linux ELF and passes header inspection. It has not run in a guest.
No AIR shader, iOS application, Metal command, GPU work or new Fortnite probe
ran. The [default Metal device](../../compat/ios/runner/metal_device.c.v) still
returns nil. Half/integer numeric conversions, vectors, memory, intrinsics,
resources, pipelines, command submission and presentation remain unfinished.

Complete evidence is retained outside Git at:

`/Users/alex/Library/Caches/vinix-ios/air-binary16-execution-validation-20261112-r1/`

The bundle contains committed source, generated IR/bitcode, every comparison,
assembler/JIT/fenv identities, binaries, target C, logs and reproduction notes.
Builds use V `0.5.2 596e18d`; LLVM C bindings emit `usize` deprecation warnings.
Unit/AArch64 builds have empty diagnostics. Selected compiler/header identities
match the pre-build receipt and pass recheck. Full compiler, SDK, LLVM/JIT/libm,
fenv and sanitizer dependency closures are not sealed.

The unchanged complete typed inventory checker passes for the original and
a fresh full restore under `air-binary16-execution-restoration-20261112-r1/`.
Every recorded path, byte, size, type and permission matches. Restored sanitized
arithmetic/mixed units and all 2,587,648 LLVM half arithmetic comparisons pass
again, including guards and controls. Sibling logs preserve the receipts. This
qualifies scalar half execution and evidence integrity only.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-binary16-execution-validation-20261112-r1.inventory.json` | `fc701361e3caead5afe39605e4dfa1f3d58ccfe950a0695951ce5132d71166f7` |
| `air-binary16-execution-validation-20261112-r1.tar.zst` | `9f68a0513e042bdc841a4029744ed6e39040c62d9387606cd3c1c920653744c1` |
| `source.tar`, revision `731dbe2e4` | `eaa904f0fce4fdf5cefd7c6b6d9df2e2f1d3388c35721532e9062a5174170e73` |
| `scalar-aarch64` | `a8af6c4cde1e45e6435d196776df2402ccde224b94d413e3472cd4d8c48e4ada` |
