# Scalar saturating integer addition and subtraction

The mixed scalar interpreter accepts `llvm.sadd.sat.iN`, `llvm.uadd.sat.iN`,
`llvm.ssub.sat.iN` and `llvm.usub.sat.iN` for every N from 1 through 64.
Each takes two iN arguments and returns iN. Signed results clamp to the signed
minimum/maximum; unsigned addition clamps to the unsigned maximum and unsigned
subtraction clamps to zero. Saturation produces a defined value. Poison in
either input propagates; selected undef errors. The integer-only API retains
its no-call profile. Primitive CALL/return takes two executed instructions.

Production masks both inputs and uses unsigned arithmetic throughout. Unsigned
operations check the available margin before addition/subtraction. Signed
operations compute a masked modular result and detect overflow from the input
and result sign bits, then choose the appropriate signed limit. This handles
i1 and INT64_MIN without host signed arithmetic or overflow. No host builtin,
LLVM, FP or new allocation participates in numerical evaluation. Unary integer
evaluators reject these binary operations.

[Saturating left shifts](SCALAR-SATURATING-SHIFT.md) use separate poison-aware
evaluation because a shift amount at least as large as the width produces poison.

The [direct-call profile](SCALAR-INTRINSICS.md) requires canonical reserved
names, exact integer widths, homogeneous fixed signatures, external declaration
identity, ordinary calling convention, default pointer address space and the
plain explicit-type header. Fast-math/tail flags and call-site attributes
reject. Harmless function-level declaration attributes retain their whitelist;
parameter/return attributes, including `immarg`, reject for these operations.
Vectors, wider integers, malformed decimal suffixes and AIR aliases reject.
All blocks are preflighted. Valid LLVM IR and matching immutable indexes
remain preconditions.

The fixed stack cache has 1320 entries: forty floating-overload slots and
twenty independent 64-width integer ranges. The four saturating families use
separate ranges. Attribute validation runs once per admitted declaration under
the shared 1,000,000-work limit. Fixed two-ID attribute storage and the three
existing owned execution arrays/cleanup remain. Retained allocation is not measured.

`scalar_saturating_test.v` passes **1,303,888** independent margin/carry-reference
comparisons, including **36,864 boundary pairs**. Every i1..i8 input pair is
exhausted; wider widths receive 4,096 mixed-bit pairs and a twelve-by-twelve edge
matrix. The signed reference safely reconstructs signed values, checks margins
before computing any potentially overflowing result, and clamps first. The
unsigned-add reference uses two 32-bit limbs with an explicit carry. Addition
commutativity, zero identities and strict name/width/arity/evaluator guards pass.

`tests/ios/air-saturating.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates and
LLVM-verifies 256 primitive functions. It compares **1,303,888 bit-exact native
LLVM results**, including **36,864 boundary pairs**, with incoming high-bit
noise on both arguments. Inputs cover signed minima/maxima and neighbors,
unsigned maxima/zero, alternating and byte patterns. Every i1..i8 pair is
exhausted; wider widths receive 4,096 mixed-bit pairs plus the edge matrix.

Controls check 512 input-poison results, 512 undef rejections, 512 budget/
integer-API rejections, twenty-eight metadata corruptions, eight argument-type
mismatches, twelve name/width mismatches and twenty result corruptions. Another
512 mixed-family cache chains use all four declarations with zero as the
second operand and return the original inputs' XOR in six instructions.
Only generated fixtures execute. LLVM/JIT/native code is not sanitizer-
instrumented. Complete IR/bitcode, every comparison, binaries, identities and
logs belong in external bundles. `tests/ios/air-saturating-regressions.v` runs
the local pinned-toolchain shared-profile checks; its header documents the
environment and output children must be fresh.

This is scalar execution groundwork. No AIR shader, Metal device, GPU command
or application launch is qualified.

Reference: [LLVM saturation semantics](https://llvm.org/docs/LangRef.html#saturation-arithmetic-intrinsics).
