# Void-return scalar execution

Scalar `air.popcount.i64` and `air.reverse_bits.i64` accept matching i64
input/results under the existing pure-call and state/work rules. Keys
2179..2180 append after AIR float identities; earlier scalar/vector keys
remain stable. The scalar cache has 2,181 entries.

Binary `air.fmin.vNf32` and `air.fmax.vNf32` accept matching fixed
1..16-lane float32 vectors and reuse the scalar AIR extrema evaluator per
lane. A numeric argument takes precedence over NaN; numeric ties retain the
first argument, including opposite signed zeros. Two NaNs yield the existing
positive canonical NaN. Both sources are observed: poison propagates locally
and any unfrozen undef lane refuses, even with a NaN peer. Existing freezes,
discarded poison, vector-PHI slots and cleanup are reused. Keys 61732..61763
append 32 AIR identities, separate from LLVM, for 61,764 vector entries;
scalar entries remain 2,181. LLVM zero ordering is preserved in mixed chains.
Exact binary signatures, both operand types and ordinary pure call metadata
remain checked, including after cache hits. One call uses one existing result
slot/step and the established source/result work charges. Invalid profiles
reject before writes; runtime state failures retain earlier stores. Half,
scalable, fast spellings and floating address projections remain excluded.

Ternary `air.fma.vNf32` accepts three matching fixed 1..16-lane float32
vectors. It reuses the existing fused evaluator: the exact product and addend
are combined before one nearest rounding with ties to even. All three sources
are observed. Lane poison propagates; any unfrozen undef source lane refuses,
including when another source is poison. Existing source/result freezes,
discarded poison, scalar extraction, vector-PHI slots and cleanup are reused.
Keys 61716..61731 append sixteen AIR identities, separate from LLVM, for
61,764 vector entries. Scalar entries remain 2,181. Exact signatures, all
three argument types and ordinary pure call metadata remain checked even
after cache hits. Work uses the established source/result charges, one result
slot and one executed step per call. Invalid profiles reject before writes;
runtime state failures preserve earlier stores. Half, fast spellings and
floating address projections remain excluded.

Fixed 1..16-lane float32 vectors accept unary `air.fabs.vNf32`,
`air.floor.vNf32`, `air.ceil.vNf32`, `air.trunc.vNf32`, `air.sqrt.vNf32`,
`air.round.vNf32` and `air.rint.vNf32`. These reuse the LLVM lane evaluators:
fabs preserves NaN payloads while arithmetic results canonicalize NaNs, round
takes half ties away from zero, and rint/sqrt round to nearest with ties to even.
Poison stays local to its lane; any unfrozen undef source lane refuses. Freezes,
discarded poison and scalar extraction retain existing rules. Exact vector
argument/result types, ordinary calls, pure attributes and duplicate checks
remain required, including after cache hits. Keys 61604..61715 append 112 AIR
identities, separate from LLVM, for 61,764 vector entries. Scalar entries stay
2,181. One call uses one existing result slot/step and the established vector
source/result work charges. The admitted AIR vector families are these unary
operations, FMA and float min/max. Half, scalable and fast overloads remain
excluded; floating address projections reject. Existing owners and cleanup
paths are reused. Invalid profiles reject before writes; runtime state
failures retain earlier stores.

Ternary `air.clamp.f32(x, low, high)` composes AIR `fmax(x, low)` then
`fmin(result, high)`, retaining numeric NaN preference and first-argument zero
ties. Ordered `low > high` produces poison, representing the Metal specification's
undefined bounds. NaN bounds do not trigger this comparison. All three input
states are observed: poison propagates and undef refuses until frozen. Domain
poison can be discarded, frozen or bypassed by a lazy select. Slot 2178 appends
one identity, for 2,181 scalar cache entries without moving earlier keys. Exact
float32 signatures, ordinary calls and pure attributes are required; other
widths/vectors and fast spellings remain excluded.

