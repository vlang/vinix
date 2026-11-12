# Scalar bit extraction and deposition

The mixed scalar interpreter accepts `llvm.pext.iN` and `llvm.pdep.iN` for
every N from 1 through 64. Each takes an iN value and an iN mask and returns iN.
`pext` gathers the selected value bits, from low to high, into contiguous low
result bits. `pdep` scatters low value bits into the mask's selected positions,
in the same order. Remaining result bits are zero. Empty masks return zero;
full masks preserve the input. Poison in either operand propagates; selected
undef errors. The integer-only API retains its no-call profile. Primitive
CALL/return takes two executed instructions.

Production masks both inputs to their declared width, consumes the lowest set
mask bit at each iteration and pairs it with the next packed bit. It takes at
most 64 iterations. Every shift is by one; the final i64 mask bit never causes
a shift by 64. Unsigned isolation/subtraction also handles the high bit of i64.
No host signed arithmetic, builtin, LLVM, FP or new allocation participates in
valid numerical evaluation. Unary integer evaluators reject these binary calls.

The [direct-call profile](SCALAR-INTRINSICS.md) checks canonical reserved
names, exact widths, homogeneous fixed signatures, external declaration
identity, ordinary calling convention, default pointer address space and the
plain explicit-type header. Fast-math/tail flags and call-site attributes
reject. Harmless function-level declaration attributes retain their whitelist;
parameter/return attributes, including `immarg`, reject for these operations.
Dynamic masks are supported. Vectors, wider integers, malformed suffixes and
AIR aliases reject. All blocks are preflighted. Valid LLVM IR and matching
immutable indexes remain preconditions.

The fixed stack cache has 1384 entries: forty floating-overload slots and
twenty-one independent 64-width integer ranges. Extraction and deposition have
separate ranges. The shared 1,000,000-work attribute limit, fixed two-ID
attribute storage and three existing owned execution arrays/cleanup remain.
Retained allocation is not measured.

`scalar_bit_permutation_test.v` passes **651,944** independent position/rank
comparisons, including **18,432 boundary pairs**. Every i1..i8 value/mask pair
is exhausted; wider widths receive 4,096 mixed pairs and a twelve-by-twelve edge
matrix. The reference scans every width position and obtains its packed rank
from a standard-library population count of lower mask bits. The standard
library is a test dependency only. Both inverse identities, empty/full masks
and strict name/width/arity/evaluator guards also pass:

```
pdep(pext(value, mask), mask) == value & mask
pext(pdep(value, mask), mask) == value & low_bits(popcount(mask))
```

`tests/ios/air-bit-permutation.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates
and LLVM-verifies 128 primitive functions. It compares **651,944 bit-exact
native LLVM results**, including **18,432 boundary pairs**, using different
wider patterns and incoming high-bit noise on both operands. Edges include
zero/full masks, sign bits and neighbors, alternating and byte patterns.
Controls check 256 input-poison results, 256 undef rejections, 256 budget/
integer-API rejections, fourteen metadata corruptions, four type mismatches,
six name/width mismatches and ten result corruptions. Another 1,024 mixed-family
cache chains check both inverse orders in three instructions, including empty,
full and single low/high-bit masks at every width. Only generated fixtures
execute. LLVM/JIT/native code is not sanitizer-instrumented. Complete fixtures,
bitcode, every comparison, binaries, identities and logs belong in external
bundles. `tests/ios/air-bit-permutation-regressions.v` runs the local pinned-
toolchain shared-profile checks; its header documents the environment and
output children must be fresh.

This is scalar execution groundwork. No AIR shader, Metal device, GPU command
or application launch is qualified.

References: [LLVM pext](https://llvm.org/docs/LangRef.html#llvm-pext-intrinsic),
[LLVM pdep](https://llvm.org/docs/LangRef.html#llvm-pdep-intrinsic).
