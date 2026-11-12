# Bounded scalar LLVM intrinsic calls

The [mixed scalar interpreter](BINARY32.md) supports ordinary direct CALLs to
these LLVM declarations for scalar half (`.f16`) and float (`.f32`):

| Intrinsic | Behavior |
| --- | --- |
| `llvm.fabs` | Clear only the sign bit; retain every NaN payload/quiet bit. |
| `llvm.copysign` | Copy only the second operand's sign bit onto the first. |
| `llvm.floor` / `llvm.ceil` | Round toward negative / positive infinity. |
| `llvm.trunc` | Round toward zero, retaining zero's sign. |
| `llvm.round` | Round to nearest integer, ties away from zero. |
| `llvm.roundeven` / `llvm.rint` / `llvm.nearbyint` | Round to nearest integer, ties to even in LLVM's default environment. |
| `llvm.minimum` / `llvm.maximum` | Select the lesser / greater operand, propagate NaNs, and order -0 below +0. |
| `llvm.minimumnum` / `llvm.maximumnum` | Select the numeric operand if exactly one input is NaN, otherwise the lesser / greater value, ordering -0 below +0. |
| `llvm.minnum` / `llvm.maxnum` | Consistently choose the permitted `minimumnum` / `maximumnum` refinement, including for signaling NaNs. |
| `llvm.sqrt` | Correctly rounded square root, nearest/ties to even; retain negative zero and choose a quiet NaN for negative nonzero inputs. |
| `llvm.fma` | Fused multiply-add with one nearest/ties-to-even rounding after the exact product and addition. |
| `llvm.fmuladd` | Optional-fusion multiply-add; this interpreter consistently chooses fused evaluation. |
| `llvm.ldexp` | Scale half/float by a signed i32 power of two, with one final nearest/ties-to-even round. |
| `llvm.is.fpclass` | Return an i1 predicate for a constant ten-class mask, preserving signaling NaNs, signed zeros and subnormals. |

Math results keep the floating-point type; classification returns i1.
`scalar_intrinsics.v` manipulates integer
sign/exponent/fraction bits; no host FP instruction, environment, libm or LLVM
dependency participates in production. Signed zeros and infinities retain
their IEEE results. Rounding NaNs choose the existing preferred positive quiet
NaN; `minimum`/`maximum` also choose that NaN if either input is NaN, including a signaling
NaN. Number-preferring extrema choose it only when both inputs are NaNs.
Their finite results are exact input bits, with negative zero selected by
`minimum` and positive zero by `maximum` when zero signs differ.
`fabs`/`copysign` preserve payload and signaling bits. Selected undef
errors and poison operands propagate. Dynamic/constrained FP environments,
exception flags and errno are not part of this profile.

Square root normalizes the integer significand and makes its exponent even,
then computes an integer root and remainder of an at-most-54-bit radicand.
The restoring calculation takes exactly 27 steps. The root carries three
extra fraction bits; a nonzero remainder supplies sticky information for one
final rounding in the existing half/float packer. Negative finite values,
negative infinity and either NaN class choose the preferred quiet NaN.
Positive infinity and both zero signs retain their bits. Positive subnormal
inputs are normalized exactly; every nonzero finite root is normal.

Admission verifies the exact reserved name, scalar signature, arity, return/
argument types, direct declaration identity, external linkage, ordinary calling
convention and address space zero. The callee is checked against the constant
pool declaration record and is never read as a runtime pointer. Intrinsics
must be declarations. Calls require the plain explicit-type bitcode header,
zero fast-math flags and no call-site attribute list. Tail/notail/musttail,
indirect/defined/unknown callees, bundles, invoke/callbr and other precisions/
vector overloads reject, including in unvisited blocks. AIR-named intrinsics
are not aliases for these LLVM names.

Declaration attributes admit only function-level `nounwind`, `readnone`,
`readonly`, `speculatable`, `willreturn`, `nofree`, `nosync`, `nocallback`,
`nocreateundeforpoison` and `memory(none)` (bitcode memory versions 0/1/2).
Except classification's mask `immarg`, return/parameter, string/type,
`strictfp`, other memory effects and unknown
attributes reject. Attribute-list/group scans share a 1,000,000 record/attribute
validation budget. A 232-entry fixed stack cache validates each admitted
declaration once per run and rejects duplicate reserved declarations. There
are no new owned execution arrays; the existing three temporary arrays and
their cleanup remain unchanged. Each intrinsic CALL costs one executed
instruction, without recursion or host function invocation. Valid LLVM IR and
matching immutable indexes remain preconditions; this is not a full verifier.
The integer-only entry point still rejects floating point and all calls.

[Scalar FMA](SCALAR-FMA.md) adds a ternary call with exact fixed-stack integer
accumulation, gradual underflow and rounding after cancellation. Its separate
maintained checker compares 1,980,544 results across both precisions, including
`fmuladd` against the permitted fused result and separate native-choice diagnostics.
[Power-of-two scaling](SCALAR-LDEXP.md) admits the exact `.f16.i32` and `.f32.i32`
names, with a floating first argument/result and a signed i32 second argument.
[Floating classification](SCALAR-FPCLASS.md) returns i1 from a half/float input
and an immediate i32 mask. Only this intrinsic admits the exact parameter-two
`immarg` declaration attribute; the mask is independently checked at every call.
[Integer bit operations](SCALAR-INTEGER-INTRINSICS.md) add unary `ctpop` and
`bitreverse` at i1..i64 and `bswap` at i16/i32/i48/i64, also through the mixed
scalar entry point. Their cache keys reserve three independent 64-width ranges
after the forty floating-overload slots. Unsupported byte-swap widths reject.