Binary `air.fmin.f32` and `air.fmax.f32` prefer the numeric operand to a NaN
and return the first argument on a numeric tie, including opposite signed zeros.
Separate appended AIR IDs retain this choice while preserving existing LLVM
extrema zero ordering. Two NaNs use the existing positive canonical NaN; the
software also treats signaling NaNs as quiet for numeric preference. The Metal
specification does not support signaling NaNs. Numeric subnormals retain their
bits. The wrapper normalizes inputs to float32 and reuses the existing number
evaluator outside zero ties, without host floating arithmetic. Keys 2176..2177
append two identities, within 2,181 scalar cache entries. Exact names, binary
signatures, each call/operand type, pure attributes, duplicate checks and existing
step/work/state/ownership rules remain. Invalid profiles reject before writes;
runtime value failures retain earlier stores. Half/vector overloads, fast
spellings and floating address projections remain excluded.

Ternary `air.fma.f32` accepts three float32 arguments and returns float32
through the existing exact fused multiply-add evaluator. It adds the exact
product to the addend before one nearest rounding with ties to even, independent
of the host rounding mode. Signed zeros, subnormals, infinities, canonical NaNs
and poison/undef/freezes retain the existing FMA rules. Slot 2175 appends one AIR
identity, within 2,181 scalar declaration-cache entries without moving earlier keys;
LLVM/AIR calls may coexist. Exact signatures, each call and all three operand
types are checked even after a cache hit. Unsupported declaration/call metadata
and bounds reject before writes. Runtime poison/undef value failures retain
earlier completed stores; result freeze and lazy selection keep existing rules.
Half/vector overloads, unknown AIR spellings and floating addresses remain excluded.

Unary `air.sqrt.f32`, `air.round.f32` and `air.rint.f32` reuse the existing
float32 root and rounding evaluators. Square root rounds once to nearest with
ties to even and preserves negative zero; negative nonzero inputs and NaNs
produce the established positive canonical NaN. Round takes half ties away
from zero; rint takes half ties to even. Results are independent of the host
rounding mode. Keys 2172..2174 append three identities, for 2,181 scalar cache
entries, preserving previous LLVM/AIR keys. Exact signatures, ordinary direct
calls, pure attributes, duplicate checks, state/freeze rules, prewrite validation
and existing work/step/ownership limits remain. Fast forms, other AIR widths,
vectors, floating addresses and calls in integer-only execution remain excluded.

Scalar `air.fabs.f32`, `air.floor.f32`, `air.ceil.f32` and `air.trunc.f32`
accept one float32 argument and return float32 through the existing evaluators.
`fabs` clears only the sign bit, including NaN payloads; the rounding operations
use the existing positive canonical NaN policy and preserve infinities and signed
zeros. Keys 2168..2171 append four AIR identities, for 2,181 scalar cache entries;
earlier LLVM and AIR identities remain stable and may coexist. Exact names,
signatures, pure declaration attributes and ordinary direct calls are required.
Poison, undef, freezes, executed-step budgets and result-slot ownership retain
their existing rules. Other AIR float overloads/vectors, floating address
projections and calls in integer-only scalar execution remain excluded.

Mixed scalar/void execution accepts binary i32 `air.mul_hi.s.i32` and
`air.mul_hi.u.i32` calls. They share the existing signed/unsigned multiply-high
evaluators, state propagation and one-step result slots. New keys 2166..2167
preserve earlier identities and permit LLVM/AIR coexistence. Both arguments
are observed; poison propagates and scalar undef retains its existing refusal.
Source/result freezes and discarded poison results keep the same rules.
Integer-only scalar execution continues to exclude calls.

Mixed scalar/void execution accepts binary i32 `air.add_sat.s.i32`,
`air.sub_sat.s.i32`, `air.add_sat.u.i32` and `air.sub_sat.u.i32` calls.
They reuse existing saturating evaluators and one-step result slots. Defined
overflow clamps; input poison still propagates and scalar undef retains its
existing refusal. Source/result freezes and discarded poison results use the
same rules. Appended keys 2162..2165 preserve prior AIR/LLVM identities.
Integer-only scalar execution continues to exclude calls.

Mixed scalar/void execution accepts `air.clz.i32` and `air.ctz.i32` with
an i32 input and a constant-false i1 flag. Zero returns 32. True/runtime/undef/
poison flags reject on every call; LLVM's separate true/poison form is unchanged.
The two appended keys 2160..2161 preserve existing identities. Pure attributes,
optional exact second-parameter immarg, poison/undef/freeze and discarded
results retain their existing rules. Integer-only scalar calls remain excluded.

