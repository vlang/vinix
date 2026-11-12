# Scalar funnel shifts and rotations

The mixed scalar interpreter accepts `llvm.fshl.iN` and `llvm.fshr.iN` at
every width N from 1 through 64. Three iN arguments supply the high half A,
low half B and unsigned shift amount S; the result is iN. The amount is masked
to iN before reducing modulo N. Left shifts extract the high half of the
shifted conceptual A:B concatenation; right shifts extract the low half.
Matching A and B give left/right rotation. Poison in any operand propagates,
including at shift zero; selected undef errors. The integer-only API retains
its existing no-call profile.

Production uses two unsigned shifts and an OR, with a separate zero-shift
branch. Zero returns A for left and B for right. Nonzero shifts and complements
are in 1..N-1, avoiding a host shift by 64 even at i64. Width i1 always takes
the zero branch. Final bits are masked to iN. No wider integer, host builtin,
LLVM, floating point or new allocation participates. Unary/binary numeric
evaluators reject these operations; ternary dispatch reads all three operands.
CALL/return takes two instructions.

The [direct-call profile](SCALAR-INTRINSICS.md) checks exact canonical names,
integer width, homogeneous signature/arity, external declaration identity,
calling convention, default pointer address space and explicit-type header.
Fast-math/tail flags and call-site attributes reject. Harmless function-level
declaration attributes retain their whitelist; parameter/return attributes,
including `immarg`, reject for these operations. Dynamic shift amounts are
supported. Vectors, wider integers, malformed decimal suffixes and AIR aliases
reject. Valid LLVM IR and matching immutable indexes remain preconditions.

The fixed stack cache has 1192 entries: forty floating-overload slots and eighteen
independent 64-width integer ranges. Funnel-left and funnel-right use separate
ranges; attribute validation runs once per admitted declaration under the
existing shared 1,000,000-work limit. The three owned execution arrays and their
cleanup remain unchanged. Retained allocation is not measured.

`scalar_funnel_test.v` passes **558,224** comparisons against an independent
oracle that selects each output bit from the conceptual concatenation. All
i1..i5 triples are exhausted; wider widths receive 4,096 patterns per direction.
Rotation round trips, zero-shift operand selection and strict name/width/arity/
evaluator guards also pass.

`tests/ios/air-funnel.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates and
LLVM-verifies 256 primitive/rotation functions over all widths and directions.
It compares **2,230,560 bit-exact native LLVM results**, including **1,114,112
boundary triples**. The eight-by-eight data-edge matrix uses shifts 0..2N-1,
all-one and high-bit amounts, and a mixed-bit amount. i1..i5 triples are exhausted;
wider inputs receive 4,096 mixed-bit triples. Incoming high bits test masking
of all three operands, including odd-width shift amounts before modulo.

Controls check 384 poison results and 384 undef rejections across all operand
positions, 256 budget/integer-API rejections, fourteen metadata corruptions,
six type mismatches, six name/width mismatches and ten result corruptions.
Another 512 complementary concatenation/shift chains restore the original
first operand, exercising both declarations in one function and exact four-
instruction results, including zero shifts. The checker runs only generated
fixtures. LLVM/JIT/native code is not sanitizer-instrumented. IR/bitcode, every
comparison, binaries, identities and logs belong in complete external bundles.

This is scalar execution groundwork. No AIR shader, Metal device, GPU command
or application launch is qualified.

References: [LLVM funnel-left](https://llvm.org/docs/LangRef.html#llvm-fshl-intrinsic),
[LLVM funnel-right](https://llvm.org/docs/LangRef.html#llvm-fshr-intrinsic).
