# Scalar funnel shifts and rotations

The mixed scalar interpreter accepts `llvm.fshl.iN` and `llvm.fshr.iN` at
every width N from 1 through 64. Three iN arguments supply the high half A,
low half B and unsigned shift amount S; the result is iN. The amount is masked
to iN before reducing modulo N. Left shifts extract the high half of the
shifted conceptual A:B concatenation; right shifts extract the low half.
Matching A and B give left/right rotation. Poison in any operand propagates,
including at shift zero; selected undef errors. The integer-only API retains
its existing no-call profile for scalar intrinsic calls. Vector calls are
supported through both scalar execution APIs as described below.

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
supported. The scalar profile rejects wider integers, malformed decimal
suffixes and AIR aliases; the vector profile follows below. Valid LLVM IR and
matching immutable indexes remain preconditions.

The fixed stack cache has 1384 entries: forty floating-overload slots and twenty-one
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

## Vector funnel shifts

Ordinary direct `llvm.fshl.vNiW` and `llvm.fshr.vNiW` calls support 1..16-lane
fixed integer vectors at widths i1..i64. All three arguments and the result
must have the identical vector type. Shift amounts are dynamic per lane, masked
to the lane width and reduced modulo W. Equal high/low inputs give rotations.
Poison in any of the three inputs propagates even at effective shift zero;
[LLVM also preserves this distinction when forming funnel shifts](https://llvm.org/docs/doxygen/InstCombineSelect_8cpp_source.html).
Any undef source lane fails, even if the result is discarded. Freezing sources
chooses zero for their indeterminate lanes; freezing a poison result chooses zero.
The helper returns independent snapshots and adds no normal-path allocation.

The mixed scalar, integer-only, void and memory execution APIs admit these
vector calls. Floating producers still require mixed execution. The direct-call
profile checks canonical names, exact integer shapes, all argument identities,
ordinary unflagged calling convention and declaration identity. Only harmless
function attributes are accepted; return/parameter attributes, including `immarg`,
reject. All blocks are checked before memory execution, including cold blocks.
Vector arguments/returns/PHIs/loads/stores, scalable/oversized vectors, i65 and
wider lanes, AIR aliases and flagged calls remain outside this profile.

Slots 4800..5823 belong to funnel-left and 5824..6847 to funnel-right. They add
2,048 independent width/count identities. Integer extrema add another 4,096;
abs adds 1,024, making 11,968 shared stack entries.
Each call costs one instruction, four lane counts of profiling work and one
shared construction slot. The existing 4,096-result and 1,000,000-work limits
remain. Declaration attributes are checked once per cached identity; each call
still validates all three sources. Untagged unary integer evaluators keep their
existing rejection of funnel operations.

`vector_funnel_intrinsics_test.v` checks 1,968,288 independent output-bit-selection
comparisons, including every i1..i5 triple, wider patterns, every width/count,
modulo/zero shifts, high-bit noise and snapshots. Another 626,688 poison/undef/
freeze checks cover all three inputs. The shared cache test covers all 11,968
identities; older units replace newly admitted name guards with vector-saturating-add guards.

`tests/ios/air-vector-funnel.v LLVM_AS FRESH_EXTERNAL_DIR` checks both directions
in 51,200 decoded shapes, five source forms and five construction paths through
memory and both scalar APIs. Bulk modules add 655,424 exact native lane values:
A exhausts i1..i16 encodings with paired B/shift patterns, and wider widths use
4,096 deterministic triples per direction. The bit-selection oracle checks all
bytes; native comparisons check defined extracted results with canonical padding,
while the VM receives high-bit noise. Native padding is not qualified.
Controls check both declarations in one function, every poison/undef operand
including zero shifts, declaration immarg refusal, cold widths, short budgets,
malformed metadata/sources, and exact shared work/storage limits through four APIs.

The software Metal fixture adds 752 dispatches across 144 kernels per runtime:
704 complete and 48 fail as expected. It covers both directions, rotations,
source/result freezes, snapshots, chains, deferred inputs, sparse bindings and
guard words. Four tail/i65 pipelines reject. Retained heap and GPU rendering
remain unqualified.

References: [LLVM funnel-left](https://llvm.org/docs/LangRef.html#llvm-fshl-intrinsic),
[LLVM funnel-right](https://llvm.org/docs/LangRef.html#llvm-fshr-intrinsic).