The mixed scalar/void APIs also accept the binary i32 declarations
`air.min.s.i32`, `air.max.s.i32`, `air.min.u.i32` and `air.max.u.i32`.
They reuse the LLVM signed/unsigned extrema evaluators, state propagation and
one-step result slots. New keys 2156..2159 preserve the existing AIR/LLVM cache
identities. Both arguments are observed; poison propagates and scalar undef
retains its existing refusal. Source freezes and discarded poison results use
the same mixed execution rules. The integer-only scalar call exclusion remains.

The mixed scalar/void APIs accept `air.popcount.i32` and
`air.reverse_bits.i32` as pure unary i32 builtins. They share the existing LLVM
evaluators and state behavior while retaining separate declaration-cache keys
2154..2155, for 2,181 scalar slots. LLVM/AIR declarations may coexist; duplicate
AIR identities still reject. Integer-only scalar execution retains its exclusion
of calls. Scalar i64 population count and bit reversal are also admitted.
The shared attribute scanner admits function-level `mustprogress` on terminating
builtins; return/parameter placements and existing unsupported properties reject.

Fixed `llvm.vector.insert` calls support matching i1..i64/half/float base and
inserted element formats with up to 16 result lanes. Integer-only execution
excludes floating formats. Every third-argument i64 constant offset aligns to
the inserted count and keeps the full window in range. Exact declaration immarg
placement is selected per family: third parameter for insertion, second for
existing immediate families. Both scalar and memory scanners share this policy.
One call costs one step, one existing result slot and 2*base_count + inserted_count
work units. The vector cache has 61,764 entries, with new keys 52628..61603; the
scalar cache remains 2,181. Existing slots, snapshots and cleanup retain ownership.
Maintained tests cover overwritten poison/undef, surrounding lanes, input/result
freezes, discarded void results, loop reuse and existing resource bounds.

Fixed `llvm.vector.extract` calls support matching i1..i64/half/float element
formats with up to 16 source lanes. Integer-only execution excludes floating
formats. Every call requires a defined aligned in-range i64 constant offset,
including calls sharing a declaration. Copying preserves lane bits and deferred
state; result slots and vector-PHI snapshots retain existing ownership. Calls
cost one executed step, one vector slot and source_count + result_count work
units. Keys 43652..52627 append 8,976 identities; the vector declaration cache
has 52,628 entries and the scalar cache remains 2,181. Existing limits remain.
The maintained subvector checkers cover discarded void results, scalar/integer
observations, selected-state freezes, loop slot reuse and exact resource bounds.

Fixed 1..16-lane `llvm.get.active.lane.mask` calls accept matching i1..i64
scalar base/limit arguments and produce i1 lanes. Mathematical addition is
used: overflow cannot reactivate lanes. Poison propagates to all lanes and
vector freezes repair poison; scalar undef arguments require a prior scalar
freeze. Scalar/integer, discarded void and memory execution use the same
owned result slots, including vector-PHI loops. One executed step and
result_count validation work units are charged. Keys 42628..43651 append
1,024 identities, bringing the vector cache to 43,652 entries; the scalar
cache remains 2,181. Existing work, slot and graph bounds remain.

Fixed 1..16-lane i8..i64 `llvm.stepvector` calls construct defined lane numbers
without source operands. Exact direct zero-argument signatures are required;
missing arguments to older intrinsic families remain invalid. Calls cost one
executed step, one shared vector slot and result_count lane-work units.
The maintained stepvector checker covers scalar/integer results, unused void
results, insertion/selection/freezes, loop reuse and both sides of the existing
4,096-slot and 1,000,000-unit validation limits. Keys 41716..42627 append 912
identities; the vector cache has 42,628 entries and the scalar cache stays 2,181.

`llvm.vector.interleave2` through `interleave8` support fixed i1..i64/half/float
inputs whose combined result has at most 16 lanes. Calls preserve raw encodings,
poison and deferred undef; unused indeterminate results can be discarded and
freezes repair observed lanes. Integer-only execution excludes floating types.
All inputs have the same type and their lane counts sum to the result count.
One existing result slot and 2*result_count validation work units are charged;
one executed step is charged per call. The maintained interleave checker covers
scalar/integer APIs, vector-PHI loops and exact/exceeded shared 4,096-slot and
1,000,000-unit work limits. The vector cache grows to 41,716 distinct entries.

