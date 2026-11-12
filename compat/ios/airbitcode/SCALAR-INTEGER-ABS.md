# Scalar integer absolute value

The mixed scalar interpreter accepts `llvm.abs.iN(iN, i1)` for every N from
1 through 64, returning iN. The second argument must be a constant boolean.
For the minimum signed value, a false flag returns the original minimum bits;
a true flag produces poison. Every other input returns its absolute magnitude.
This includes i1, whose only negative value is also its minimum. Input poison
propagates; selected undef errors. The integer-only API retains its no-call
profile. CALL/return takes two executed instructions.

Production masks the input to its declared width and uses unsigned modular
negation when the sign bit is set. It never negates a host signed minimum,
including INT64_MIN. No host builtin, LLVM, FP or new allocation participates
in numerical evaluation. Untagged and unary integer evaluators reject abs.

The [direct-call profile](SCALAR-INTRINSICS.md) checks canonical names, exact
width/signature/arity, direct external declaration identity, calling convention,
default pointer address space and explicit-type CALL header. Fast-math/tail
flags and call-site attributes reject. Harmless function-level declaration
attributes retain their whitelist. Parameter two alone may have the exact enum
`immarg` attribute. Every call checks its constant i1 independently of attribute
caching, including in unvisited blocks. Dynamic, SSA, declaration, poison,
undef, splat, opaque, mistyped and nonboolean flag encodings reject. Vectors,
wider integers, malformed decimal suffixes and AIR aliases reject. Valid LLVM
IR and matching immutable indexes remain preconditions.

The fixed stack cache has 1192 entries: forty floating-overload slots and eighteen
independent 64-width integer ranges. Abs uses its own range. The shared
1,000,000-work attribute limit, fixed two-ID attribute storage and existing
three owned execution arrays/cleanup remain. Retained allocation is not measured.

`scalar_integer_abs_test.v` passes **655,356** independent signed-magnitude
comparisons (sixteen poison cases), plus idempotence, every width's minimum
under both flags, zero and strict name/width/arity/evaluator guards. Every
i1..i16 bit pattern is exhausted under both flags; wider widths receive 4,096
patterns each. The reference safely reconstructs signed values and handles
each minimum before signed negation, independently of production's arithmetic.

`tests/ios/air-integer-abs.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates
and LLVM-verifies 128 primitive functions across all widths and both flags.
It compares **656,892 exact value/tag results**, including **87 poison cases**.
Every i1..i16 bit pattern is exhausted; wider widths receive 4,096 mixed-bit
values. Twelve edge values per function include zero, +/-1, signed minima and
neighbors, maximum patterns, alternating bits and byte patterns. Incoming high
bits test argument truncation before the minimum comparison.

The native value wrapper substitutes zero before a call that would produce
poison; a separate native function returns an explicit minimum/flag poison tag.
No invalid native abs result is consumed, and no result bit is reserved for
tagging. Defined values, poison, result kind/width and exact instruction count
are compared. Poison payload bits are ignored.

Controls check 64 input-poison results, 64 undef rejections, 128 budget/integer-
API rejections, 128 mixed-flag results, 64 cached nonconstant-flag rejections,
seven metadata corruptions, twelve flag corruptions, six result corruptions and
one malformed flag in a dead block. Mixed functions reuse the same declaration
under both flags, with minimum and zero inputs, in exactly four instructions.
Only generated fixtures execute. LLVM/JIT/native code is not sanitizer-
instrumented. Complete IR/bitcode, every comparison, binaries, identities and
logs belong in external bundles.

`tests/ios/air-integer-abs-regressions.v EXTERNAL_BUNDLE_DIR` is the local
pinned-toolchain V batch for the shared-profile sanitizer regressions. Its
header records the required environment; output children must be fresh.

This is scalar execution groundwork. No AIR shader, Metal device, GPU command
or application launch is qualified.

Reference: [LLVM abs semantics](https://llvm.org/docs/LangRef.html#llvm-abs-intrinsic).
