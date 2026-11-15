# Scalar signed and unsigned integer extrema

The mixed scalar interpreter accepts `llvm.smin.iN`, `llvm.smax.iN`,
`llvm.umin.iN` and `llvm.umax.iN` for every N from 1 through 64. Each takes two
iN arguments and returns iN. Signed operations select the smaller/larger
two's-complement value; unsigned operations select the smaller/larger bit
pattern. The chosen input's exact masked bits are returned. Equal inputs agree
in either argument order. Poison in either operand propagates; selected undef
errors. The integer-only API retains its existing no-call profile for scalar
intrinsic calls. Vector calls are admitted through both scalar APIs below.

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
including `immarg`, reject for these operations. In the scalar profile, wider
integers, malformed decimal suffixes and AIR aliases reject. Valid LLVM IR and matching
immutable indexes remain preconditions.

The fixed stack cache has 1384 entries: forty floating-overload slots and twenty-one
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

## Vector integer extrema

Ordinary direct `llvm.smin.vNiW`, `llvm.smax.vNiW`, `llvm.umin.vNiW` and
`llvm.umax.vNiW` calls support fixed 1..16-lane integer vectors at widths i1..i64.
Both arguments and the result must have the identical vector type. Signed
operations compare two's-complement values, including i1 values -1 and 0;
unsigned operations compare bit patterns. Results retain the chosen masked bits.
The existing scalar evaluator compares sign-flipped unsigned keys, avoiding
signed casts and overflowing signed arithmetic. No normal-path allocation is added.

Poison propagates per lane from either input. Any undef source lane fails even
when a result is discarded. Source freezes choose zero for indeterminate lanes;
result freezes choose zero for poison. Results are independent snapshots. Both
scalar execution APIs, void and memory execution admit these calls. Floating
producers retain their mixed-only policy. The direct-call checks require exact
canonical names, shapes, signatures, declaration identities and ordinary flags/
calling convention. Each call validates both sources. Return/parameter attributes,
including `immarg`, reject; harmless function attributes remain allowed. Cold
unsupported blocks reject before memory writes. Vector arguments/returns/PHIs/
loads/stores, scalable/oversized vectors, i65/wider lanes and AIR aliases remain
outside this profile.

The four families add distinct 1,024-entry width/count ranges: signed minimum
6848..7871, signed maximum 7872..8895, unsigned minimum 8896..9919 and unsigned
maximum 9920..10943. Abs adds 1,024, saturating add/sub adds 4,096 and saturating shifts add 2,048; the
shared declaration cache now has 18,112 stack entries.
Attributes are checked once per declaration/identity. Each call costs one step,
three lane counts of profiling work and one shared construction slot. The
4,096-result and 1,000,000-work limits remain unchanged.

`vector_integer_extrema_test.v` checks 4,087,168 independent comparisons using
safe signed-value reconstruction and direct unsigned comparisons, including
all i1..i8 pairs, 4,096 wider patterned pairs per operation, every shape, signed/
unsigned boundary values, high-bit noise, symmetry, idempotence and snapshots.
Another 835,584 poison/undef/freeze checks cover both sources. The cache test
checks all 18,112 identities. Older units update unsupported vector-smin names
to unsupported vector-carryless-multiply names while preserving positive coverage.

`tests/ios/air-vector-integer-extrema.v LLVM_AS FRESH_EXTERNAL_DIR` checks all
four operations in 102,400 decoded shapes through memory and both scalar APIs.
Bulk modules add 1,267,072 exact native lane comparisons, exhausting every i1..i8
pair and checking 4,096 wider pairs per operation. The independent oracle safely
reconstructs signed values; native comparisons check defined extracted results
with canonical padding while the VM receives high-bit noise. Native padding is
not qualified. Controls cover all four declarations in one function at every
width, both poison/undef operands, discarded results, repaired attribute baselines,
forbidden immarg groups, cold i65 blocks, exact budgets and shared work/storage
limits through four APIs. Attribute-refusal fixtures use full-sized output bindings.

The software Metal fixture adds 1,504 dispatches across 288 kernels per runtime:
1,408 complete and 96 fail as expected. Four families, equal inputs, source/result
freezes, snapshot changes, chains, deferred writes, sparse bindings and guards
are covered. Eight tail/i65 pipelines reject. Retained heap and GPU rendering
remain unqualified.

References: [LLVM signed minimum](https://llvm.org/docs/LangRef.html#llvm-smin-intrinsic),
[signed maximum](https://llvm.org/docs/LangRef.html#llvm-smax-intrinsic),
[unsigned minimum](https://llvm.org/docs/LangRef.html#llvm-umin-intrinsic),
[unsigned maximum](https://llvm.org/docs/LangRef.html#llvm-umax-intrinsic).