Fixed 1..16-lane i1..i64/half/float `llvm.vector.splice.left` and `.right`
calls concatenate two same-typed vectors and copy a shifted window with a
runtime scalar i32 offset. Offsets above N produce vector poison. Raw lane bits
and selected poison/undef tags remain intact, including signaling NaNs;
unselected indeterminate lanes may be discarded. A scalar undef offset still
requires a direct freeze before use. Integer-only execution excludes floating
lanes. Calls share existing 4,096 result slots, one executed step per call and
the 1,000,000-unit lane-work budget (3*N per splice). Canonical overload keys
37888..39999 distinguish both directions and all 66 formats at counts 1..16.
`tests/ios/air-vector-splice.v` checks scalar/integer execution, vector-PHI loop
slot reuse, state/freeze behavior, metadata and exact/exceeded resource limits.

Fixed 1..16-lane i1..i64/half/float `llvm.vector.reverse` calls copy lanes in
reverse order, preserving raw encodings and poison/undef state. They defer
undef observation, so unused undef results may be discarded and source/result
freezes retain their usual choices. Floating signaling NaNs remain unchanged.
Scalar, void and both memory APIs accept exact ordinary direct declarations;
integer-only execution excludes floating lanes. Calls cost one step and use
one existing vector slot plus 2*N validation lane-work units. The 1,056 new
cache keys append after earlier families and distinguish integer/half/float
types. Existing type/flag/attribute, work and construction limits apply.
Integer projections use existing shuffle-selector nodes in bounded address
graphs; loaded/PHI/floating address restrictions remain. The maintained
`tests/ios/air-vector-reverse.v` compares native LLVM raw bits, state, loop reuse,
typed/loaded source copies and admission/resource limits.

Scalar i1..i64 and fixed 1..16-lane integer `llvm.smulh`/`llvm.umulh` calls
return the high N bits of the full signed/unsigned 2N-bit product. Integer limb
arithmetic avoids host i128 and signed overflow. Scalar, void and both memory
APIs accept exact direct declarations; the integer-only API accepts the vector
forms through its existing intrinsic path. Poison propagates per lane, observed
undef rejects and source/result freezes retain their existing choices. Calls
cost one step; vectors use existing slots and 3*N validation lane-work units.
New cache entries append without shifting prior identities. Pure integer
address graphs accept both operands under existing node/depth limits.
`tests/ios/air-multiply-high.v` compares widened native LLVM products and checks
state, address, metadata, loop reuse and work/storage boundaries.

`llvm.canonicalize.f16/f32` and fixed 1..16-lane vector overloads preserve
finite encodings, subnormals, signed zero and infinities. NaNs retain sign and
payload, with only a signaling NaN's quiet bit changed. Evaluation uses integer
bits and ignores host FP state. Poison propagates per lane; observed undef
rejects, including after poison. Source freezes repair state before the call.
Calls cost one step; vectors use existing slots and 2*N validation lane-work
units. Two scalar and 32 vector cache identities append without moving prior
keys. Exact direct declarations and existing attribute guards apply; fast-math,
nondefault denormal modes, double, scalable/wider vectors and floating address
dependencies remain excluded. `tests/ios/air-canonicalize.v` compares exact
native LLVM encodings, state, metadata and budget boundaries.

Fixed-vector PHIs support 1..16 matching i1..i64/half/float lanes. The
executed predecessor selects the incoming vector, preserving its raw bits and
per-lane poison/undef state without reading unselected values. All selected
vectors are copied into a separate execution-owned snapshot buffer before
any PHI result is assigned. Each vector PHI owns a stable construction slot,
so simultaneous swaps and loop iterations cannot alias a changing producer.
Scalar and void APIs accept loop-carried vectors within the existing dynamic
step budget. Memory APIs keep their forward-only control-flow restriction;
typed vector arguments, constants, constructions and vector loads may feed
forward joins. Integer-only execution still excludes floating lanes, and
vector PHI dependencies remain excluded from precomputed address graphs.
Each PHI costs one execution step, N*(incoming-count+1) validation lane-work
units and one of the shared 4,096 vector slots. Snapshot capacity is bounded
by the number of vector PHIs and is allocated once per call, reused on block
visits and freed on every exit. Existing declaration cache identities stay
unchanged. Fast-math PHIs, scalable/wider vectors, vector returns and general
aggregates remain excluded. This support supersedes PHI exclusions in the
operation-specific sections below; other profile restrictions still apply.
`tests/ios/air-vector-phi.v` checks native LLVM branch values and simultaneous
loop rotations; `air-vector-phi-controls.v` checks void/loaded/argument flow,
metadata guards, address exclusions and exact work/storage boundaries.

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
poison/undef lanes. Earlier snapshots retain their state. Vector arguments and
loaded vectors remain unsupported. Whole-vector
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

