# Scalar signed and unsigned integer extrema

The mixed scalar interpreter accepts `llvm.smin.iN`, `llvm.smax.iN`,
`llvm.umin.iN` and `llvm.umax.iN` for every N from 1 through 64. Each takes two
iN arguments and returns iN. Signed operations select the smaller/larger
two's-complement value; unsigned operations select the smaller/larger bit
pattern. The chosen input's exact masked bits are returned. Equal inputs agree
in either argument order. Poison in either operand propagates; selected undef
errors. The integer-only API retains its existing no-call profile.

Production compares unsigned keys after flipping the sign bit for signed
operations. It performs no signed conversion, subtraction or overflowing host
signed arithmetic, including for i1 and INT64_MIN. Unsigned operations compare
the masked bits directly. No host builtin, LLVM, FP or new allocation participates.
Unary evaluators reject these binary operations. CALL/return takes two executed
instructions.

The [existing direct-call profile](SCALAR-INTRINSICS.md) checks canonical names,
exact integer width, homogeneous signature/arity, external declaration identity,
calling convention, default pointer address space and explicit-type header.
Fast-math/tail flags and call-site attributes reject. Harmless function-level
declaration attributes retain their whitelist; parameter/return attributes,
including `immarg`, reject for these operations. Vectors, wider integers,
malformed decimal suffixes and AIR aliases reject. Valid LLVM IR and matching
immutable indexes remain preconditions.

The fixed stack cache has 808 entries: forty floating-overload slots and twelve
independent 64-width integer ranges. The four extrema families use separate
ranges. Attribute validation runs once per admitted declaration under the
shared 1,000,000-work limit. The three owned execution arrays and their cleanup
remain unchanged. Retained allocation is not measured.

`scalar_integer_extrema_test.v` passes **1,267,024** comparisons against an
independent reference that reconstructs negative magnitudes safely in i64.
All i1..i8 pairs are exhausted; wider widths receive 4,096 patterned pairs per
operation. Symmetry, idempotence, i1/i64 signed limits and strict name/width/
arity/evaluator guards also pass.

`tests/ios/air-integer-extrema.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates
and LLVM-verifies 256 primitive functions across all widths and families. It
compares **1,303,888 bit-exact native LLVM results**, including **36,864 boundary
pairs** from a twelve-by-twelve edge matrix. Inputs cover signed minima/maxima,
unsigned maxima/zero, neighboring values, alternating and byte patterns. All
i1..i8 pairs are exhausted; wider cases receive 4,096 mixed-bit pairs. Incoming
high bits test masking of both arguments.

Controls check 512 poison results and 512 undef rejections across both operand
positions, 512 budget/integer-API rejections, twenty-eight metadata corruptions,
eight argument-type mismatches, twelve name/width mismatches and twenty result
corruptions. Another 512 mixed-family chains run all four declarations in one
function: unsigned extrema of the signed-selected pair XOR back to the original
inputs' XOR, in six instructions. The checker runs only generated fixtures.
LLVM/JIT/native code is not sanitizer-instrumented. IR/bitcode, every comparison,
binaries, identities and logs belong in complete external bundles.

This is scalar execution groundwork. No AIR shader, Metal device, GPU command
or application launch is qualified.

References: [LLVM signed minimum](https://llvm.org/docs/LangRef.html#llvm-smin-intrinsic),
[signed maximum](https://llvm.org/docs/LangRef.html#llvm-smax-intrinsic),
[unsigned minimum](https://llvm.org/docs/LangRef.html#llvm-umin-intrinsic),
[unsigned maximum](https://llvm.org/docs/LangRef.html#llvm-umax-intrinsic).
