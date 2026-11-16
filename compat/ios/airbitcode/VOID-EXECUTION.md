# Void-return scalar execution

`IRTypedProgram.run_void_function` executes defined ordinary functions whose
return type is void. Arguments and instructions use the existing mixed scalar
profile: i1..i64, binary16 and binary32 arithmetic, supported intrinsics and
bounded control flow. It returns `IRVoidRun{steps: ...}`. `ret void` costs one
step and reads no value. Nonvoid signatures reject; integer/scalar result APIs
continue to reject void signatures. Argument counts, function attributes,
calling conventions, decoded operands, poison branch conditions, selected undef,
unreachable instructions and step budgets retain their existing checks.

Valid LLVM IR and matching immutable indexes remain preconditions. This API
does not add memory instructions, pointer arguments, kernel ABI binding,
pipeline construction or dispatch. Discarded poison arithmetic has no returned
value; poison consumed as a branch condition still rejects.

Fixed-vector insertion, shuffling, freeze, comparisons, integer binary operations,
scalar/vector-conditioned select and lane extraction follow the shared
scalar/memory rules:
1..16 i1..i64/half/float lanes, scalar unsigned indices, preflight of every
lane and a bounded per-function lane-work budget. A discarded poison result is
permitted; selected undef still errors at extraction even when its result is
unused. Insertions preserve earlier snapshots and per-lane poison/undef;
invalid indices poison the new vector and a later insertion may repair a lane.
At most 4,096 static vector construction results share one execution-owned
storage array.
Vector freeze preserves defined lanes and independently chooses zero for
poison/undef lanes. Earlier snapshots retain their state. Vector arguments,
PHIs and loaded vectors remain unsupported. Whole-vector
select copies the chosen arm's lane states; poison conditions poison the whole
result and undef conditions reject. Discarding a selected undef vector is
permitted until an instruction attempts to extract an undef lane.
Per-lane select accepts a matching fixed i1 vector condition. Poison condition
lanes poison only their corresponding result lanes; any undef condition lane
rejects at select, including discarded results. A frozen condition chooses zero
for its poison/undef lanes. Condition sources follow the same earlier-construction
rules as arms and add their lane count to validation work. Arms unused by all
defined condition lanes are not read. Selections share one-step execution and
snapshot storage with whole-vector selects.
Vector comparisons produce fixed i1 masks with per-lane poison propagation.
Integer comparisons include all predicates and `samesign`; half/float include
all ordered/unordered predicates. Any undef operand lane rejects at comparison,
including discarded results. Constant FP false/true predicates follow the
existing scalar policy and do not read their operands, after full preflight.
Each comparison costs one step and charges both sources and result to lane work.
Its snapshot shares construction storage and can feed any supported vector
operation, including another comparison or a per-lane select.
Vector integer binary operations support all thirteen scalar opcodes at i1..i64
and all counts 1..16. Arithmetic/exact/disjoint flags and oversized shifts
produce per-lane poison. Any undef lane rejects, even for discarded results.
Poison division/remainder, zero divisors and signed-minimum/-1 reject the whole
executed instruction under the existing scalar policy. Freezing the result
does not suppress those errors. One executed step, both source counts plus
result lane work, and the existing construction array are shared with the
other vector operations.

Fixed integer vectors support `trunc`, `zext` and `sext` across i1..i64
with unchanged lane count (1..16). Truncation requires a narrower destination;
extensions require a wider one. Truncation `nuw`/`nsw` and zero-extension
`nneg` follow the scalar promise rules, producing poison only in affected
lanes. Complete literal/earlier-construction sources are checked, including
inactive blocks. Any undef source lane rejects at the cast, even for discarded
results. Freezing a source repairs indeterminate lanes; freezing a result does
not suppress earlier evaluation errors. Results retain independent snapshots
and feed other supported vector operations, including another integer cast.
Each cast costs one executed step and charges source plus result count to
shared lane work. Results share the existing 4,096 static construction slots
and execution-owned allocation. Integer, mixed, void and memory APIs use the
same integer-vector rules. Pointer casts, arguments/returns,
PHIs, loads/stores, scalable vectors and
widths beyond i64 remain unsupported. `tests/ios/air-vector-integer-cast.v`
checks every width pair and flag variant against native LLVM, explicit freeze
choices and poison failures, plus source/result freezing, composition, loop
reuse, unsupported profiles and exact shared storage/work limits.