Ordered floating sum/product reductions support ordinary direct
`llvm.vector.reduce.fadd.vNf16/f32` and `fmul` calls for fixed 1..16 lanes.
A matching scalar seed is combined with lanes in increasing index order,
rounding to the lane format after every operation. Existing IEEE arithmetic
provides nearest/ties-to-even rounding, gradual underflow, signed zeros,
infinities and the preferred quiet NaN choice. Seed or source poison poisons
the result; scalar seed undef and every executed undef vector lane reject.
Seed poison or an earlier NaN does not hide a later undef lane. Direct seed
and source freezes repair indeterminate inputs; result freeze repairs poison
but cannot suppress earlier undef errors. Mixed, void and memory execution
accept these calls, including earlier scalar results/PHIs as seeds where
admitted. Integer-only execution and floating address dependencies remain
excluded. Calls cost one execution step and N+2 validation lane-work units,
with no vector storage slot for the scalar result. Canonical overloads, exact
seed/element/result type identity, declarations, attributes and shared limits
remain checked. Fast-math/reassociation flags and scalable/wider formats
remain excluded. `tests/ios/air-vector-sequential-reduction.v` compares LLVM
intrinsics with explicit scalar chains and the interpreter, including half
sweeps, order-sensitive rounding, seed/lane states, freezes, loop reuse,
ordinary/prepared memory, metadata guards and exact shared limits.

Number-preferring floating reductions support ordinary direct
`llvm.vector.reduce.fmin.vNf16/f32` and `fmax` calls for fixed 1..16 lanes.
`fminimumnum` and `fmaximumnum` accept the same shapes and directly require
numeric preference for both quiet and signaling NaNs. Modern and legacy
declarations have distinct cache identities; existing keys stay unchanged.
The result is the numeric minimum/maximum, ignoring quiet NaNs when a number
is available and ordering -0 below +0. The existing scalar minnum/maxnum
refinement treats signaling NaNs as quiet too. Multiple all-NaN lanes produce
the preferred quiet NaN; a single lane preserves its raw bits. Every lane is
observed: poison propagates and executed undef rejects, including after NaNs
or poison. Source freeze repairs indeterminate lanes; result freeze repairs
poison without suppressing earlier undef errors. These scalar results reuse
mixed, void and memory execution and require N+1 validation work units with
no vector construction slot. Declaration/type/attribute guards and shared
limits are unchanged. Integer-only execution, floating address dependencies,
fast-math flags, scalable vectors and wider formats remain excluded.
`tests/ios/air-vector-number-reduction.v` compares native LLVM on defined,
quieted reference inputs, while independently checking the raw signaling-NaN
refinement, strict undef/poison, freeze and prewrite behavior in the interpreter.
The unit oracle ignores NaNs and selects extrema by integer encoding order.
`tests/ios/air-vector-modern-number-reduction.v` checks the modern names with
raw encodings, including signaling NaNs, against native LLVM scalar
minimumnum/maximumnum folds. It records intrinsic availability and keeps the
native reference module separate from synthetic vector calls: the installed
LLVM recognizes the scalar operations but lacks the modern vector reductions.

