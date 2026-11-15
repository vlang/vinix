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
integer-only API rejects these scalar intrinsic calls. Integer-only functions
using scalar calls execute through `run_scalar_function`. The vector population
count, bit reversal and byte swap described below also execute through `run_integer_function`.

Production uses unsigned shifts, masks and additions in loops of at most 64
iterations (eight for byte swap), without host intrinsics, LLVM, floating point
or new allocation. Intrinsic CALL costs one executed instruction; primitive
CALL/return takes two. Name recognition inspects bytes directly without a
substring allocation or permissive numeric parser. Only canonical decimal
suffixes 1..64 are admitted; leading zeros, signs, trailing suffixes, scalar calls
with vector arguments, floating types, AIR aliases and unsupported byte-swap
widths reject.

The [existing direct-call profile](SCALAR-INTRINSICS.md) checks declaration
identity, external linkage, signature/arity, default pointer address space,
ordinary calling convention, explicit-type header, zero fast-math flags and
no call-site attributes. The exact suffix must match the result and argument
integer type. Harmless function-level declaration attributes retain their
existing whitelist; parameter/return attributes, including `immarg`, reject
for these unary operations. All blocks are checked, including unvisited ones.
Valid LLVM IR and matching immutable indexes remain preconditions.

The fixed stack declaration cache has 1384 entries: forty floating-overload
slots followed by twenty-one independent 64-width integer ranges, including the
[leading/trailing zero counts](SCALAR-ZERO-COUNTS.md),
[funnel shifts](SCALAR-FUNNEL.md), [integer extrema](SCALAR-INTEGER-EXTREMA.md),
[integer absolute value](SCALAR-INTEGER-ABS.md),
[saturating arithmetic](SCALAR-SATURATING.md),
[saturating left shifts](SCALAR-SATURATING-SHIFT.md),
[bit extraction/deposition](SCALAR-BIT-PERMUTATION.md) and
[carry-less multiplication](SCALAR-CLMUL.md).
Only four slots
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

## Vector population count

Ordinary direct `llvm.ctpop.vNiW` calls accept fixed vectors of 1..16 lanes
and integer widths i1..i64, returning the identical vector type. Canonical
name, signature, argument/result identity, direct declaration, flags, calling
convention and attributes are checked before execution, including cold blocks.
Both mixed and integer-only execution APIs admit these integer calls. Floating
producers/classification still require mixed execution; scalar intrinsic calls
retain their existing policy. Vector arguments/returns, loads/stores, PHIs,
scalable vectors, widths above 64, counts above 16 and AIR aliases reject.

Each lane reuses the scalar integer population counter, masking the declared
width. Lane poison propagates; any undef lane errors even if the result is
discarded. Source freezes repair indeterminate inputs before counting. Result
freezes choose zero for poison. Results are independent snapshots and compose
with integer vector construction, comparisons and selects. A call costs one
step, two lane counts of profiling work and one shared construction slot.
The existing 4,096-result and 1,000,000-work limits apply.

Population count occupies shared vector declaration-cache slots 640..1663,
one per width/count pair. The cache now has 4,800 stack entries: 640 floating
identities, 1,024 population-count identities, 1,024 bit-reversal identities,
64 byte-swap identities, 1,024 leading-zero identities and 1,024 trailing-zero identities.
Declaration attributes are checked once per identity;
duplicate reserved declarations reject. Unary integer calls reject return/
parameter attributes, including `immarg`. The normal production lane path
adds no allocations. Retained heap has not been measured.

`vector_ctpop_intrinsics_test.v` checks 1,032,736 exact lane values with an
independent low-set-bit-clearing oracle, including every i1..i16 encoding,
wide patterns, single-set/clear bits, upper-bit noise and snapshots. Another
104,448 lane poison/undef/freeze checks and the shared cache unit cover all
1,024 new identities alongside the original 640.

`tests/ios/air-vector-ctpop.v LLVM_AS FRESH_EXTERNAL_DIR` generates and verifies
25,600 shapes across every width/count, five source forms and five construction
paths, exercising mixed scalar, integer-only and memory execution. Bounded
bulk modules compare 3,276,832 native LLVM lane values, exhausting narrow widths
and using 65,536 mixed patterns per wider width. The VM receives nonzero
padding bits; native loads receive canonical padding because the captured LLVM
legalizer can retain unused load bits in i1 vector operations. Both results
must agree with the independent width-masked oracle. The failed initial noisy
native comparison remains in the evidence bundle.

Controls cover strict undef/discards, poison/freeze, snapshots, chains,
signatures, declaration attributes, duplicates, all 1,024 overloads in bounded
cache groups, changing-source loops, floating/integer API isolation, malformed
metadata, exact budgets and shared storage/work boundaries through all four
APIs. A combined 1,024-declaration module must reject the shared attribute-work
limit through both scalar APIs. The software Metal fixture adds 216 dispatches
per runtime across 64 kernels and eight representative widths, including deferred writes, sparse
bindings, pipeline reuse, guard bytes and expected failures. These synthetic
CPU checks do not qualify an Apple shader, GPU frame or application launch.

## Vector bit reversal