`scalar_intrinsics_test.v` checks 28 exact bit/rounding/special-value patterns,
unsupported names/widths, canonical attributes, memory versions, and rejecting
memory/strictfp/string/return/parameter/missing/budget cases.
An additional 264 exact extrema results check all six extrema operations, both precisions and argument
orders, including signed zeros, subnormals, infinities and quiet/signaling NaNs.
`minimumnum`/`maximumnum` suppress either quiet or signaling NaN when the other
operand is numeric, preserving that numeric operand's exact bits. Two NaNs
choose the preferred quiet NaN. `minnum`/`maxnum` consistently choose the same
number-preferring behavior. LLVM explicitly permits this refinement; it can
otherwise propagate a signaling NaN. AIR aliases remain unsupported.
Square-root units check 32 exact values, unary/name/width guards and 327,680
independent multiplication inequalities for root/remainder results, including
exact squares and neighbors near the 54-bit bound.

`tests/ios/air-scalar-intrinsics.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates
44 functions: seventeen primitives, three chains and two bounded loops for each
precision. Half inputs cover all 65,536 encodings in every case. Float inputs
cover 32 fixed edges, 65,536 mixed-bit inputs and 65,536 signed midpoint/neighbor
inputs across exponents 0..22. Extrema additionally exhaust every half encoding
against sixteen boundary peers in both argument orders, and all 32-by-32 float
edge pairs. Square root also receives 196,608 neighbors of squared exact
float-root midpoints, formed independently using u64 products and shifts across
the normal exponent range. Scaling adds 2,097,152 boundary pairs against sixteen
signed exponent values. It compares **19,208,896 results**: 17,718,326 bit-exact
results and 1,490,570 rounding/arithmetic NaN-class cases. Non-math
operations preserve NaN bits exactly. Primitive CALL/return results cost two
instructions; the sign/rounding chain costs four and the extrema/square-root
chains three. The square-root loop feeds back its result through a PHI.
Scaling wrappers also cost three instructions, including their exponent cast.
Nine rejecting fixtures, three poison results, forty-eight extrema poison/undef
controls, four square-root poison/undef controls, lazy select, budget/integer
isolation, eight call-metadata corruptions,
two declaration-attribute corruptions, five result corruptions and six
distinguishing host-rounding controls plus four square-root host-rounding
controls pass. Scaling adds eight poison/undef, two exponent-type and four
host-rounding controls. Square-root controls use sqrt(2) under upward rounding and
sqrt(5) under downward rounding, where nearest-mode results differ in each
precision. Native calls run only in the
default environment; LLVM/JIT/native code is not sanitizer-instrumented.

For `minnum`/`maxnum`, production comparisons deliberately call native
`minimumnum`/`maximumnum` to qualify the chosen refinement. A separate
`legacy-native.tsv` records 2,560 actual native legacy results over both edge
matrices, distinguishing permitted sNaN propagation from backend signed-zero
violations. Neither category relaxes production's exact numeric bits or zero
signs. Twenty-four controls reject flags/arity, insufficient budgets, integer
entry-point use and flipped zero signs for the four new overloads.
Two additional chains mix all four legacy/refined declarations, verifying
distinct cache identities and five executed instructions per chain.

The host LLVM backend's half `copysign` quiets signaling NaNs: input `0x7c01`
with a negative sign produces `0xfe01` where the contract requires `0xfc01`.
The native observation and initial failing corpus are retained. This one case
uses a defined native LLVM integer bit-operation reference for all 65,536
inputs; the remaining 19,143,360 comparisons use native floating-point wrappers.
The reference does not relax payload checks or change production semantics.
IR/bitcode, every comparison, native diagnostic, assembler/JIT/fenv identities
and logs are preserved outside Git. The tool executes only its own fixture.

This executes a scalar prerequisite. It does not execute an AIR shader, create
a Metal device, submit GPU work or qualify an iOS application launch.

References: [LLVM fabs](https://llvm.org/docs/LangRef.html#llvm-fabs-intrinsic),
[copysign](https://llvm.org/docs/LangRef.html#llvm-copysign-intrinsic),
[rounding](https://llvm.org/docs/LangRef.html#llvm-roundeven-intrinsic),
[minimum](https://llvm.org/docs/LangRef.html#llvm-minimum-intrinsic),
[maximum](https://llvm.org/docs/LangRef.html#llvm-maximum-intrinsic),
[minimumNumber](https://llvm.org/docs/LangRef.html#llvm-minimumnum-intrinsic),
[maximumNumber](https://llvm.org/docs/LangRef.html#llvm-maximumnum-intrinsic),
[legacy minnum](https://llvm.org/docs/LangRef.html#llvm-minnum-intrinsic),
[legacy maxnum](https://llvm.org/docs/LangRef.html#llvm-maxnum-intrinsic),
[square root](https://llvm.org/docs/LangRef.html#llvm-sqrt-intrinsic),
[default environment](https://llvm.org/docs/LangRef.html#floating-point-environment),
[memory attribute decoding](https://github.com/llvm/llvm-project/blob/main/llvm/lib/Bitcode/Reader/BitcodeReader.cpp).