Floating minimum/maximum reductions support ordinary direct
`llvm.vector.reduce.fminimum.vNf16/f32` and `fmaximum` calls for fixed 1..16
lanes. They return one matching half/float scalar, propagate NaNs and order
negative zero below positive zero. A single lane retains its raw bits; larger
reductions use the existing preferred quiet NaN choice. Every input lane is
observed: poison poisons the scalar result and executed undef rejects, even
after earlier poison or a later result freeze. Source freeze repairs lanes;
scalar result freeze repairs poison to zero. Mixed, void and memory execution
accept these calls, with existing literal/construction/argument/load sources
where admitted. Integer-only execution and floating address dependencies remain
excluded. Calls cost one step and N+1 validation lane-work units, with scalar
SSA results consuming no vector construction slot. Canonical overloads, exact
type/declaration identities, attributes and shared limits remain checked.
Fast-math flags, scalable vectors, wider formats and other floating reduction
families remain excluded. `tests/ios/air-vector-float-reduction.v` checks native
LLVM finite bits/NaN classes, exhaustive half and deterministic float sweeps,
signed zeros, poison/undef/freezing, scalar/ordinary/prepared execution,
metadata guards and exact shared storage/work limits.

Integer vector reductions support ordinary direct `llvm.vector.reduce.add`,
`mul`, `and`, `or`, `xor`, `smin`, `smax`, `umin` and `umax` calls with canonical
`.vNiW` overloads, 1..16 lanes and i1..i64 elements. The result is scalar iW;
addition and multiplication wrap at W bits. All source lanes are observed: any
poison lane poisons the result even with an annihilating operand, and any
executed undef lane rejects before returning a result. Source freeze repairs
indeterminate lanes; scalar result freeze chooses zero for poison but cannot
hide an earlier undef error. Integer, mixed, void and memory execution accept
these calls. Memory sources may include admitted vector arguments and loads;
scalar execution keeps its existing argument restrictions. Reduction results
use ordinary scalar SSA slots, without consuming vector construction storage.
Each call costs one execution step and N+1 units of shared validation lane
work. Exact declaration identities, signatures, attributes and existing budgets
remain checked. Other reductions, nonordinary flags and scalable vectors
remain excluded. Pure integer address graphs also accept these reductions,
with complete source observation before writes, including inactive GEP roots
and results discarded by scalar select/freeze. Existing 256-node/32-level
bounds count all source projections and cached heights. Loaded values, PHIs
and floating dependencies remain excluded from address graphs.
`tests/ios/air-vector-reduction.v` checks native LLVM values, independent
arithmetic/extrema, all-lane states and freezing, ordinary/prepared stores,
loop reuse, malformed metadata, cache separation and exact shared limits.
`tests/ios/air-memory-vector-reduction-index.v` checks native LLVM results,
nonmutating address validation, ordinary/prepared write ordering, all-source
poison/undef and freeze controls, nested reductions and exact graph limits.

Fixed 1..16-lane integer vectors also support ordinary direct `llvm.clmul.vNiW`
calls for i1..i64 lanes. Multiplication combines polynomial terms with XOR
instead of carries, retaining the low W bits. Both operands and result must
have exactly the same vector type. Poison remains local to its lane even with
a zero multiplier; any executed undef operand lane rejects the call. Source
freeze repairs indeterminate lanes, while result freeze cannot hide earlier
errors. Integer, mixed, void and memory APIs accept the calls, including pure
integer address graphs with eager observation of all sources and conservative
prewrite checks. Existing construction/work and node/depth bounds apply.
Scalable vectors, malformed overloads, wider lanes and nonordinary call flags
remain excluded. `tests/ios/air-vector-clmul.v` checks native LLVM and independent
polynomial coefficients, both operand states, source/result freezing, loop
reuse, ordinary/prepared memory, cache identities and exact shared limits.

Fixed 1..16-lane integer vectors support ordinary direct `llvm.pext.vNiW`
and `llvm.pdep.vNiW` calls for i1..i64 lanes. Extraction gathers selected bits
into consecutive low positions; deposition scatters low bits into selected
positions. Positions are visited from low to high and unused bits are zero.
Each operand and result has the exact same vector type. Source poison remains
lane-local even with a zero mask; any undef input lane rejects the executed
call. Source freeze repairs indeterminate lanes, while result freeze cannot
hide earlier undef errors. Calls share existing construction, source-plus-result
lane work, declaration attributes and cache identity checks. Integer, mixed,
void and memory execution accept the calls, including pure integer address
graphs with all-source observation, conservative prewrite validation and
existing node/depth bounds. Scalable vectors, malformed overloads and nonzero
call flags remain excluded. `tests/ios/air-vector-bit-permutation.v` compares
native LLVM and an independent bit-position oracle, ordinary/prepared address
execution, scalar round trips, both source states, cache collisions and shared
work/storage bounds.

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