Ordinary direct `llvm.bitreverse.vNiW` calls admit fixed vectors of 1..16
integer lanes, widths i1..i64. Bit M of each lane moves to bit W-M-1; lane
order and the exact vector type remain unchanged. The implementation shares
canonical integer-overload parsing, type/source validation and lane-state
handling with population count, then reuses the scalar integer bit reverser.
Both families execute through the mixed, integer-only, void and memory APIs.
The existing call flags, attributes, cold-block validation and unsupported
vector-profile restrictions apply. Scalable vectors, i65 and wider types,
counts above 16 and AIR aliases reject.

Reversal adds cache slots 1664..2687 without moving older identities. Each
call takes one step, two lane counts of profiling work and one construction
slot. All existing vector-result, vector-work and attribute-work limits remain.
Poison propagates per lane, any undef lane fails even when discarded, source
freezes repair inputs and result freezes choose zero for poison. Results are
independent snapshots. The normal lane path adds no allocation; retained
heap has not been measured.

`vector_bitreverse_intrinsics_test.v` compares 1,032,736 exact lane values with
the standard-library 64-bit reverser shifted to the declared width, independently
of the production shift loop. It additionally checks 705,024 reversal
involutions, 104,448 lane-state cases, high-bit masking, snapshots and guards.
The shared cache unit covers all 4,800 identities.

`tests/ios/air-vector-bitreverse.v LLVM_AS FRESH_EXTERNAL_DIR` checks every
width/count through 25,600 decoded shapes and 3,347,424 exact native LLVM
comparisons. Its 606 controls include 320 mixed-family API cases: reversal
twice restores the input and reversal preserves population count, with both
call orders through both scalar APIs. It also checks attributes, all overloads
in bounded cache groups, exact budgets and shared limits through all four
APIs. VM inputs retain noisy high bits; native loads receive canonical padding,
following the population-count reference qualification. Native padding behavior
is not qualified. The software Metal fixture adds 216 dispatches per runtime
across 64 kernels and eight representative widths, including nontrivial double
reversal, guards, deferred writes and expected failures.

## Vector byte swap

Ordinary direct `llvm.bswap.vNiW` calls accept 1..16 fixed lanes at widths
i16, i32, i48 and i64. Each lane reverses its bytes while preserving bit order
within each byte and the order of lanes. These are the even-byte widths in the
interpreter's i1..i64 range. Scalar implementation, canonical integer-overload
parsing, type/source validation and lane execution are shared with the existing
integer operations. Both scalar execution APIs, void and memory execution admit
these vector calls. The normal lane path adds no allocation.

Byte swap adds cache slots 2688..2751 without moving the preceding 2,688 slots.
All existing call, signature, flag, attribute and cold-block guards apply.
Poison propagates per lane, any undef lane fails even when discarded, source
freezes repair inputs and result freezes choose zero for poison. Each call
costs one step, two lane counts of profiling work and one shared construction
slot. Existing result/work limits remain. Other widths, oversized/scalable
vectors, vector arguments/returns/loads/stores/PHIs and AIR aliases reject.

`vector_bswap_intrinsics_test.v` checks 130,048 exact values against the
standard-library 64-bit byte reverser shifted to the declared width, plus
52,224 involutions and 6,528 lane-state checks. It exhausts i16 and checks wide
patterns, individual set/clear bits, high-bit noise, snapshots and guards.
The shared cache unit covers all 4,800 identities. Older integer-vector units
replace their unsupported-byte-swap guards with unsupported funnel-shift-left
because byte swap is now admitted. Their positive value/state coverage remains.

`tests/ios/air-vector-bswap.v LLVM_AS FRESH_EXTERNAL_DIR` checks 1,600 decoded
shapes and 266,556 exact native comparisons: all i16 values, 65,536 patterns
per wider width, and composed cases across all 16 counts. Its 926 controls
include 320 population-count/involution cases and 320 byte-swap/bit-reversal
commutation cases through both scalar APIs and both call orders. It verifies
all 64 declarations together, attributes, budgets and exact shared storage/
work boundaries through all four APIs. A mixed floating predicate is widened
to i16 before byte swapping; integer-only execution must reject its floating
producer. A valid LLVM i80 byte swap in a cold block rejects before writes.
The software Metal fixture adds 108 dispatches per runtime across 32 kernels,
including deferred writes, sparse bindings, double swaps, guards and expected
failures. Retained heap and GPU rendering are not qualified.

Vector `llvm.ctlz` uses slots 2752..3775 and `llvm.cttz` uses slots 3776..4799.
Both use a call-local constant i1 poison
flag. The [leading-zero profile and qualification](SCALAR-ZERO-COUNTS.md#vector-leading-zero-count)
describe immediate validation, defined-zero/poison behavior and supported APIs.
The [trailing-zero profile](SCALAR-ZERO-COUNTS.md#vector-trailing-zero-count) records
its independent value/state coverage and native reference checker.

References: [LLVM population count](https://llvm.org/docs/LangRef.html#llvm-ctpop-intrinsic),
[bit reversal](https://llvm.org/docs/LangRef.html#llvm-bitreverse-intrinsics),
[byte swap](https://llvm.org/docs/LangRef.html#llvm-bswap-intrinsics).
