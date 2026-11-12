# Scalar integer bit intrinsics

The mixed scalar interpreter accepts ordinary direct LLVM calls to:

| Intrinsic | Widths | Result |
| --- | --- | --- |
| `llvm.ctpop.iN` | i1 through i64 | Number of set bits, returned at the input width. |
| `llvm.bitreverse.iN` | i1 through i64 | Input bit M moves to bit N-M-1. |
| `llvm.bswap.iN` | i16, i32, i48, i64 | Reverse the order of the even number of input bytes. |

Each intrinsic takes one integer argument and returns the identical integer
type. Arguments are masked to their declared width; results keep that width,
integer kind and exact bits. Poison propagates; selected undef errors. The
integer-only API retains its existing no-call profile. Integer-only functions
using these calls execute through `run_scalar_function`.

Production uses unsigned shifts, masks and additions in loops of at most 64
iterations (eight for byte swap), without host intrinsics, LLVM, floating point
or new allocation. Intrinsic CALL costs one executed instruction; primitive
CALL/return takes two. Name recognition inspects bytes directly without a
substring allocation or permissive numeric parser. Only canonical decimal
suffixes 1..64 are admitted; leading zeros, signs, trailing suffixes, vectors,
floating types, AIR aliases and unsupported byte-swap widths reject.

The [existing direct-call profile](SCALAR-INTRINSICS.md) checks declaration
identity, external linkage, signature/arity, default pointer address space,
ordinary calling convention, explicit-type header, zero fast-math flags and
no call-site attributes. The exact suffix must match the result and argument
integer type. Harmless function-level declaration attributes retain their
existing whitelist; parameter/return attributes, including `immarg`, reject
for these unary operations. All blocks are checked, including unvisited ones.
Valid LLVM IR and matching immutable indexes remain preconditions.

The fixed stack declaration cache has 360 entries: forty floating-overload
slots followed by five independent 64-width integer ranges, including the
[leading/trailing zero counts](SCALAR-ZERO-COUNTS.md). Only four slots
in the byte-swap range are admitted. Each declaration is attribute-validated
once per run under the shared 1,000,000-work limit; duplicate reserved
declarations reject. The existing three owned execution arrays and cleanup
are unchanged. This is not a retained-allocation measurement.

`scalar_integer_intrinsics_test.v` compares **733,180** exact results with
standard-library population count, bit reversal and byte reversal, plus
reversal involutions. It exhausts all i1..i16 input values and uses 4,096 wide
patterns per overload, checking name/width/arity guards and explicit i48/i64
limits. The standard library is a test dependency only.

`tests/ios/air-integer-intrinsics.v self-test LLVM_AS FRESH_EXTERNAL_DIR`
generates and LLVM-verifies 132 primitive functions with native wrappers.
Every narrow input is exhausted; wider inputs receive 4,096 mixed-bit values,
and every overload receives zero/all-one/sign/alternating/byte patterns plus
each single-bit and single-clear-bit value. Incoming high bits check masking.
An additional function combines all 132 declarations through reversal, byte
swap and population count, testing independent cache identities. It takes
323 instructions and sums prefix population counts; all-zero/all-one inputs
have independent expected results 0/2080. It receives 258 inputs.
All **743,134 comparisons** are bit-exact native LLVM comparisons.

Controls check 132 poison results, 132 selected undef rejections, 264 execution-
budget/integer-API rejections, 21 metadata corruptions, nine name/width mismatches
and fifteen result corruptions. Every result comparison checks kind, width,
value, poison and exact steps. LLVM/JIT/native code is not sanitizer-instrumented.
The tool executes only its generated fixture. Source/bitcode, every comparison,
binaries, identities and logs belong in complete external evidence bundles.

This is scalar execution groundwork. No AIR shader, Metal device, GPU command
or application launch is qualified.

References: [LLVM population count](https://llvm.org/docs/LangRef.html#llvm-ctpop-intrinsic),
[bit reversal](https://llvm.org/docs/LangRef.html#llvm-bitreverse-intrinsics),
[byte swap](https://llvm.org/docs/LangRef.html#llvm-bswap-intrinsics).
