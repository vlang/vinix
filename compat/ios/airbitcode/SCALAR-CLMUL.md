# Scalar carry-less multiplication

The mixed scalar interpreter accepts `llvm.clmul.iN` for every N from 1 through
64. It takes two iN arguments and returns iN. Multiplication replaces additions
with XOR, treating the inputs as polynomial bit coefficients and retaining the
low N product bits. Overflow is discarded without poison. Poison in either
input propagates; selected undef errors. The integer-only API retains its
no-call profile. Primitive CALL/return takes two executed instructions.

Production masks both inputs and accumulates shifted terms selected by the
multiplier bits, using XOR. Each term is masked to N bits. The loop takes at
most 64 iterations and shifts only by one, including for a full i64 multiplier.
No host signed arithmetic, builtin, LLVM, FP or new allocation participates in
valid numerical evaluation. Unary integer evaluators reject this binary call.

The [direct-call profile](SCALAR-INTRINSICS.md) checks canonical names, exact
widths, homogeneous fixed signatures, external declaration identity, ordinary
calling convention, default pointer address space and explicit-type header.
Fast-math/tail flags and call-site attributes reject. Harmless function-level
declaration attributes retain their whitelist; parameter/return attributes,
including `immarg`, reject for this operation. Vectors, wider integers,
malformed suffixes and AIR aliases reject. All blocks are preflighted. Valid
LLVM IR and matching immutable indexes remain preconditions.

The fixed stack cache has 1384 entries: forty floating-overload slots and
twenty-one independent 64-width integer ranges. Carry-less multiplication has
its own range. The shared 1,000,000-work attribute limit, fixed two-ID storage
and three existing owned execution arrays/cleanup remain. Retained allocation
is not measured.

`scalar_clmul_test.v` passes **325,972** independent polynomial-convolution
comparisons, including **9,216 boundary pairs**. Every i1..i8 input pair is
exhausted; wider widths receive 4,096 mixed pairs and a twelve-by-twelve edge
matrix. The reference computes each output coefficient's parity from all
input-bit pairs on its diagonal. It uses no shifted-term accumulation.
Commutativity, XOR distributivity, polynomial squaring, zero/identity behavior,
high-bit truncation and strict name/width/arity/evaluator guards also pass.

`tests/ios/air-clmul.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates and
LLVM-verifies 64 primitive functions. It compares **325,972 bit-exact native
LLVM results**, including **9,216 boundary pairs**, using different wider
patterns and incoming high-bit noise on both arguments. Edges include zero,
one, all bits set, high bits and neighbors, alternating and byte patterns.
Controls check 128 input-poison results, 128 undef rejections, 128 budget/
integer-API rejections, seven metadata corruptions, two type mismatches, three
name/width mismatches and five result corruptions. Another 512 chains combine
commutativity and XOR-distributivity residuals with OR, requiring both to be
zero, in ten instructions. Each chain uses four calls to the same declaration.
Another 128 controls corrupt the second call's flags or attributes, checking
that cached declaration validation never skips per-call checks.

Only generated fixtures execute. LLVM/JIT/native code is not sanitizer-
instrumented. Complete fixtures, bitcode, every comparison, binaries, identities
and logs belong in external bundles. `tests/ios/air-clmul-regressions.v` runs
the local pinned-toolchain shared-profile checks; its header documents the
environment and output children must be fresh.

This is scalar execution groundwork. No AIR shader, Metal device, GPU command
or application launch is qualified.

Reference: [LLVM clmul semantics](https://llvm.org/docs/LangRef.html#llvm-clmul-intrinsic).