Fixed integer vectors also support unflagged `bitcast` between any two
1..16-lane i1..i64 shapes with equal total bit width. On little-endian layouts,
lane zero supplies the lowest packed bits, without padding for non-byte widths.
Packing, splitting and boundaries crossing source lanes preserve all defined
bits. A destination lane is poison if any overlapping source lane is poison;
any undef source lane rejects the executed cast, including discarded results.
Source freeze chooses zero for indeterminate source lanes; result freeze clears
whole poison destination lanes and cannot hide an earlier undef error. Results
retain independent snapshots and share existing construction storage, step and
source-plus-result work budgets in integer, mixed, void and memory APIs.
Big-endian lane reshaping, pointer casts, scalable vectors
and widths beyond i64 remain unsupported.
`tests/ios/air-memory-vector-integer-bitcast-index.v` checks native LLVM bits,
scalar APIs, ordinary/prepared memory, address preflight and composed graphs;
the unit suite checks every supported shape pair. See
[LLVM bitcast semantics](https://llvm.org/docs/LangRef.html#bitcast-to-instruction).

Fixed vectors support raw unflagged `bitcast` between any equal-total-width
1..16-lane shapes using i1..i64, half or float elements. This includes integer/FP
packing and splitting, half/float reshaping and same-category identity casts.
Lane reshaping requires a little-endian layout; lane zero occupies the lowest
packed bits, with no padding at non-byte boundaries. Integer-only execution
continues to reject floating lanes. Mixed, void and memory APIs preserve every
raw bit, including signed zero, NaN signs/payloads and signaling NaNs, without
floating arithmetic or quieting. A destination lane is poison if any overlapping
source lane is poison. Any undef source lane rejects the executed cast, even
for discarded results. Source freeze repairs individual input lanes; result
freeze clears entire poison destination lanes and cannot suppress earlier
errors. Independent snapshots compose with supported arithmetic, comparison,
select, insertion, shuffle, extraction and other bitcasts. A round trip through
wider lanes can spread poison to previously defined neighboring source lanes.
Each cast costs one executed step and source plus result lane work, sharing
the existing 4,096 construction slots and execution-owned array. Validation
checks complete sources, including inactive blocks. Existing memory argument,
load and store profiles remain separate; floating dependencies remain excluded
from pure address graphs. Pointer casts, other floating
formats, scalable vectors, vector returns and PHIs remain unsupported. Scalar
and void APIs continue to exclude vector arguments.
`tests/ios/air-vector-reshape-bitcast.v` checks all supported shape pairs that
include half/float, exact native LLVM bits, payloads, poison overlap, freezes,
ordinary/prepared memory write ordering, scalar results, snapshots, composition,
loop reuse and exact shared limits. `tests/ios/air-vector-bitcast.v` retains the
complete half-encoding and float-pattern checks for the original same-shape
integer/FP casts.

Scalar/vector bitcasts also support unflagged casts between a scalar and a
fixed 1..16-lane vector of equal total width, up to 64 bits, using i1..i64,
half and float. These casts require little-endian layouts, including one-lane
containers. Lane zero supplies the lowest packed bits without byte padding.
Raw floating bits retain NaN payloads and signs without floating arithmetic.
Scalar poison spreads to every split lane; any poison input lane poisons the
packed scalar. Executed undef inputs reject eagerly, even for discarded
results. Source freeze repairs individual vector lanes or the whole scalar;
result freeze clears entire poison result lanes and cannot hide an earlier
undef error. A scalar round trip can therefore spread poison to other lanes.
Each cast costs one executed step and source plus result lane work. Only a
vector result consumes a shared construction slot; scalar packs use existing
scalar result storage. Integer-only execution accepts integer shapes; mixed,
void and memory APIs also accept half/float shapes. Pure integer versions may
feed bounded address graphs; floating dependencies remain excluded. Existing
argument, load/store, return and PHI restrictions remain in force. `tests/ios/air-scalar-vector-bitcast.v` checks
every shape in both directions against native LLVM and an independent bit
model, freeze/poison/undef behavior, ordinary/prepared write ordering, strict
budgets, loop reuse, metadata guards and shared work/storage boundaries.

Pure integer scalar/vector bitcasts can feed memory offsets through supported
scalar expressions and vector lane projections, including arguments, literals,
freeze, insertions, shuffles, arithmetic and selects. A scalar split shares its
complete result table across selectors. Packing observes every input lane
before producing a scalar; a later select or freeze cannot hide undef errors.
Scalar undef requires a direct source freeze. Every GEP root is validated
before writes, including inactive blocks and roots reused after freeze. Loaded
values, PHIs and floating dependencies remain outside pure address graphs.
Existing 256-node and 32-level bounds count all sources and cached heights.
`tests/ios/air-memory-scalar-vector-bitcast-index.v` checks every integer shape
in both directions, native LLVM bits, nonmutating validation, ordinary/prepared
write ordering, freeze/poison/undef controls and exact graph boundaries.

Fixed 1..16-lane half/float vectors support unflagged `fpext`
(half to float) and `fptrunc` (float to half), retaining the lane count. They
reuse scalar integer-based conversion: widening is exact for finite values;
narrowing rounds nearest/ties-to-even with gradual underflow and signed
zero/infinity. Conversion NaNs choose the preferred positive quiet NaN.
Poison remains local; any undef source lane rejects the executed cast, even
for discarded results. Freezing sources repairs indeterminate lanes; result
freezes do not suppress earlier errors. Complete supported literal/earlier
construction sources are validated, including inactive blocks. Results keep
independent snapshots and compose with other supported vector operations.
Each cast costs one step and source plus result lane work, sharing the
existing 4,096 construction slots and execution-owned array. Mixed, void and
memory APIs support these casts; the integer-only API rejects floating lanes.
Fast-math flags, other floating formats, reshaping, vector arguments/returns,
PHIs and loads/stores remain unsupported. `tests/ios/air-vector-precision.v` checks all half encodings, both
signs of every half midpoint and its neighboring float values, deterministic
float samples, NaN choices, snapshots, composition, guards and shared limits.

Fixed 1..16-lane integer vectors support unflagged `uitofp` and `sitofp`
to half or float, retaining the lane count. Source widths are i1..i64;
signed i1 true converts to -1. The existing integer-based scalar converters
round nearest/ties-to-even, independently of host rounding; half overflow
produces signed infinity. Poison stays local. Any undef source lane rejects
at the executed cast, including discarded results. Source freezes repair
indeterminate lanes; result freezes do not suppress earlier errors. Complete
supported literal/earlier-construction sources are validated, including
inactive blocks. Results retain independent snapshots and compose with
supported vector operations. Each cast costs one step and source plus result
lane work, sharing the existing 4,096 construction slots and execution-owned
array. Mixed, void and memory APIs support these conversions; the integer-only
API rejects floating lanes. Fast-math flags, `uitofp nneg`, other formats,
reshaping, vector arguments/returns, PHIs and loads/stores remain unsupported. `tests/ios/air-vector-int-float.v`
compares every source width with native LLVM, exhausts signed/unsigned i1..i16,
and checks rounding boundaries, poison/undef, freezing, composition, loops,
unsupported profiles and shared storage/work limits.

Fixed 1..16-lane half/float vectors support unflagged `fptoui` and `fptosi`
to i1..i64, retaining the lane count. Conversion truncates toward zero,
independently of host rounding. NaNs, infinities and values whose truncated
result is outside the integer range produce poison only in affected lanes.
Negative fractions between -1 and zero convert to unsigned zero; fractional
values just below a signed minimum remain valid if truncation brings them
into range. Signed i1 has range -1..0. Any undef source lane rejects at the
executed cast, even for discarded results. Source freezes repair indeterminate
inputs, but do not repair numeric invalidity; result freezes repair produced
poison without suppressing earlier undef errors. Complete supported literals
and earlier constructions are validated, including inactive blocks. Independent
snapshots compose with integer operations and existing vector casts. Each cast
costs one step and source plus result lane work, sharing the existing 4,096
construction slots and execution-owned array. Mixed, void and memory APIs
support these conversions; the integer-only API rejects floating sources.
Nonzero flags, other formats, reshaping, vector arguments/returns, PHIs and
loads/stores remain unsupported. `tests/ios/air-vector-float-int.v` uses defined
native saturation and separate range tags, including truncation before range
checks, without executing invalid native casts.

Fixed 1..16-lane half/float vectors also support ordinary direct
`llvm.fptosi.sat.vNiW.vNf16`/`vNf32` and `llvm.fptoui.sat.vNiW.vNf16`/`vNf32`
calls, with matching source/result lane counts and i1..i64 results. Conversion
truncates toward zero and clamps to the signed or unsigned destination limits;
all NaNs become zero, infinities clamp and negative unsigned inputs become
zero. Signed i1 has range -1..0. Finite numeric inputs never introduce poison;
source poison remains lane-local, while any undef source lane rejects the
executed call, including discarded results. Source freezes repair indeterminate
inputs; result freezes repair source poison without hiding earlier errors.
Results retain independent snapshots and compose with existing integer/vector
operations. Mixed, void and memory APIs share one executed step, source plus
result lane work and the existing 4,096 construction slots. Integer-only
execution and pure address graphs continue to reject floating sources. Other
floating formats, scalable vectors, mismatched counts, fast-math/tail calls,
call-site attributes and malformed names/signatures reject.
The two-width conversion family adds 4,096 distinct declaration-cache entries
after all 18,112 previous entries, preserving their identities. The two existing
fixed per-profile cache arrays grow by 32 KiB each on the qualified 64-bit host;
no new managed storage or owner is added. Integer arithmetic reuses the scalar
saturation evaluator independently of host floating rounding.
`tests/ios/air-vector-saturating-cast.v` compares direct LLVM vector calls and
an independent rational oracle, all half encodings at common widths, ordinary/
prepared memory write ordering, scalar results, overload identity, malformed
calls, poison/undef/freezes, composition, loops and shared limits.
See [LLVM saturating conversion semantics](https://llvm.org/docs/LangRef.html#llvm-fptosi-sat-intrinsic).

Fixed 1..16-lane half/float vectors support direct unflagged calls to
`llvm.fabs.vNf16`/`vNf32` and `llvm.copysign.vNf16`/`vNf32`. Fabs clears
the sign bit; copysign copies only the second operand's sign bit. Every other
bit is preserved, including NaN payloads and signaling bits; no NaN quieting
occurs. Poison remains local to each lane. Any undef source lane rejects
at the executed call, even for discarded results. Source freezes repair
indeterminate inputs; result freezes do not suppress earlier undef errors.
Both copysign sources must be supported complete literals or earlier
constructions. Validation includes inactive blocks. Independent results compose
with existing vector operations and raw bitcasts. Each call costs one step;
fabs charges two lane counts and copysign three to shared work, reusing the
existing 4,096 construction slots and execution-owned array. Mixed, void and
memory APIs support these calls; the integer-only API rejects floating lanes.
Canonical overload names, exact signatures and direct declaration identity
are checked. Harmless declaration attributes use the existing bounded scanner
once per overload, with a separate 64-entry duplicate-declaration cache.
Fast-math flags, tail calls, call-site attributes, unsupported declaration
attributes, other vector intrinsics/formats, vector arguments/returns, PHIs
and loads/stores remain unsupported. `tests/ios/air-vector-sign-intrinsics.v`
checks exact native LLVM bits, every half encoding, all lane counts, poison/undef,
freezing, snapshots, composition, malformed calls/declarations and shared limits.

Fixed 1..16-lane half/float vectors also support unflagged `fadd`, `fsub`,
`fmul`, `fdiv` and `frem`, using the integer-based scalar math at the lane
precision. Rounding is nearest/ties-to-even with gradual underflow. Signed
zeros and infinities retain IEEE results. Zero divisors and invalid FP
arithmetic yield infinity or the preferred positive quiet NaN, without
poison or a host trap. Arithmetic NaNs choose `0x7e00` or `0x7fc00000`;
copying operations retain their bits. Poison propagates per lane, including
division/remainder. Any undef operand lane rejects at the binary instruction,
including discarded results; freezing sources first repairs indeterminate
lanes, while freezing the result cannot suppress prior evaluation errors.
Both complete sources are checked before execution, including inactive blocks.
Each operation costs one executed step and charges both source counts plus
result count to the shared lane-work budget. Results use the existing bounded
snapshot allocation and may feed any supported vector operation. Fast-math
flags, other formats, scalable vectors, vector PHIs/arguments/returns and vector
loads/stores remain unsupported. `tests/ios/air-vector-float-binary.v` checks
native LLVM values with arithmetic NaNs normalized, exact copied bits,
poison/undef, freezing, composition, loop reuse, rejected profiles and exact
shared storage/work boundaries. Its sweep covers every half left encoding,
permuted right encodings, deterministic float pairs and complete edge grids.

Fixed 1..16-lane half/float vectors support unflagged `fneg`, from literals
or earlier supported constructions. It flips only the sign bit, including
signed zeros, preserving NaN quiet/signaling bits and payloads. Poison is local to
each lane; any undef source lane rejects at evaluation, including discarded
results. Freezing a source repairs indeterminate lanes before negation;
freezing a result does not suppress an earlier undef error. New results
retain independent snapshots and feed further negation, insertion, shuffle,
freeze, comparison, select or extraction. Each executed negation costs one
step. The source and result lane counts charge the shared 1,000,000-unit
validation budget, and results share the existing 4,096 static construction
slots and execution-owned allocation. Preflight validates complete sources
and inactive blocks. Fast-math flags, other lane formats, scalable vectors,
vector arguments/returns, vector PHIs and vector loads/stores remain outside
this bounded profile. `tests/ios/air-vector-fneg.v` checks exact LLVM values,
poison/undef policy, source/result freezing, snapshots, loop slot reuse,
composition, rejected profiles and exact/exceeded storage/work limits.

`tests/ios/air-constant-extract.v` checks successful discards, indeterminate
lanes and the whole-function work limit through this API.
`tests/ios/air-vector-insert.v` also checks the whole-function insertion storage
and shared insertion/extraction work limits before execution.
`tests/ios/air-vector-shuffle.v` also checks exact and exceeded combined
construction/storage and lane-work limits, including successful void execution.
`tests/ios/air-vector-freeze.v` checks successful discarded vector freezes and
the combined construction/storage and lane-work boundaries through this API.
`tests/ios/air-vector-select.v` also checks combined construction/storage and
lane-work boundaries through this API, with selects among the constructions.
`tests/ios/air-vector-lane-select.v` checks the same limits with vector conditions,
including their additional lane work and scalar-loop slot reuse.
`tests/ios/air-vector-compare.v` also checks exact/exceeded shared limits with
comparison results and their complete source/result lane-work charges.
`tests/ios/air-vector-binary.v` checks the same limits with integer binary
results, including rejected discarded undef and division/remainder operations.

The maintained serialized-bitcode check is `tests/ios/air-void-execute.v`.
Build it with the repository's V module path, then run its executable with
`LLVM_AS FRESH_EXTERNAL_DIR`. It assembles fixtures with llvm-as, parses them
through the production readers and checks 641 executions against explicit
path/step expectations. This is not a native-JIT result comparison: void
functions in this profile have no observable output besides interpreter steps.
