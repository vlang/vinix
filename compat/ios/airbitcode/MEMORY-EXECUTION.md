# Bounded memory execution

`run_memory_function` executes a defined ordinary void function with buffer and
typed value arguments, forward control flow, scalar/vector loads/stores, scalar binary operations,
comparisons, scalar select/casts/freeze, floating negation, bounded constant and
argument-derived GEPs,
checked overflow-pair operations and a final ret void.
It accepts i1..i64, half and float memory values.
Scalar `extractelement` may also read supported fixed constant/constructed/loaded
vectors. Fixed 1..16-lane vector memory accesses accept byte-aligned integer
widths i8/i16/i24/i32/i40/i48/i56/i64 and half/float. Lanes occupy consecutive
little-endian bytes and preserve raw floating bits. Non-byte-aligned lanes,
scalable vectors, vector returns and vector PHIs remain unsupported.
This memory profile supersedes the loaded-vector exclusions in the individual
vector-operation sections below; scalar/void API exclusions still apply.

A vector load owns one existing construction slot and captures every lane before
later writes, including overlapping bindings. Vector stores validate all lane
tags before writing any destination byte; poison/undef rejects the entire store
while earlier instructions remain visible. Explicit alignment, permissions,
bounds and inactive-block preflight apply to the full stored byte size. Vector
GEP strides continue to use allocation size: `<3 x i24>` stores nine bytes but
has a sixteen-byte default allocation stride. Loads and stores charge their
lane counts to the existing work limit; loads share the 4,096-result cap.
No new execution array or per-access allocation is added. Retained heap is
unmeasured.

`memory_vector_test.v` checks 32,768 byte round trips and every indeterminate/
invalid lane position. `tests/ios/air-memory-vector.v` checks 61,440 exact native
copies, bitwise inversions and overlapping snapshots, 640 poison/undef/freeze
cases and 8,640 binding/budget/metadata/API refusals. Additional controls cover
unsupported shapes, cold blocks, address space 2, constant vectors, explicit
alignment, vector GEP padding and 4,096/4,097 result boundaries.
`tests/ios/vector-memory-regressions.v` runs focused controls from 23 existing
checkers. Their unsupported loaded-vector guards now use volatile vector loads;
complete historical matrices retain their original entry points.

`tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR vector-memory` builds and
runs the focused Objective-C runtime fixture with normal and deterministic Swift
hashing. Each mode checks 40 deferred dispatches across two drained runtimes:
20 complete and 20 fail on poison/undef without partial vector writes. This
mode leaves the existing `software` and `default` full-suite entry points intact.

Integer binary opcodes and half/float fadd/fsub/fmul/fdiv/frem reuse the scalar
interpreter's arithmetic, undefined-operation guards and poison propagation.
Nonvolatile constant-length memset, memmove and disjoint memcpy also operate on
byte ranges, as described below. Fast-math flags, alloca,
integer-pointer casts,
loops, atomics, volatile accesses, general calls or aggregate loads/stores
are rejected. The separate scalar/void APIs retain their existing profiles.

## Value arguments

Memory functions accept up to 64 interleaved buffer pointers and scalar/vector
values. Scalars are i1..i64, half or float; fixed vectors have 1..16 lanes of
those types, including non-byte-aligned integers. Argument values are raw bits,
without input poison/undef tags. `IRMemoryArgument.value_bits` is zero for a
buffer, otherwise it reports the lane width and `value_lanes` reports one for a
scalar or the declared vector count. The declaration still determines the type.

Bind a value with `IRMemoryBinding{values: words}`: exactly one u64 per lane,
empty data, zero offset, base alignment one and writable false. Each word is
masked to its declared lane width. Buffer bindings require empty values and keep
their existing data/bounds/alignment/permission checks. All bindings are validated
before writes, then all values are captured into execution-owned snapshots before
the first instruction. Caller arrays are borrowed only for the call; changing
them affects the next run, and aliasing output cannot alter the captured values.
The snapshot array is allocated only when value arguments exist and freed on
every execution exit. Materialization is bounded by 64 arguments and 16 lanes;
operation lane-work and result limits remain unchanged.

Vector arguments compose with the existing vector operations and extraction.
Integer/FP scalar arguments use the same raw-bit evaluator as the scalar API.
Both ordinary and prepared memory execution support values. The standalone
integer/scalar/void signatures retain their vector-argument exclusions. This
memory support supersedes argument exclusions in older operation sections below.
Vector memory stores still require byte-aligned lanes. Pointer values cannot be
supplied as integers. A direct scalar integer argument may index a GEP as
described below, including the bounded pure expressions listed there.

`tests/ios/air-memory-values.v` compares 35,904 mixed scalar/vector cases with
native LLVM through both APIs, including all widths/counts, masking and explicit
floating edge bits. It checks 16,830 invalid value/buffer bindings before writes,
unsupported input shapes, loaded GEP/inttoptr rejection, aliased snapshots,
bufferless functions, 256 branch/PHI inputs and 256 alternating poison/recovery calls.

## Indexed addresses

A single-index GEP may use a direct i1..i64 function argument with a fixed
pointer base, including an earlier constant GEP. It requires an explicit
little-endian layout with 64-bit pointer/index widths and a fixed allocation
stride of at most 64 MiB. Index words are masked to their declared width and
interpreted as signed; negative values reject. The checked product plus the
fixed offset must not exceed 64 MiB or the current binding's remaining extent.
Zero strides are supported. Known inbounds/nusw/nuw flags use the same bounded,
nonwrapping profile. An unused indexed pointer may be one past the binding;
loads/stores also require their complete stored size and explicit alignment.

An index may also be a pure integer SSA expression built from scalar arguments,
defined integer literals, extraction from a direct integer vector argument or
literal vector using a supported pure integer lane selector, add/subtract/multiply,
signed/unsigned division and remainder, shifts,
AND/OR/XOR, scalar integer comparisons/selects/freezes, unary bit intrinsics,
and trunc/zext/sext. Integer widths are i1..i64
and vectors retain the 1..16-lane limit. Known integer wrap/cast flags reuse the
ordinary scalar evaluators. Oversized shifts, left-shift wrap promises, right-shift
exactness and OR disjointness are checked before writes. Poison and negative/out-of-range final indices
reject before writes. Unflagged arithmetic keeps its ordinary modular semantics;
negative intermediate values are permitted when the final address is valid.
Zero divisors and signed minimum divided/remaindered by -1 reject as undefined
arithmetic. `exact` division with a nonzero remainder rejects as poison. These
checks also apply to cold/unused index expressions, even if execution would not
visit their block. Unrelated division keeps ordinary dynamic error behavior.
All ten scalar `icmp` predicates are supported, including `samesign` (different
operand signs produce poison). A comparison keeps its source integer width
separate from its i1 result width. Zero-extend a boolean for a positive 0/1
offset: a direct i1 true GEP index is negative and rejects under this profile.
Floating and pointer comparisons remain outside address expressions. Integer
vector comparison sources are described below.
Integer selects use a scalar i1 condition and matching i1..i64 value types.
Literal poison is admitted in the expression graph; undef is admitted only as
the direct operand of a freeze.
Poison propagates through ordinary nodes, but a select ignores poison in its
unselected value. A poison condition or chosen value poisons the result. Every
GEP expression is marked as an independent root, so a poisoned root still rejects
even if another select ignores the same node. Immediate arithmetic errors and
the existing poison-division profile errors remain unmaskable anywhere in the
graph. Selects choose values, not whether earlier IR arithmetic executes.
Scalar integer freeze preserves defined values and makes the same stable zero
choice for poison/direct undef as ordinary execution. It cannot repair an
independently checked poisoned GEP root or an immediate arithmetic error. Undef
in arithmetic or select dependencies still rejects, including when that same
constant was previously cached as a direct freeze source.
Address expressions also accept scalar `llvm.ctpop`, `llvm.bitreverse` and
`llvm.bswap` calls. Population count and bit reversal accept i1..i64; byte swap
retains the scalar profile's i16/i32/i48/i64 widths. Direct declaration identity,
signature, attributes and duplicate checks remain required by preflight.
These nodes propagate poison and compose with select/freeze. Other intrinsic
dependencies and ordinary calls remain outside the address graph. Intrinsic
nodes reuse the shared depth/node budget and allocate nothing during execution.
Leading/trailing zero counts (`llvm.ctlz`/`llvm.cttz`) also accept i1..i64 and
require a defined constant i1 zero-poison flag. A false flag returns the width
for zero; a true flag produces poison for zero. Select/freeze may suppress or
repair that poison, while independent GEP roots still reject it. The validated
flag is cached in the node; declaration immarg and attribute checks remain.
Signed/unsigned integer min/max (`llvm.smin`, `llvm.smax`, `llvm.umin`,
`llvm.umax`) accept matching i1..i64 operands. Both dependencies are validated,
including their full cached subtree heights, and poison in either operand
poisons the result even when the other value would win the comparison.
Integer absolute value (`llvm.abs`) accepts i1..i64 with a defined constant i1
minimum-poison flag. The signed minimum remains unchanged with a false flag,
and produces poison with a true flag. Other negative inputs become positive.
Poison propagation, select/freeze repair, independent root checks and declaration
immarg validation retain the same rules as zero-count intrinsics.
Signed/unsigned saturating addition/subtraction (`llvm.sadd.sat`, `llvm.uadd.sat`,
`llvm.ssub.sat`, `llvm.usub.sat`) accept matching i1..i64 operands. Overflow
clamps to the corresponding integer limit; it does not itself produce poison.
Poison in either input still propagates, and both dependency heights count
toward the shared graph limits.
Signed/unsigned saturating left shifts (`llvm.sshl.sat`, `llvm.ushl.sat`) also
accept matching i1..i64 value/amount operands. Valid shifts clamp overflow;
amounts at or above the width produce poison even when the input is zero.
Amounts are width-truncated unsigned words, without modulo reduction.
Funnel shifts (`llvm.fshl`, `llvm.fshr`) accept three matching i1..i64 inputs.
The unsigned amount reduces modulo the width; a zero effective shift chooses
the left word for fshl and right word for fshr. Identical data words implement
rotations. Poison in any input propagates, and all three subtree heights count
toward the shared depth limit.
Carry-less multiplication (`llvm.clmul`) and parallel bit extraction/deposition
(`llvm.pext`, `llvm.pdep`) accept matching i1..i64 operands. Carry-less products
retain the low N polynomial-product bits. Extraction packs selected bits into
low positions; deposition scatters low bits into selected positions. Both input
dependencies and poison flags are checked under the same graph limits.
`extractvalue` fields from signed/unsigned checked add/subtract/multiply
(`llvm.*.with.overflow`) also accept i1..i64 operands. Field zero is the wrapped
value; field one is the i1 overflow flag. Arithmetic overflow is defined, while
poison in either input poisons either extracted field. Pair selects may choose
between checked calls, nested pair selects and zero/poison pair constants. A
poison condition poisons the selected field; poison in an unselected pair does
not. Both branches and the condition are validated, and all three cached heights
count. Pair freeze preserves defined value/overflow fields and independently
chooses zero for poison fields. A direct frozen undef pair also chooses zero;
undef remains unsupported through ordinary extraction or selection, including
after its frozen form was cached. Cached constants retain their original poison
state, so freezing one use never repairs an unfrozen use. Pair `insertvalue`
replaces field zero (iN data) or one (i1 flag) using a validated literal index.
Only that field receives the replacement's value/poison; its neighbor retains
the base field. Inserts can repair one or both fields of a poison pair and
compose with select/freeze. Both base and replacement dependencies are built
and evaluated even when extracting an untouched field; both cached heights
count. Unsupported operands and immediate arithmetic errors still reject.
PHIs, loaded operands and ordinary undef bases/replacements remain unsupported
address dependencies; an appropriate direct freeze may repair undef first.

Pair fields are projected into scalar nodes, with separate cache keys for the
value field, overflow field and ordinary scalar results. Each projected pair
operation/constant and each extraction consumes a node/depth level. Calls plus
extractions still consume two levels. This separate representation can reach
the 256-node bound earlier than the former fused direct-call extraction.

Preflight builds a private, topologically ordered dependency graph only for
required index expressions. Its shared node limit is 256 per function, with at
most 32 levels including leaves and cached subexpressions. Unrelated arithmetic
does not consume this graph budget. Loads, PHIs and
other vector constructions and loaded vector dependencies reject as
address expressions. These operations keep their ordinary non-address support.
Every call evaluates the graph from immutable argument words into a fixed stack
array before resolving addresses, including in cold blocks and unused GEPs.
The graph is owned/freed with the profile; its build cache is transient and freed
on success/error. No expression node allocates during execution.
Evaluation uses an additional fixed 256-entry poison array alongside value words.
Selects include all three dependency heights in the shared depth limit.

Dynamic lane selectors are unsigned words masked to their own i1..i64 width.
Poison or a selector outside the vector yields poison without reading a lane.
Select/freeze can suppress/repair it; independent poisoned GEP roots still fail
before writes. A direct undef selector requires freeze first. Computed selectors
add their dependency height plus one extraction level and share the node budget.
Defined in-range literal argument-lane extractions retain their single-leaf cost.
Literal out-of-range/poison selectors now follow the same repairable poison path.
The source may be a direct 1..16-lane integer vector argument or a supported
literal integer vector. Constant vectors validate all lanes and retain a cached
contiguous scalar-leaf table, charged one graph node per lane. Each extraction
adds its selector dependency and one level/node. Zero/data/aggregate/splat,
poison and undef constants retain ordinary lane semantics. Only a selected undef
lane errors, even under scalar select/freeze; poison or out-of-range selectors skip
that check and produce poison. Unselected undef/poison lanes do not affect a
defined lane. Earlier vector freezes of these sources also feed addresses.
Repeated freezes preserve defined lanes and independently choose stable zero for
poison/undef lanes before extraction. This does not repair an invalid or poisoned
extraction selector; an outer scalar freeze may do so. Original constant tables
retain their unfrozen state in cache, so an unfrozen consumer still sees poison
or a selected-undef error. Unsupported constructions and loaded vectors still reject.

Vector argument leaves and each source freeze use private POD metadata nodes
under the existing vector cache tag. Source and selector heights both count
plus one extraction level, including cached subtrees. Argument literal lanes on
the existing direct path retain their cost. All source operations and branches
are validated before execution; scalar select cannot conceal unsupported sources
or an independently poisoned GEP root. No owned field or runtime heap array is added.

Vector sources also accept nested vector selects with a scalar i1 condition.
Arms may be direct integer vector arguments, supported constants, freezes,
insertions, shuffles, integer arithmetic/casts or further scalar-condition selects. Both arms and the condition
are validated even for literal conditions. Undef in an unchosen vector arm remains unobserved;
a chosen undef lane errors at the final extraction, even under a later scalar
select/freeze. A source vector freeze may repair it first. Poison conditions
produce poison lanes and may be repaired by a source vector freeze. Invalid
extraction selectors still produce poison before lane access. Loads, PHIs and
other unsupported constructions remain excluded from these
address graphs.

Private scalar projections defer lane undef until the final extraction. Select
propagates only the chosen tag; source freeze repairs tags after selector checks.
A new fixed 256-entry bool array stores these internal tags; no runtime heap
array is added. Cache keys reserve nine low bits for scalar/pair/source tags
0..3, per-selector projection tags 4..259 and guarded condition tables at 260.
Existing ownership/free paths and
256-node/32-level limits remain. All projected source/selector/condition heights
count, including cache hits; freeze-only paths retain their previous costs.

`insertelement` also supplies projected address lanes. It accepts the same pure
vector sources and i1..i64 replacement values and insertion indices. A valid
insertion overwrites one lane and preserves all other lane states. Literal undef
replacements stay deferred until a final extraction; overwriting an undef lane
repairs it, and unobserved undef replacements do not error. A poison or unsigned
out-of-range insertion index poisons the entire vector. A later valid insertion
can repair one lane, and a vector freeze can repair all lanes before extraction.
Invalid extraction indices remain poison through a source freeze. An undef
insertion index rejects, as do immediate errors in any source, replacement or
index dependency, including ignored lanes and inactive blocks.

Insertion projections use the existing POD nodes, selector-keyed cache and
fixed stack arrays, adding no owned field or successful-path allocation. Source,
replacement, insertion-index and extraction-selector heights all count toward
the existing limits, including cached subtrees.
`tests/ios/air-memory-vector-insert-index.v LLVM_AS FRESH_EXTERNAL_DIR` checks
all 64 lane/insertion widths, lane repair, poison/undef, nested insertion/select/
freeze composition, exact graph limits,
cache isolation and all three memory APIs. Older constructed-source rejection
fixtures use unsupported floating vector comparisons; retained historical evidence is unchanged.

`shufflevector` supplies address lanes from the same pure integer vector
sources. Its result may independently contain 1..16 lanes, matching the inputs'
element type. A fixed i32 mask selects across both inputs; poison and legacy
undef entries produce poison lanes. Selected source undef stays deferred until
final extraction or repair by a source freeze/insertion. Both complete sources
and every mask entry validate, even when unselected. Normalized entries must
match the original mask constant; negative integer entries cannot impersonate
poison tags. Floating operations and loaded/PHI sources remain
excluded from address graphs.

Two existing POD words pack the sixteen mask bytes, with 255 reserved for
poison. A mapping node checks the full unsigned extraction index before any
shift, then a rebasing node supplies the input lane to both source projections.
The shuffle node copies only the selected arm's state. Invalid extraction indices
remain poison through a vector freeze; a valid poison mask entry may be frozen
to zero. Every mapping, rebasing and source projection counts toward the existing
node/depth budgets, including cache hits. No owned field or runtime array is
added. `tests/ios/air-memory-vector-shuffle-index.v LLVM_AS FRESH_EXTERNAL_DIR`
checks both-source permutations, broadcasts, resized results, upper mask bytes,
poison/undef and frozen/unfrozen selection, exact limits and malformed masks.

Integer vector binary operations also feed pure addresses: add/sub/mul,
unsigned/signed division and remainder, shifts, and/or/xor, including the
existing nuw/nsw/exact/disjoint promises. Every operand lane is evaluated.
Any undef lane, invalid division/remainder or poison division operand rejects
the address dependency before writes, including ignored lanes, invalid extracts,
later unchosen selects and result freezes. Other poison remains lane-local and
may be ignored by extraction or repaired with a result vector freeze. Freezing
the sources first repairs their indeterminate lanes before arithmetic, but does
not suppress errors introduced by the arithmetic itself.

Each binary instruction builds one contiguous table of all result lanes and
caches POD metadata under the existing vector tag. Static selectors project
both full operands; binary nodes reject undef and use the existing integer
evaluator. Dynamic extraction reads the table through the existing constant-lane
node. Metadata retains the maximum height across every lane, with all dependencies
charged to the 256-node/32-level limits, including cache hits. Two fixed 16-int
builder arrays hold temporary indices; no owned field or runtime array is added.
`tests/ios/air-memory-vector-binary-index.v LLVM_AS FRESH_EXTERNAL_DIR` covers
all widths, thirteen opcodes/thirty flag variants, whole-vector errors and
lane-local poison, source/result freezing and exact cached graph boundaries.

Integer vector trunc/zext/sext also feed addresses, preserving lane count and
using i1..i64 source/destination widths with their required narrowing/widening
direction. Trunc accepts nuw/nsw and zext accepts nneg. Violated promises and
source poison stay lane-local; any operand undef rejects the cast dependency,
including ignored lanes, invalid extracts and later unchosen selects/freezes.
Source freeze repairs indeterminate operands before casting; result freeze may
repair cast poison but cannot conceal eager undef errors or an invalid extraction.
Floating conversions and floating bitcasts remain excluded here.

Each cast builds one contiguous result table with POD metadata under the same
vector cache tag as binary tables. Static selectors project every input lane,
then cast nodes check undef and call the existing scalar integer cast evaluator.
Metadata retains the maximum height across all lanes, including cached sources.
A fixed 16-int builder array holds parent indices; existing nodes/cache ownership,
free paths and graph limits remain. No runtime array or owned field is added.
`tests/ios/air-memory-vector-cast-index.v LLVM_AS FRESH_EXTERNAL_DIR` checks every
distinct width pair, flag variants, source/result freezes, eager errors, lane
poison and exact cached limits against native LLVM and a per-bit oracle.

Integer vector bitcasts also feed pure address graphs. Equal-total-width
1..16-lane i1..i64 shapes use little-endian packed bit positions, including
non-byte widths and lanes spanning multiple inputs. All source lanes are
observed before any result: even unused undef lanes or cold/unchosen address
dependencies reject before writes. Poison affects each overlapping result lane;
source/result/scalar freezes and invalid extraction selectors retain their
existing rules. One fixed 16-int builder array collects projections; existing
scalar observation nodes hold a contiguous source table, and POD bitcast nodes
read only validated bit positions. The cached result table retains the maximum
height across all source lanes. Existing 256-node/32-level bounds, graph/cache
ownership and fixed runtime arrays remain; no new owner or free path is added.
The maintained integer-bitcast index checker covers cache reuse, exact graph
limits, eager errors, rejected dependency kinds and malformed operations.

Integer vector `icmp` also supplies i1 address lanes from matching 1..16-lane
i1..i64 operands. All ten equality/unsigned/signed predicates accept `samesign`.
Source poison and different signs under that promise produce lane-local poison.
Every lane of both operands compares before extraction; any undef rejects the
address dependency before writes, including ignored lanes, invalid selectors,
later unchosen selects and result freezes. Freezing sources first repairs their
indeterminate lanes; freezing results may repair comparison poison. An invalid
extraction selector remains poison. Supported integer vector operations compose
on both sides of the comparison and may consume the resulting mask.

One cached contiguous table holds all i1 results. Two fixed 16-int builder arrays
hold input projection indices. POD metadata retains the table base and maximum
lane height; source/selector/result heights, including cached subtrees, share
the existing 256-node/32-level limits. Comparison nodes reject undef then reuse
the scalar integer comparator with the operand width kept separate from i1.
Existing graph/cache ownership and free paths remain, with no runtime array or
owned field added. Floating comparisons remain excluded.
`tests/ios/air-memory-vector-compare-index.v LLVM_AS FRESH_EXTERNAL_DIR` checks
every integer width/predicate/flag, representative full lane-count coverage,
both operands' indeterminate lanes, source/result freezes, table reuse and exact
cached graph limits against native LLVM and an independent signed-order oracle.

Vector `select` conditions may also be matching 1..16-lane i1 masks. Each lane
chooses its own arm; only that arm supplies the lane's undef or poison. A poison
condition poisons its result lane without observing either arm's state. Chosen
arm undef remains deferred until extraction or repair by a vector freeze.
Every condition lane must be defined: any condition undef rejects before writes,
even in an ignored lane, invalid extraction, cold block, later unchosen select or
result freeze. Freezing the mask first repairs indeterminate condition lanes.
Both arms, the entire condition and all immediate dependency errors still
validate. Pure integer comparison masks and existing vector constructions compose.

A guarded condition table uses cache tag 260, separate from ordinary/frozen
source snapshots and projection tags. Static selectors project every mask lane,
then existing extraction guards reject deferred undef while preserving poison.
Dynamic table reads and the existing projected select node choose the arm.
One fixed 16-int builder array holds input indices; POD table metadata retains
maximum lane height. Every source/condition/selector and cached height remains
charged to the existing graph limits. Runtime arrays, node kinds, ownership and
free paths are unchanged. Loaded/PHI and floating condition sources reject.
`tests/ios/air-memory-vector-lane-select-index.v LLVM_AS FRESH_EXTERNAL_DIR`
checks all widths, mask/arm states, unfrozen and frozen forms, condition-table
isolation/reuse and exact graph limits against native LLVM and a lane oracle.

Pure vector `llvm.ctpop`, `llvm.bitreverse` and `llvm.bswap` calls may also feed
addresses. Population count and bit reversal accept i1..i64 lanes; byte swap
accepts i16/i32/i48/i64. Fixed 1..16-lane argument and result types must match
the canonical overload. Existing direct declaration, signature, call-header,
attribute and duplicate-overload validation applies. No declaration or external
function pointer executes: projected nodes reuse the scalar bit evaluator.
Every input lane computes before extraction, so any undef rejects before writes,
including ignored lanes, invalid selectors and later unchosen selects/freezes.
Poison stays lane-local; source freeze repairs operands and result freeze may
repair poison. Original extraction bounds remain checked.

One contiguous result table per call uses the existing source cache tag and POD
metadata retaining maximum lane height. A fixed 16-int builder array holds input
projection indices. Source/result/selector and cached heights retain the existing
graph limits; ownership, free paths and fixed runtime arrays are unchanged.
`tests/ios/air-memory-vector-bit-intrinsic-index.v LLVM_AS FRESH_EXTERNAL_DIR`
checks all supported widths/families, representative full lane-count coverage,
source/result freezing, poison/undef, cached graph limits and malformed calls
against native LLVM and independent bit/byte oracles.

Vector `llvm.ctlz` and `llvm.cttz` likewise supply address lanes across i1..i64.
Their call-local `is_zero_poison` argument must be an exact defined i1 constant,
validated on every call, including declaration/source cache hits. False returns
the lane width for zero; true produces lane-local poison for zero. Source
poison also stays lane-local. Undef remains an eager whole-vector error, even
when extraction, an unchosen select or a later freeze would ignore that lane.
Source freeze may repair undef/poison to zero, which can itself produce poison
under a true flag; result freeze may repair zero-count poison. Extraction bounds
remain independent. The existing intrinsic table stores each call's flag in its
POD nodes, with no new array, node kind, owner or limit change. Declaration
attributes retain the second-parameter immarg policy.
`tests/ios/air-memory-vector-zero-count-index.v LLVM_AS FRESH_EXTERNAL_DIR`
checks both operations/flags at every width, source/result recovery, call-local
flag isolation/guards and exact cached graph limits with LLVM and independent
division-based count oracles.

Vector `llvm.abs` also supplies address lanes across fixed 1..16-lane i1..i64
operands. The call-local `is_int_min_poison` flag must be an exact defined i1
constant. False preserves the signed minimum bit pattern; true produces
lane-local poison for that value. Other negative inputs yield their positive
magnitude bits. Source poison stays lane-local, while undef remains an eager
whole-vector error before extraction, selects or result freeze. Source freeze
repairs indeterminate lanes to zero; result freeze may repair minimum poison.
The existing unary intrinsic table and scalar abs evaluator retain each call's
flag, with unchanged storage, ownership, extraction bounds and graph limits.
Other vector intrinsic families remain excluded from address dependencies.
`tests/ios/air-memory-vector-abs-index.v LLVM_AS FRESH_EXTERNAL_DIR` checks both
flags, all widths, minimum/negative inputs, poison/undef, source/result recovery,
call-local flag isolation and cached graph boundaries against defined native
LLVM references and an independent unsigned magnitude oracle.

Vector `llvm.smin`, `llvm.smax`, `llvm.umin` and `llvm.umax` also supply address
lanes for matching fixed 1..16-lane i1..i64 operands. Both input vectors compute
before extraction. Undef in either input is an eager whole-vector error, even
in an ignored lane, unchosen select or cold block. Poison in either input
propagates only to its result lane, even if the other input would win an ordinary
comparison. Source freeze can repair indeterminate inputs; result freeze may
repair poison but cannot hide an earlier undef error. Extraction bounds remain.

The shared intrinsic builder validates three lane counts of work (two inputs
and the result), then projects both sources using fixed 16-int arrays. Each
existing POD result node stores the second projection in its right field; unary
calls keep that field at -1. Cached table height includes both operands. The
existing evaluator checks both undef/poison states and uses the scalar integer
extremum helper. No node kind, managed array, owner, lifetime or free path is
added; limits remain 256 nodes/32 levels.
`tests/ios/air-memory-vector-minmax-index.v LLVM_AS FRESH_EXTERNAL_DIR` checks
all four operations, widths, operand states, source/result freezes, both input
depth boundaries, cached selectors and exact node limits against defined native
LLVM references and an independent sign-partition comparison oracle.

Vector `llvm.sadd.sat`, `llvm.uadd.sat`, `llvm.ssub.sat` and `llvm.usub.sat`
also supply address lanes for matching fixed 1..16-lane i1..i64 inputs. Signed
overflow clamps to the corresponding signed endpoint; unsigned addition clamps
to the unsigned maximum and unsigned subtraction clamps to zero. Saturation
itself produces defined values. Poison from either input stays lane-local and
undef in either remains an eager whole-vector error. Source/result freezes,
extraction bounds and the existing pure composition rules retain their behavior.
The existing two-input intrinsic table and scalar intrinsic dispatcher handle
these operations with unchanged node layout, arrays, ownership and graph limits.
`tests/ios/air-memory-vector-saturating-index.v LLVM_AS FRESH_EXTERNAL_DIR`
checks all four operations at every width, both operand states, source/result
freezes, ten explicit clamp boundaries and the earlier graph/call controls
against defined native LLVM, checked signed margins and a two-limb unsigned
addition oracle.

Vector `llvm.sshl.sat` and `llvm.ushl.sat` also supply address lanes for matching
fixed 1..16-lane i1..i64 values and amounts. Each amount is width-truncated and
interpreted as unsigned. Counts below the width produce a saturating signed or
unsigned left shift; counts at or above the width produce lane-local poison,
including shifts of zero. Counts never reduce modulo the width. Source poison
also propagates lane-locally; undef in either source remains an eager error.
Source freeze repairs indeterminate inputs but does not repair a defined
overshift. Result freeze or a scalar freeze after a valid extraction may repair
overshift poison. Extraction bounds remain independent of result freeze.

The existing two-input table dispatches these operations to the poison-aware
scalar shift helper before the ordinary scalar intrinsic dispatcher. Node
layout, fixed arrays, ownership, free paths and graph limits remain unchanged.
`tests/ios/air-memory-vector-saturating-shift-index.v LLVM_AS FRESH_EXTERNAL_DIR`
checks both families at every width, boundary counts, both source states,
freezes, prewrite refusals and prior graph/call controls. Native LLVM references
substitute a defined zero amount for overshifts; V models the original poison
separately and checks defined results with independent checked doubling.

Vector `llvm.fshl` and `llvm.fshr` also supply address lanes for three matching
fixed 1..16-lane i1..i64 inputs. Amounts are width-truncated and reduced modulo
the lane width. A zero count selects the left word for fshl and the right word
for fshr. All three inputs are observed: poison in any input propagates to its
lane, including an otherwise unused word at zero count; undef in any input is
an eager whole-vector error before extraction, unchosen selects or cold blocks.
Source/result freezes retain their existing recovery rules and extraction bounds.

The shared intrinsic builder validates four lane counts of work and adds one
fixed 16-int array for third projections. Existing POD result nodes store that
projection in their condition field, with -1 retained for other intrinsic calls.
Cached height includes all three operands. The existing evaluator checks their
states before scalar funnel evaluation. No node kind, managed array, owner or
free path is added; graph limits remain 256 nodes/32 levels. Other vector
intrinsic families remain excluded from addresses.
`tests/ios/air-memory-vector-funnel-index.v LLVM_AS FRESH_EXTERNAL_DIR` checks
both directions, all widths, modulo/zero counts, three independent source
states, the third input's cached depth and exact node boundaries, call guards
and exact byte preservation against native LLVM and per-bit selection oracles.

`tests/ios/air-memory-vector-select-index.v LLVM_AS FRESH_EXTERNAL_DIR` checks
all integer lane widths, lazy arm selection, nested selects, source/result
freezes, condition poison, invalid selectors, cache isolation, exact graph limits
and unsupported or immediately invalid source/condition dependencies.

`tests/ios/air-memory-vector-freeze-index.v LLVM_AS FRESH_EXTERNAL_DIR` checks
all integer lane widths, direct arguments and constant lane states, repeated
freezes, scalar recovery, selector poison/range, frozen/unfrozen cache isolation,
exact graph limits, cold/independent roots and unsupported source dependencies.

`tests/ios/air-memory-constant-lane-index.v LLVM_AS FRESH_EXTERNAL_DIR` compares
constant lane selection against defined native LLVM extracts. It checks all
i1..i64 lane widths, lengths 1..16, selector widths 1/32/64, mixed defined/poison/
undef lanes, lazy lane errors, scalar select/freeze, exact graph limits, shared
constant tables, independent/cold roots and malformed constant metadata.

`tests/ios/air-memory-dynamic-lane-index.v LLVM_AS FRESH_EXTERNAL_DIR` checks
all integer lane widths, six selector widths, vector lengths 1/2/3/16,
computed/poison/frozen selectors, masking, select/freeze recovery, and exact
prewrite refusal across validation and ordinary/prepared execution. Defined
native LLVM extracts provide the lane oracle; invalid native extracts are
never executed. It also checks cached depth/node limits, independent/cold roots,
binding shape, and unsupported or immediately invalid selector dependencies.

`tests/ios/air-memory-bitwise-index.v LLVM_AS FRESH_EXTERNAL_DIR` checks all
i1..i64 widths with a defined LLVM oracle. It selects safe shift amounts before
evaluating ordinary reference operations, then checks flag promises with wide
arithmetic, reverse shifts or overlap tests. Native flagged targets run only for
accepted addresses. Validation alone, prepared and ordinary execution must agree;
rejected indices preserve the entire output. Existing graph limits still apply.

`tests/ios/air-memory-division-index.v LLVM_AS FRESH_EXTERNAL_DIR` checks all
i1..i64 widths with a defined wide LLVM oracle. A selected nonzero divisor and
i128 arithmetic avoid executing original-width undefined operations in the
reference; separate tags identify zero/overflow, exactness poison and bounds.
Flagged native memory targets run only for accepted addresses. Both execution
APIs and validation alone must agree and preserve output on refusal.

`tests/ios/air-memory-compare-index.v LLVM_AS FRESH_EXTERNAL_DIR` compares every
predicate, i1..i64 source width, samesign/unflagged form and direct-i1/zext-i64
address form with LLVM. The reference uses unflagged comparisons and a defined
sign-bit test; flagged native targets run only after a nonpoison bounded index
is established. Both execution APIs and validation alone check full output
preservation on refusal. Graph limits, cold-block checking and snapshots apply.

`tests/ios/air-memory-select-index.v LLVM_AS FRESH_EXTERNAL_DIR` checks both
conditions, nested selects, literal and computed poison, poisoned conditions,
and ordinary values across i1..i64 against defined LLVM oracle values/tags.
Separate controls check independently cached GEP roots, one-past bounds, cold
poison, unmaskable division errors and exact cached-condition depth boundaries.

`tests/ios/air-memory-freeze-index.v LLVM_AS FRESH_EXTERNAL_DIR` checks defined
values and explicit zero choices across i1..i64, including poison arithmetic,
selects, comparisons, nested freezes and direct undef. Defined native targets
run only for accepted addresses; arbitrary native freeze choices are checked
with choice-independent properties. All three APIs verify prewrite refusals
and consistent address/value use. Controls cover independent roots, immediate
errors, cold blocks, one-past bounds, undef cache isolation and depth boundaries.

Preflight caches the index source, width and stride. Every call resolves all
indexed GEPs and accesses, including cold blocks, before any AIR instruction or
write. Static argument minimum sizes describe only the fixed base and access
sizes; callers must also pass the per-call validation. The engine owns one
offset array for an indexed function, releases it on success and error, and
uses no such scratch for a static function. Caller buffers and words remain
borrowed; aliased output cannot change the resolved offsets or captured values.

Indexed pointers are confined to direct ordinary load/store operands. Another
GEP, pointer PHI/select/freeze/cast/comparison, or memory-intrinsic use rejects
before writes, including zero-length intrinsic uses. General SSA indices,
multiple dynamic indices and negative final indices remain outside this
profile. Existing constant backward and structured paths retain their support.

`tests/ios/air-memory-indexed.v` checks 37,788 exact native cases and 15,460
invalid inputs through ordinary/prepared execution and validation alone, across
all 64 index widths, 13 layouts and four flag forms. Controls cover unsupported
pointer flows, alignment, cold blocks, one-past/64 MiB limits, aliased index
snapshots, readonly address spaces and default prepared objects.

`tests/ios/air-memory-computed-index.v` compares integer expression flags against
defined native LLVM overflow intrinsics before invoking flagged native targets.
It covers all 64 widths, vector-coordinate flattening, integer casts, poison,
cold bounds, aliased argument snapshots and exact graph node/depth boundaries.

`tests/ios/air-memory-bit-intrinsic-index.v LLVM_AS FRESH_EXTERNAL_DIR` compares
all 132 admitted unary bit overloads with native LLVM, through validation and
ordinary/prepared execution. Six patterns cover direct/masked values, literal
and computed poison, freeze and select suppression; refusals preserve all bytes.
Each overload also checks exact cached depth acceptance/refusal boundaries.

`tests/ios/air-memory-zero-count-index.v LLVM_AS FRESH_EXTERNAL_DIR` checks both
zero-poison flags across all 128 overloads, with a defined false-flag LLVM oracle
and separate poison checks. It covers cached depth limits, cold poison/freeze,
independent roots, dynamic flag rejection and malformed call metadata.

`tests/ios/air-memory-minmax-index.v LLVM_AS FRESH_EXTERNAL_DIR` compares all
256 scalar min/max overloads with defined native LLVM calls. It checks direct
and masked indices, both poisoned operands, computed right-hand poison,
select/freeze handling and cached depth boundaries through either dependency.
Validation and both execution APIs preserve every output byte on refusal.

`tests/ios/air-memory-abs-index.v LLVM_AS FRESH_EXTERNAL_DIR` checks both flag
settings across i1..i64 using a defined false-flag LLVM oracle and separate
poison checks. It covers signed minima, computed poison, select/freeze, cached
depth limits, cold blocks, independent roots and malformed call/flag metadata.

`tests/ios/air-memory-saturating-index.v LLVM_AS FRESH_EXTERNAL_DIR` compares
all 256 saturating add/sub overloads with defined native LLVM operations. It
covers signed/unsigned limits, direct/masked indices, poison on either side,
computed wrap poison, select/freeze and both cached dependency depth boundaries.

`tests/ios/air-memory-saturating-shift-index.v LLVM_AS FRESH_EXTERNAL_DIR` uses
a defined LLVM oracle with oversized amounts replaced before native shifts.
Separate checks model poison and cover select/freeze, both dependency depth
boundaries, cold zero overshifts and independent GEP roots through all three APIs.

`tests/ios/air-memory-funnel-index.v LLVM_AS FRESH_EXTERNAL_DIR` compares i1..i64
funnel shifts with defined native LLVM calls. It covers modulo/zero amounts,
non-power-of-two widths, poison in each input, select/freeze, computed amount
poison and cached depth boundaries through all three dependencies.

`tests/ios/air-memory-bit-manipulation-index.v LLVM_AS FRESH_EXTERNAL_DIR`
compares all 192 carry-less multiply/extract/deposit overloads with defined
native LLVM calls. It covers masks, low-bit truncation, direct/masked indices,
both poisoned operands, computed poison, select/freeze and cached depth limits
through either input. All three APIs preserve output on refusal.

`tests/ios/air-memory-overflow-index.v LLVM_AS FRESH_EXTERNAL_DIR` compares both
direct fields of all 384 checked-arithmetic overloads with defined native LLVM
calls. It checks direct/masked/zero-extended indices, poison in either operand,
computed poison, scalar select/freeze, cached depth through either input, cold
and independent poison roots, and unsupported aggregate/load dependencies.
Validation, ordinary and prepared execution preserve every byte on refusal.

`tests/ios/air-memory-pair-select-index.v LLVM_AS FRESH_EXTERNAL_DIR` compares
both selected fields across all 384 checked-arithmetic overloads with defined
native LLVM calls/selects. It checks nested selects, zero/poison pairs, poison
conditions, scalar freeze, computed conditions, both shared-field extraction
orders, exact node/depth limits, cold/independent roots and unsupported inputs.

`tests/ios/air-memory-pair-freeze-index.v LLVM_AS FRESH_EXTERNAL_DIR` compares
defined pair freezes and repeated freezes with LLVM over all 384 overloads and
both fields. It checks the stable zero choice for poison/direct undef, nested
select/freeze composition, shared fields, cached unfrozen poison/undef uses,
exact node/depth boundaries and cold frozen/non-frozen roots.

`tests/ios/air-memory-pair-insert-index.v LLVM_AS FRESH_EXTERNAL_DIR` compares
field replacement with LLVM over all 384 checked-arithmetic overloads. It checks
partial/full poison repair, both overwrite orders, untouched neighbors, scalar
replacement poison, select/freeze composition, both shared-field extraction
orders, exact node/depth limits and rejected ignored dependencies.

## Prepared memory functions

`p.prepare_memory_function(ir, stream, pools, bodies, function)` validates the
complete function once and returns an owned `IRPreparedMemoryFunction`. Call
`prepared.run(mut bindings, step_limit)` for subsequent executions. The object
captures its function and indexes internally; execution does not accept a caller
supplied profile. `argument_count()`, `argument(index)` and `steps()` expose the
binding requirements and static upper bound on steps. Each argument query returns
a value copy, so changing it cannot alter the cached requirements. A default
uninitialized object rejects execution and validation.
`prepared.validate(bindings, step_limit)` checks the current bindings and all indexed addresses without
executing the AIR body or writing buffers. It evaluates index-expression poison;
it does not evaluate unrelated arithmetic or
guarantee a future call whose bindings have changed; `run` repeats the checks.

The prepared object owns only its profile arrays. The program, module, stream,
constant pools, bodies and backing bitcode are borrowed: they must remain alive
and immutable through the last execution. Free the prepared object exactly once
before freeing those indexes. It does not clone or freeze their storage. Valid
LLVM IR remains a precondition. The ordinary `run_memory_function` entry point
continues to preflight each call, including the existing mutation checks.

Every prepared execution still checks the current binding count, sizes, offsets,
alignment, permissions, address-space restrictions, step limit and actual
backing-address overlap for memcpy and all indexed addresses. These checks run
before any writes, including for inactive instructions. Execution allocates fresh
scalar/vector/PHI/move/value-argument/indexed-offset scratch and releases it on
success or error; values and failures do not
persist between runs. The operation semantics and execution engine are shared
with the ordinary API. The software Metal pipeline owns this preparation and
reuses it when deferred dispatch snapshots execute.

`tests/ios/air-memory-prepared.v` compares 28,928 scalar/vector copies with the
ordinary API and independent expected bytes. Another 3,314 controls cover changing
inputs, branch PHIs, fills/copies/moves, poison recovery, copied metadata and
binding/budget guards. Extra controls cover aliases, explicit alignment, readonly
address space 2, invalid cold blocks, empty functions and default objects. Its
alternating five-round microbenchmark uses a synthetic 2,048-instruction cold
block and reports raw times; it is not an application performance measurement.

Unconditional branches and scalar i1 conditional branches must target strictly
later blocks in the function's block order; conditional destinations must be
distinct. All blocks are partitioned and preflighted, including unvisited
ones. Leading PHIs accept matching i1..i64, half/float or supported overflow
pairs, with exactly one incoming value for each actual predecessor. They read
only the executed predecessor, collecting all incoming values before publishing
results. Pointer PHIs are supported when every incoming operand has the same
pointer type and resolves to the same argument identity and byte offset.
Incoming arguments, earlier GEPs and earlier invariant pointer PHIs may use
different SSA names. All incoming pointers must be supported and equivalent,
including on inactive paths; different arguments reject even if their buffers
alias. These PHIs resolve during preflight and never enter scalar value slots.
They still cost one executed step and may mix with scalar/pair PHIs in any
order. General aggregate PHIs, backward edges and loops reject.

Integer `switch` accepts i1..i64 conditions and zero through 64 distinct
defined integer literal cases of exactly the condition type. Default and case
destinations must be distinct and strictly later blocks. Case literals, kinds,
widths and duplicate values are checked before stores, with bounded validation
work. Execution tests cases in their encoded order, charging one additional
step per comparison until a match; default paths compare every case. Empty
switches still evaluate the condition. Poison conditions error and undef
conditions retain the scalar reader's error behavior.

Buffer extents, alignments and permissions combine every block's requirements,
including inactive paths. `IRMemoryProfile.steps` is the conservative total
instruction count across all blocks plus the maximum case comparisons for
every switch, every memset byte and twice every memmove byte;
callers must supply at least that budget
before any execution. `IRVoidRun.steps` counts the executed path, charging each
branch, PHI and return once. Poison branch conditions error; undef conditions
retain the scalar reader's error behavior. Dynamic errors leave earlier stores
visible. Untaken dynamic errors and unchosen scalar PHI undef values are not
evaluated; unsupported operations/constants in any block still fail preflight.

Integer add/sub/mul/shl accept `nuw`, `nsw` or both. Integer udiv/sdiv/lshr/ashr
accept `exact`. Their existing scalar evaluator propagates poison for violated
wrap/exact promises and overshifts. Unknown and wrong-family flag bits reject
during preflight. Floating arithmetic still requires zero flags. Division by
zero, signed division overflow and poison division inputs retain their dynamic
error behavior. Storing poison rejects; select may discard it and freeze can
make a defined choice. Flags add no execution steps.

Integer `or disjoint` also supports i1..i64. It produces poison when any bit
is set in both operands; otherwise it returns ordinary bitwise OR. Operand
poison propagates and selected undef errors, including when the other operand
is zero. Integer, mixed scalar, void and memory APIs share this evaluator.

Integer comparisons support all ten signed/unsigned/equality predicates;
half/float comparisons support all sixteen ordered/unordered predicates.
Results are scalar i1. Select requires an i1 condition and matching scalar
value/result types. Comparison and selection reuse the scalar interpreter's
helpers, including constant true/false FP predicates and poison propagation.
Select reads its condition and only the chosen value. Unselected poison/undef
constants do not reject; selected undef errors, and poison conditions/chosen
values propagate to a rejected poison store. Selection does not skip earlier
instructions. Same-binding pointer equality and unsigned ordering are described
below. Aggregate comparisons,
general aggregate selects and select flags remain unsupported;
the overflow-pair select exception is described below.

Scalar integer `icmp samesign` supports all ten predicates at i1..i64 and
produces poison for operands with different sign bits, including i1 0 versus 1.
Same-sign operands retain the ordinary predicate result. Flags add no steps;
poison may be stored only after freeze or discarded by a select, and a poisoned
branch condition errors after earlier writes. Floating/pointer comparison flags
and unknown integer comparison flag bits still reject during preflight.

Pointer selects accept a scalar i1 condition and two operands of exactly the
result pointer type, both resolving to the same argument identity and byte
offset. Both arms must be supported and equivalent even for a literal condition;
different arguments reject even if their bound buffers alias. Arguments, GEPs,
invariant pointer PHIs and earlier invariant selects may feed either arm. The
result resolves during preflight and may feed GEPs, PHIs, selects and accesses.
Each executed pointer select reads its condition and costs one step. This
bounded profile requires a defined condition at that instruction: poison/undef
reject immediately, including for unused results, and prior stores remain
visible. Untaken blocks do not evaluate their selects. Scalar freeze may make
the condition defined. No runtime pointer poison tracking is provided.

`extractelement` supports fixed vectors of 1..16 i1..i64/half/float
lanes and scalar i1..i64 indices, interpreted as unsigned after width masking.
Materialized data, scalar splats, aggregate lane constants, zero, poison and
undef vectors are admitted. Every lane is checked in preflight, including
unselected lanes and inactive blocks; unsupported expressions reject before
stores. A separate per-function budget admits at most 1,000,000 lanes
across extractions, insertions, shuffles, vector freezes and vector selects. Extractions,
insertions and freezes charge their vector's full count; shuffles charge both
input counts and the output count, as do whole-vector selects for their two arms
and result.
Each executed extraction costs one step and adds no buffer access requirement.

Execution reads only the indexed lane. An out-of-range or poison index yields
poison; an undef index errors. Selected poison propagates and selected undef
errors; other poison/undef lanes do not affect a defined selection. An
out-of-range index yields poison even for a whole undef vector. Extracted
scalar bits feed existing arithmetic, casts, select/freeze, PHIs and stores.
Integer, mixed scalar and void APIs share validation/evaluation; the integer
API admits integer lanes only.

`insertelement` creates a new vector snapshot from a supported literal or an
earlier supported vector result of the same type. It replaces one lane
with a scalar value, poison or literal undef; other lanes retain their state.
Extraction may read either snapshot. A poison or out-of-range insertion index poisons the
whole new vector; an undef index errors. A later valid insertion can repair
one lane of poison/undef. Each insertion costs one executed step. Preflight
caps all supported vector construction results together at 4,096
per function, including inactive blocks.
One execution-owned array holds those fixed-size snapshots and is freed on
every exit; loop visits reuse each instruction's slot. Vector PHIs,
arguments, loads/stores, scalable vectors, other lane
formats and vectors larger than sixteen lanes remain unsupported.

`shufflevector` combines lanes from two supported constant or earlier
constructed vectors of the same type. Its fixed output has the same scalar
element type and may independently contain 1..16 lanes. Constant i32 mask
entries select across the concatenated inputs; poison and legacy undef mask
entries produce poison lanes. Selected source undef remains undef until
extracted. Other lane states and scalar bits are copied exactly. Preflight
checks both complete sources and matches the normalized mask against its
original constant, including unselected lanes and inactive blocks. A shuffle
costs one executed step and uses the same bounded snapshot storage as insertion.

Vector `freeze` accepts the same fixed scalar-lane types and supported literal
or earlier constructed sources. Each defined lane retains its exact bits;
each poison/undef lane becomes a fixed zero independently. The new snapshot
has no indeterminate lanes, and repeated freezes are idempotent. All uses of
one dynamic result read the same stored snapshot. Earlier vectors retain
their state. Frozen vectors may feed insertions, shuffles, freezes and scalar
extractions. Freeze costs one executed step and shares construction storage
and lane-work limits. It does not suppress errors that occur while evaluating
its source, or poison introduced by subsequent operations.

Whole-vector `select` accepts a scalar i1 condition and two supported sources
of exactly the result type. Both complete arms are checked in preflight,
including unchosen constants and inactive blocks. At execution only the
selected arm is read; its scalar bits and per-lane poison/undef tags are
copied into an independent snapshot. A poison condition produces poison in
every result lane; an undef condition rejects at select, following the existing
scalar execution policy. An unselected undef/poison arm does not taint the
chosen result. Earlier source-evaluation errors still stop execution.
Selections may feed any supported vector operation. Each select costs one
executed step and shares construction/storage and lane-work limits. Vector
select fast-math flags and vector PHIs remain unsupported.

Per-lane `select` accepts a fixed i1 vector condition with exactly the result's
lane count. Its source may be a supported constant or an earlier construction,
including an i1 vector select. Preflight checks the complete condition and both
arms; lane work charges the condition, both arms and result. Each defined
condition lane copies the chosen arm's exact bits and poison/undef state.
Poison condition lanes produce poison only in the corresponding result lane.
Any undef condition lane rejects execution at select, even when another lane
would be extracted or the result discarded. Freezing the condition first
chooses zero for its indeterminate lanes. An arm is read only when at least
one defined condition lane chooses it; all-poison conditions read neither arm.
The result uses the same snapshot storage, one executed step, and downstream
operations as whole-vector selection. Prior source evaluation errors still stop
execution. Vector condition arguments, PHIs and loads remain unsupported.

Vector `icmp` and `fcmp` compare corresponding lanes and produce a matching
fixed i1 vector. Sources use the same supported constant/earlier-construction
rules. All ten integer predicates accept i1..i64 lanes; `samesign` independently
poisons lanes with different input signs. Half/float support all sixteen
ordered/unordered predicates, including NaNs, infinities and signed zeros,
using the existing bit-based scalar helpers. Poison propagates independently
per lane. Any undef input lane rejects at comparison, even for a discarded
result or an extraction of another lane. The constant FP predicates false/true
follow the existing scalar policy: they return uniform defined masks without
reading either source, while preflight still checks both complete sources.
Earlier source instructions still execute and may fail.
Results may feed comparisons, per-lane select, freeze, insertion, shuffle and
extraction, preserving older snapshots. Comparison costs one executed step;
validation charges both source counts plus the result count, and results share
the existing construction storage. Floating/pointer comparison flags, vector
pointer comparisons remain unsupported.

Vector integer binary operations accept matching fixed 1..16-lane i1..i64
vectors. All thirteen scalar opcodes apply independently per lane: add, subtract,
multiply, signed/unsigned division/remainder, shifts, AND, OR and XOR.
`nuw`/`nsw`, `exact` and OR `disjoint` follow the scalar flag rules and produce
poison only in affected lanes. Out-of-range shift amounts also poison only
their own lanes. Sources use the same supported constant/earlier-construction
rules, and both complete sources are checked before execution. The result
preserves earlier snapshots and may feed any supported vector operation.
Any undef operand lane rejects at the binary instruction, including discarded
results or extraction of a different lane. Division/remainder with poison,
zero divisors or signed-minimum/-1 rejects the whole executed instruction,
following the existing bounded scalar policy; this includes signed remainder.
Freezing sources first can repair poison/undef, but a frozen zero divisor still
rejects. Freezing a result does not suppress errors that occur while evaluating
the instruction. Earlier stores remain visible after dynamic failures.
Each binary instruction costs one step, charges both source counts plus result
count against lane work, and shares the existing bounded snapshot array.

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

Scalar casts share validation and value conversion with the scalar executor:
integer truncation/zero extension/sign extension across i1..i64, signed and
unsigned conversions between those integers and half/float, float-to-half
truncation, half-to-float extension, and same-width integer/floating bitcasts
at 16/32 bits. Integer width changes require the correct direction. `trunc`
accepts `nuw`, `nsw` or both: unsigned/signed preservation of the source value
is required respectively, or the result is poison. `zext nneg` produces poison
for negative sources (including i1 true). These promises apply in the integer,
mixed scalar, void and memory profiles and add no execution steps. Other cast
flags, integer-pointer and aggregate casts, double and bfloat remain
unsupported. Pointer bitcasts and bounded address-space casts are described below.
Float-to-integer conversion truncates toward zero; NaN, infinity and values
whose truncated result is outside the destination range produce poison.
Poison inputs propagate. Selected undef still errors. Storing a poisoned cast
rejects; a later select can discard its poison result. All casts cost one step.

Direct `llvm.fptosi.sat`/`llvm.fptoui.sat` accept a scalar half/float input
and an i1..i64 result, with exact integer/floating overload widths in the name.
They truncate toward zero and clamp out-of-range values to the signed/unsigned
destination limits; either NaN class becomes zero. Infinities clamp, negative
unsigned inputs become zero, and signed i1 has range -1..0. Evaluation uses
integer arithmetic independently of host rounding modes and exception flags.
Poison inputs still propagate and selected undef errors; freeze/select and
poison-store rules remain in force. Calls cost one step, share scalar/void
validation and retain the existing intrinsic attribute/call restrictions.
Each signedness/source/result-width overload has a distinct declaration-cache
identity, separate from previous floating and integer families. Other floating
formats, aggregate results and malformed overload names reject. Fixed vector
overloads use the shared vector profile described above.

Floating `fneg` toggles only the sign bit of half/float, preserving zeros,
subnormals, infinities and NaN payload/quiet bits. Poison propagates; undef
rejects. Scalar `freeze` preserves defined i1..i64/half/float bits and makes a
fixed zero choice for poison or undef. Every use of its SSA result sees that
same choice. It does not prevent an earlier instruction from rejecting undef
or another dynamic error. Both operations require zero flags and cost one
step. General aggregate freezes remain unsupported by this API;
the checked overflow-pair exception is described below.

Pointer `freeze` preserves an already resolved virtual pointer and requires
exactly matching operand/result types. Pointer `bitcast` preserves that address
when both types are scalar pointers in the same address space. Both accept
arguments, GEPs, invariant PHIs/selects and earlier pointer identity operations.
Their results resolve during preflight and cost one executed step without
entering scalar value slots. Bounds, alignment and permissions stay attached
to the original argument and byte offset. Literal null, poison and undef
pointers reject during preflight. Freezing a pointer select does not bypass
its defined-condition requirement. Pointer-integer casts remain unsupported.

Scalar pointer `addrspacecast` supports all six distinct space-0/1/2 pairs in
this interpreter's flat virtual target. It preserves the binding identity and
byte offset; it does not construct or expose host addresses. An explicit
supported little-endian data layout must give both pointer types 64-bit size
and 64-bit index width. The existing per-profile layout table is reused and
freed after preflight. Missing, narrower, non-integral and other unsupported
layouts reject, as do flags, vector casts, same-space casts, literal pointers
and spaces outside 0/1/2. This is a target policy, not a promise that arbitrary
LLVM targets implement those casts as identities.

Cast results may feed GEPs, invariant PHIs/selects, identity operations,
comparisons, scalar accesses and memory intrinsics. Each executed cast costs
one step and never enters scalar value slots. Requirements stay on the
original argument. A space-2 argument cannot acquire write access by casting
it to another space. Nonempty scalar or intrinsic writes through a space-2
view also reject, even when the original argument is writable. Returning a
writable argument to a writable view preserves its original permission.
Zero-length intrinsics still add no read/write usage. Every block is checked,
including inactive writes, and aliased bindings retain distinct identities.

Direct LLVM integer bit intrinsics `ctpop`, `bitreverse`, `bswap`, `ctlz` and
`cttz` are supported using the scalar executor's declaration/signature,
attribute and value checks. Counts and reversal accept i1..i64; byte swap
accepts i16/i32/i48/i64. Zero-count calls require a literal defined i1
zero-poison flag. With that flag false, zero returns the width; with it true,
zero produces poison. Poison input propagates, undef input rejects, and
freeze may consume a poison result. Each call costs one step.

Direct LLVM `fabs`/`copysign` support half and float. Absolute value clears
the sign bit; copy-sign replaces the first operand's sign with the second's.
All other bits, including NaN payload and quiet/signaling bits, are preserved.
Copy-sign requires matching operand/result types and evaluates both operands.
Poison propagates and undef rejects, including in the sign donor. Each call
costs one step and shares scalar validation/evaluation. No floating arithmetic
or host rounding mode participates in these operations.

Direct LLVM `floor`/`ceil`/`trunc`/`round`/`roundeven` support matching half/float
operands and results. They round to integral floating values toward negative
infinity, positive infinity, zero, nearest with ties away from zero, and
nearest with ties to even, respectively. Zero results preserve the input sign;
infinities and already integral finite values are unchanged. NaNs use the
scalar evaluator's preferred quiet NaN choice. Poison propagates and undef
rejects. Each call costs one step and shares scalar validation/evaluation,
independent of host rounding mode.

Direct LLVM `rint`/`nearbyint` also support matching half/float operands and
results, rounding to nearest integral values with ties to even in LLVM's
default environment. They reuse scalar integer bit evaluation, preserving
zero signs and choosing the preferred quiet NaN. Poison propagates and undef
rejects. Each call costs one step. Host rounding modes and exception flags
do not participate; dynamic/constrained environments and exception modeling
remain outside this profile. Their declarations retain distinct cache slots
from each other and from `roundeven`.

Direct LLVM `sqrt` supports matching half/float operands and results. It uses
the scalar evaluator's integer root/remainder algorithm and rounds to nearest
with ties to even, independent of host rounding mode. Positive finite values
produce correctly rounded roots, signed zero retains its sign, and positive
infinity remains positive infinity. Negative nonzero inputs and NaNs produce
the evaluator's preferred quiet NaN. Poison propagates and undef rejects.
Each call costs one step and shares scalar validation/evaluation.

Direct LLVM `minimum`/`maximum` support matching half/float operands and results.
They propagate a NaN from either input, using the scalar evaluator's preferred
quiet NaN representation. Other results preserve the selected input bits;
negative zero sorts below positive zero in either operand order. Both operands
are evaluated; poison propagates and undef rejects. Each call costs one step
and shares scalar validation/evaluation.

Direct LLVM `minimumnum`/`maximumnum` also support matching half/float
operands/results. A single NaN of either class selects the numeric operand's
exact bits; two NaNs produce the preferred quiet NaN. Negative zero sorts
below positive zero in either operand order. Both operands are evaluated;
poison propagates and undef rejects even with a NaN counterpart. Each call
costs one step and shares scalar validation/evaluation.

Direct LLVM `minnum`/`maxnum` use the scalar evaluator's permitted
`minimumnum`/`maximumnum` refinement consistently: prefer the exact numeric
operand over either NaN class, use the preferred quiet NaN for two NaNs and
order negative zero below positive zero. Both operands are evaluated; poison
propagates and undef rejects even with a NaN counterpart. Each call costs one
step and shares scalar validation/evaluation. Legacy and modern declarations
keep distinct cache identities and may be mixed in one kernel.

Direct LLVM `is.fpclass` accepts a half/float input and a literal defined i32
mask from 0 through 1023, returning scalar i1. Bits 0..9 select signaling NaN,
quiet NaN, negative infinity/normal/subnormal/zero, positive zero/subnormal/
normal/infinity, respectively. Mask zero selects nothing; 1023 selects all
defined inputs. Classification reads raw bits, distinguishing signaling and
quiet NaNs without floating arithmetic or exceptions. Poison propagates even
with zero/full masks; undef rejects. Calls cost one step and share scalar
validation/evaluation. Parameter two's exact immarg is admitted; every call's
mask is checked even after its declaration is cached. Invalid masks reject
in preflight before earlier stores. The i1 result can feed select, casts and
stores; its byte store has zero high padding bits.

Direct LLVM `fma` accepts three matching half/float operands and result. The
scalar evaluator forms the exact product-plus-addend on fixed integer limbs
and rounds once to nearest with ties to even, independently of host rounding
mode. Finite cancellation, overflow avoidance and subnormal ties therefore
retain fused semantics. Defined zero/infinity/NaN cases use the scalar FMA
rules and preferred quiet NaN choice. All three operands are evaluated; poison
propagates and undef rejects, including with a zero product. Calls cost one
step and share scalar validation/evaluation.

Direct LLVM `fmuladd` supports the same three matching half/float operands
and result, consistently choosing the permitted fused evaluation through the
scalar FMA evaluator. It retains one nearest-even round and all FMA value,
poison/undef and budget rules; it does not reproduce another backend's choice
between fused and separate rounding. FMA and fmuladd declarations keep distinct
cache identities and may be mixed in one kernel. Constrained floating
operations remain unsupported by this buffer profile.

Direct LLVM `ldexp` supports a half/float value, a signed i32 exponent and a
matching floating result. Scaling by a power of two uses the scalar integer
unpack/pack evaluator with nearest-even rounding, independent of host rounding
mode. Overflow becomes signed infinity; underflow rounds through subnormals
to signed zero. Zeros and infinities preserve their bits even at INT_MIN/MAX
exponents; NaNs use the preferred quiet choice. Both operands are evaluated,
so poison/undef in the exponent is not bypassed for a zero value. Calls cost
one step and share scalar validation/evaluation. The exponent must be i32,
not the floating input's type or another integer width.

Direct LLVM `fshl`/`fshr` also support i1..i64. All three operands must match
the result type. The amount is reduced modulo the width, so equal operands
produce rotations and oversized amounts are defined. A zero amount selects
the first input for fshl and the second for fshr. All operands are evaluated;
poison propagates even in an otherwise unused half at zero shift, and undef
rejects. These calls reuse scalar evaluation and cost one step each.

Direct LLVM `smin`/`smax`/`umin`/`umax` support matching scalar i1..i64
operands and results. Signed variants use two's-complement ordering, including
i1 true as -1 and i64 minimum. Unsigned variants compare the raw masked words.
Both operands are evaluated; poison propagates and undef rejects. Results
preserve the chosen input bits. Each call costs one step and reuses the scalar
intrinsic validator and evaluator.

Direct LLVM `abs` supports i1..i64 and requires a literal defined i1
minimum-poison flag. With that flag false, the signed minimum retains its raw
bits; with it true, the minimum produces poison. Other defined inputs produce
their absolute-value bit pattern. Poison input propagates and undef rejects;
freeze can consume the poisoned minimum. Each call costs one step and shares
the scalar validator, immediate checks and evaluator.

Direct LLVM `sadd.sat`/`uadd.sat`/`ssub.sat`/`usub.sat` support two matching
scalar i1..i64 operands and results. Signed variants clamp to the signed
minimum/maximum; unsigned variants clamp to zero/unsigned maximum. Defined
arithmetic overflow saturates instead of producing poison. Poison operands
still propagate and undef rejects. Each call costs one step and reuses the
scalar validator and evaluator.

Direct LLVM `sshl.sat`/`ushl.sat` support matching scalar i1..i64 values,
amounts and results. Valid amounts below the width shift left and clamp to
signed/unsigned bounds. Amounts are interpreted as unsigned width-masked words;
amounts at or above the width produce poison, even for zero input. Amounts do
not reduce modulo the width. Poison operands propagate and undef rejects.
Freeze or select may consume/discard computed overshift poison. Each call
costs one step and shares scalar validation/evaluation.

Direct LLVM `pext`/`pdep` support matching scalar i1..i64 operands and results.
In low-to-high bit order, extraction packs the input bits selected by the mask
into low positions; deposition scatters low input bits to the mask's selected
positions. A zero mask yields zero and a full mask preserves the input.
Both operands are evaluated; poison propagates even with a zero mask or value,
and undef rejects. Each call costs one step and shares scalar validation/evaluation.

Direct LLVM `clmul` supports matching scalar i1..i64 operands and results.
It multiplies binary polynomials over GF(2), using XOR rather than carries,
and retains only the low result-width coefficients. Both operands are
evaluated; poison propagates even with a zero multiplier and undef rejects.
Each call costs one step and shares scalar validation/evaluation. The fixed
declaration cache reserves all 64 widths alongside the existing families.

Direct LLVM signed/unsigned add/subtract/multiply `*.with.overflow` calls
support i1..i64 inputs and literal unpacked `{iN, i1}` results. The shared
scalar evaluator retains the wrapped value and a separate overflow flag;
overflow keeps both fields defined. Input poison propagates to both fields
and undef rejects, including with a zero multiplier. `extractvalue` reads
field 0 or 1 after checking the complete pair shape, source type, result type
and field index. Each call and extraction costs one step. Extracted values
can feed scalar operations, freeze/select and scalar stores. Zero/poison pair
constants are admitted; other pair constants reject. General aggregate memory,
arguments and returns remain unsupported here.

`freeze` also accepts these literal unpacked overflow pairs. Defined fields
preserve their bits; each poison field independently chooses zero. A direct
undef pair chooses two zero fields, but an earlier undef scalar computation
still rejects. Both poison tags clear while the aggregate tag survives, and
the stored result slot keeps repeated uses consistent. Each freeze costs one
step and shares scalar validation/evaluation. Other pair constants, layouts,
field types and aggregate operations retain their existing restrictions.

Unflagged `select` also accepts these overflow pairs, with exactly matching
arm/result types and a scalar i1 condition. Only the chosen pair is read;
zero/poison pair constants are allowed, while undef pair constants reject
during preflight even in an unchosen arm. A poison condition makes both fields
poison and a later pair freeze chooses zero for each. Undef conditions and
earlier dynamic errors still reject. Selection copies both fields and poison
tags into the result slot and costs one step, using the scalar evaluator.

Unflagged `insertvalue` replaces field 0 or 1 of these pairs. Exactly one
literal index, matching source/result pair types and the field's exact scalar
type are required. Only that field and its poison tag change; defined
replacements repair a poisoned field, while poison replacements leave the
neighbor unchanged. Zero/poison base constants are allowed; undef bases reject
during preflight and undef replacements reject dynamically, even if a later
operation would overwrite or ignore the field. Each insertion costs one step
and shares scalar validation/evaluation. General aggregates, nested paths and
aggregate memory remain unsupported.

Scalar intrinsics require ordinary direct calls to these forty-seven families'
exact declarations:
no call-site attributes, fast-math flags, tail calls, indirect calls or other
scalar intrinsics. Harmless declaration properties and parameter two's immarg use
the existing scalar allowlist and cumulative attribute-work limit. Each
declaration's attributes are checked once per profile; each call's signature
and constant flag are checked independently. No declaration or host pointer
is invoked by execution. Unsupported calls after stores reject in preflight.

The memory profile additionally admits `llvm.memset.p0.i32/i64`,
`llvm.memset.p1.i32/i64` and zero-length `llvm.memset.p2.i32/i64`. These must
be ordinary void direct calls to exactly matching fixed declarations with an
i8 byte, defined literal i32/i64 length, and literal false i1 volatility flag.
The destination uses the existing resolved pointer sources. Nonempty calls
derive their full extent before execution and require write permission;
address space 2 rejects writes. Unannotated destinations use byte alignment.
Except for pointer alignment described below, call-site attributes reject.
Tail calls, volatile fills, dynamic/poison/undef lengths,
literal pointer destinations, atomic variants and general calls reject.

Declaration attributes admit the existing harmless function properties except
readnone/readonly/speculatable, fourth-parameter immarg, destination writeonly
and nocapture/captures(none), and memory(argmem: write) encodings 0/1/2.
Unknown attributes and other parameter properties reject. Declaration scans
share the existing cumulative work limit and run once per admitted overload.
The separate scalar and void APIs retain their prior intrinsic profiles.

A memset costs its instruction step plus one step per written byte. The static
budget sums lengths across all blocks/calls and must fit the million-step
limit before stores. Runtime reads a nonempty fill's byte once; poison/undef
errors before any of that fill's writes, preserving earlier stores. Untaken
fills do not read the byte. Zero length has no byte evaluation or write
requirement, so it permits poison/undef byte operands and empty readonly
bindings, including address space 2. Existing GEP extents and earlier executed
instructions still apply. Execution uses indexed byte writes without calling
host memset, exposing host addresses or allocating a fill buffer.

`llvm.memset.inline.pD.i32/i64` shares this bounded fill path, including the
runtime byte, literal length, false volatility, full preflight, one step per
byte and zero-length behavior. Inline fills also admit an optional length
immarg on their declarations, with independent length/volatile duplicate checks.
Ordinary and inline fills have separate fixed declaration-cache slots, allowing
both in one function. Indexed writes invoke no external declaration or host
fill routine and add no owned profile or execution array. Atomic fills remain
unsupported.

Nonvolatile `llvm.memmove.pD.pS.i32/i64` calls use the same exact void call,
constant-length and literal-false volatility checks. Destination spaces D=0/1
and source spaces S=0/1/2 support nonempty moves; D=2 only permits zero length.
Both pointers use the existing resolved sources, with full source read and
destination write extents checked before stores. Source readability and
destination writability combine normally when both name one binding.
Zero length adds neither read/write usage nor extent; existing GEP requirements
remain. Literal null/poison/undef pointers reject on either side even at zero
length. Inline/atomic variants and general calls remain unsupported.

Move declarations admit source readonly and nocapture/captures(none) as well
as the destination properties and fourth immarg; their canonical memory effect
is memory(argmem: readwrite), versions 0/1/2. Other attributes reject. Each
move costs one instruction plus two steps per byte (read and write), sharing
the cumulative million-step limit with fills, switches and ordinary instructions.
One scratch byte array per run is sized for the largest admitted move and freed
on every exit. Every move snapshots all source bytes before its first write,
including when distinct bindings or borrowed slices alias. Later moves see
earlier writes and reuse that scratch storage. No host address comparison or
host memmove call is used. The profile records only the scratch size, with no
new owned array in the cached profile.

Nonvolatile `llvm.memcpy.pD.pS.i32/i64` uses the same pointer/length, extent,
permission and two-steps-per-byte rules, sharing the transfer scratch array.
Memcpy declarations additionally admit canonical noalias on each pointer
parameter. Memmove still rejects noalias. This bounded memcpy profile requires
disjoint actual byte ranges: partial overlap and identical ranges reject before
any instruction executes. Every copy is checked, including later calls and
inactive blocks. Zero length skips overlap checks and adds no read/write usage.

The executor compares addresses of the borrowed backing-array views solely for
this overlap guard, after validating all bindings and budgets. This covers
different bindings and sliced views that alias even though their virtual
identities differ. Address bits never enter AIR value slots or become accepted
numeric pointer inputs. Copies still use indexed reads/writes and the existing
scratch storage, with no host memcpy call. Callers must keep bindings and data
stable throughout execution, as for all memory operations.

`llvm.memcpy.inline.pD.pS.i32/i64` uses the same bounded disjoint-copy path,
including resolved pointers, literal length, false volatility, permissions,
alignment, overlap preflight, reusable scratch and two steps per byte. It
never invokes an external declaration or host copy routine. Its declaration
may additionally mark parameter three (length) immarg; this does not relax the
literal check on any call. Both immarg slots have independent duplicate guards.
Ordinary and inline overloads use distinct fixed declaration-cache slots, so
both can appear in one function in either order. Atomic variants remain
excluded. No new owned profile or execution array is added.

Memory-intrinsic call sites admit only `align N` on the destination and, for
memmove/memcpy, source pointer arguments. N must be a power of two from 1
through 64 MiB. Each binding's required alignment combines the largest
requirement across all calls and ordinary accesses. The declared virtual base
alignment and binding offset must meet that combined requirement. Each derived
pointer offset must independently meet its own access requirement; a binding
offset cannot compensate for an unaligned derived pointer.
Zero-length calls still impose alignment, including in inactive blocks, while
adding no read/write usage. Other call attributes, including properties combined
with alignment, reject. Alignment-list scans share the cumulative declaration
work budget. A fixed sixteen-slot stack cache reuses decoded lists by their full
set identity; collisions revalidate the list. No owned profile array is added.
Software Metal retains its separate 256-byte virtual base-alignment limit.

`memory_function_profile` validates the supported signature and complete body
without accessing buffer data. Its owned `arguments` array describes required
address spaces, minimum extents, alignment and read/write usage; release it
with `profile.free()`. The executor uses the same validation, then checks
actual bindings and budget before execution. A store through address space 2
is rejected when building the profile.

GEPs resolve to a binding identity and a byte offset, using the existing ABI
layout/offset planner. They require an explicit little-endian data layout,
64-bit pointer/index widths. Literal, defined nonnegative i1..i64 indexes may
select arrays, structures (including packed fields), byte-addressable fixed
vector elements and chains of earlier GEPs. Every offset/stride/source
allocation size stays within 64 MiB; multiplication and addition are checked
before computing an offset. Negative indexes over supported scalars and nonempty
fixed aggregate paths subtract their layout stride without going below the
binding's logical base. The executor replays the validated type path, applying
each structure-field offset and scaled index in traversal order. Packed,
unpacked and nested nonzero field offsets can mix with negative indexes;
each prefix must stay within the binding's extent, even when later subtraction
lowers the final offset. The negative index magnitude
and scaled subtraction are checked before multiplication, including the signed
minimum index. The binding's own offset supplies no extra headroom.
Zero-stride negative indexes, scalable layouts, dynamic, poison/undef and wider
indexes reject. Constant-expression
pointers, integer-pointer conversions and numerical pointer inputs reject.

Known GEP inbounds/nusw/nuw flags are accepted within the forward,
nonwrapping profile. Backward GEPs accept plain, nusw and inbounds
(including historical inbounds encoding), but any nuw bit rejects. Unknown
bits reject. All intermediate offsets and unused GEP results must fit the
binding's extent. A one-past result is
allowed; dereferencing it needs additional bytes and rejects. Profiles retain
an owned per-instruction access table, released by `profile.free()`. GEPs cost
one step but never construct host pointers or enter the scalar value slots.

Each pointer argument binds to an IRMemoryBinding with borrowed mutable data,
a byte offset, declared virtual base alignment and write permission. At most
64 bindings of at most 64 MiB each are accepted. Address spaces 0 and 1 are
supported; space 2 requires a readonly binding. Pointer operands must directly
name arguments, earlier supported GEP results, invariant pointer PHIs/selects
or supported pointer freezes/bitcasts.
No numerical host pointers are accepted as AIR values.
Pointer comparisons accept `eq`, `ne`, `ugt`, `uge`, `ult` and `ule` for
exactly matching pointer types resolved to the same binding. Preflight compares
bounded offsets, including one-past addresses, without adding source reads or
access extents. Each executed comparison publishes a scalar i1 and costs one
step. Branches and scalar/pointer selects can consume it. Different bindings
reject even when their storage aliases, since their bases are unknown; signed
pointer ordering and literal null/poison/undef pointers also reject. Precomputing
a comparison does not bypass earlier pointer-select condition evaluation.
Bindings may share byte storage;
execution observes earlier stores through aliases. Callers retain ownership
and must prevent concurrent access/mutation during a run.

All accesses and instruction shapes are preflighted before any store. Bounds,
explicit power-of-two alignment and write permission are checked. Alignment
zero (unresolved ABI default) rejects. The virtual base must satisfy the
declared alignment; the binding offset must satisfy each access alignment.
Derived offsets must also satisfy the access alignment independently of the
binding offset; offsets that would compensate for an unaligned binding reject.
Big-endian layouts reject; without GEPs, absent layouts use this API's
little-endian profile.
Valid LLVM IR and matching immutable parsed indexes remain preconditions.

Loads assemble little-endian bytes and mask narrow integer padding bits.
Stores write only the scalar's ceil(bits/8) bytes, zeroing unused high bits.
Loads/stores preserve floating raw bits. Nonzero padding in a narrow integer
load uses the profile's masked defined choice rather than tracking LLVM load
poison. Native reference comparisons require zero input padding. Buffer bytes are treated as defined values;
uninitialized-memory/poison shadow tracking is not implemented. Poison stores
and selected undef reject. Dynamic value errors can leave earlier stores
visible; errors do not roll back memory. Every load, store, binary operation,
comparison, select, cast, fneg, freeze, intrinsic, GEP and return costs one step, with the existing
maximum step limit. Preflight rejects an insufficient budget.
Execution scratch arrays are freed on success and failure; binding data is not.

`tests/ios/air-memory-execute.v` assembles LLVM fixtures and checks 16,896 copies
against independent byte expectations, guards and constant stores. Execution is
also checked against native LLVM by `tests/ios/air-memory-arithmetic.v` for
load/compute/store bodies, including poison consumption and budget guards.
`tests/ios/air-memory-gep.v` compares indexed loads/stores with native LLVM,
including narrow padding, layouts, GEP flags, chains and preflight failures.
`tests/ios/air-memory-backward-gep.v` compares bounded backward scalar loads and
stores with native LLVM, including every scalar width and every index width,
aliased buffers, exact one-past intermediate extents and historical inbounds.
It checks budgets, permissions, intermediate bounds and rejected negative
profiles/flags before an earlier store.
`tests/ios/air-memory-backward-aggregate.v` checks negative allocation strides
for arrays, packed/unpacked structures and fixed vectors with scalar loads and
stores. It compares native LLVM results, aliases and exact one-past extents,
and rejects empty/oversized layouts and scaled underflow before stores.
`tests/ios/air-memory-multi-index.v` compares mixed-sign array/nested-array
paths and zero-offset structure fields with native LLVM. It checks prefix
extents independently of the final offset, exact one-past views, aliases,
flags/budgets and rejection of underflow that a later index would compensate.
`tests/ios/air-memory-structured-gep.v` compares mixed-sign packed/unpacked
and nested structure paths with native LLVM. It checks nonzero fields before
and after subtraction, exact prefix extents, aliases, field-prefix bounds and
underflow that a later field offset would otherwise hide.
`tests/ios/air-memory-casts.v` checks load/cast/store bodies against defined
native LLVM conversions, with separate poison and unsupported-input controls.
`tests/ios/air-constant-extract.v` compares literal vector extractions with
defined native LLVM across integer/half/float lanes, several vector/index
widths and constant forms. Independent lane expectations cover poison/undef,
index masking, padding, prior stores, budgets and preflight guards. Whole
functions test both memory and scalar lane-work limits before execution.
`tests/ios/air-vector-insert.v` compares chained insertions and old/new snapshot
extractions with defined native LLVM. It checks per-lane poison/undef, repairs,
all scalar lane formats, index masking, prior stores, metadata rejection,
scalar/integer APIs, loop slot reuse, step budgets and both public storage/work
limits. Native execution excludes indeterminate selections.
`tests/ios/air-vector-shuffle.v` checks both-source permutations, broadcasts,
duplicates, length changes, poison/legacy-undef masks, source indeterminacy,
shuffle/insertion chains and immutable snapshots against defined native LLVM
and independent state expectations. Metadata, mask identity, unsupported
profiles, loops, void discards, budgets and exact/over-limit storage/work
boundaries are checked separately.
`tests/ios/air-vector-freeze.v` compares unchanged defined lanes with native
LLVM and separately checks the permitted fixed-zero choices for indeterminate
lanes. Literal/computed/repeated/inserted/shuffled snapshots, original source
states, errors before freeze, poison after freeze, repeated uses, discard,
loop slot reuse, metadata rejection and exact/exceeded limits are covered.
`tests/ios/air-vector-select.v` checks both scalar condition values, chosen and
unchosen arm states, poison/undef conditions, condition masking, nested selects,
freeze/insertion/shuffle chains, snapshots, prior writes, void discards, loops,
metadata rejection and exact/exceeded limits. Only defined selections compare
with native LLVM; frozen choices and indeterminate failures use explicit oracles.
`tests/ios/air-vector-lane-select.v` adds mixed lane conditions, constructed
conditions, localized poison, chosen undef, condition/result freezing, discard,
condition source/type/shape mutations and exact/exceeded shared limits. Only
fully defined native choices are executed; freeze-dependent values use explicit
interpreter expectations. Its lane controls check full-buffer write ordering.
`tests/ios/air-vector-compare.v` covers all vector integer/half/float predicates,
integer `samesign`, fixed counts, boolean masks feeding selections, native
defined values, frozen mask choices, poison stores, undef rejection, source
and result snapshots, constant FP predicates, metadata/source/shape guards,
step budgets and shared storage/work boundaries through memory and void APIs.
`tests/ios/air-vector-binary.v` covers i1..i64, all thirteen integer opcodes and
thirty flag variants, raw/frozen/compared/selected results, defined native LLVM
values, independent poison and division guards, source/result freezing, old
snapshots, undef/poison discards, full-buffer write ordering, metadata/source/
shape guards, budgets and exact/exceeded shared construction/work limits.
Invalid native division and poison-valued native selections are never executed.
`tests/ios/air-memory-cast-flags.v` covers every i1..i64 flagged truncation and
extension shape in bounded modules. Defined inputs compare with native LLVM;
an independent range oracle checks poison without executing invalid native
casts. It also checks integer/mixed/void APIs, prior-write preservation,
budgets, preflight metadata rejection, and poison/undef/freeze/select chains.
`tests/ios/air-saturating-cast.v` checks all 256 signed/unsigned half/float to
i1..i64 saturation overloads against defined native LLVM, with exhaustive half
inputs at five destination widths, boundary/sample inputs, scalar argument
masking, poison/undef/choice rules, budgets, cached-call metadata/type guards,
mixed-family cache identities and host rounding/exception controls.
`tests/ios/air-memory-unary.v` checks fneg/freeze against native LLVM and exact
raw-bit expectations, all half encodings, and separate indeterminate choices.
`tests/ios/air-memory-flags.v` checks integer flags across all widths against a
defined widened LLVM value/poison-tag reference without executing native poison.
`tests/ios/air-bit-sign-promises.v` covers OR disjoint and all ten ICMP samesign
predicates across i1..i64. Only defined inputs execute natively; independent
carry/sign range checks decide poison. Integer/mixed/void APIs, narrow masking,
stores/branches, freeze/select, prior writes, budgets and unknown/noninteger
flag preflight controls share the decoded fixtures.
`tests/ios/air-memory-bits.v` checks bit intrinsic buffer functions against
defined native LLVM execution, with separate zero/poison/undef/call controls.
`tests/ios/air-memory-funnel.v` checks three-input funnel buffer functions,
rotation/amount boundaries and separate poison/undef/padding-choice controls.
`tests/ios/air-memory-extrema.v` checks signed/unsigned min/max buffer functions
against native LLVM, including boundary matrices and separate poison controls.
`tests/ios/air-memory-abs.v` checks absolute-value buffer functions, defined
native inputs, minimum-poison flags and per-call flag checks after cache hits.
`tests/ios/air-memory-saturating.v` checks saturating add/sub buffer functions
against defined native LLVM, boundary matrices and separate poison controls.
`tests/ios/air-memory-saturating-shift.v` checks valid native saturating shifts
and interpreter-only loaded/constant overshifts, zero overshifts and selection.
`tests/ios/air-memory-bit-permutation.v` compares extraction/deposition and both
round-trip chains against native LLVM, checks independent masked identities,
and exercises poison/undef, freeze/select, budgets and call-metadata controls.
`tests/ios/air-memory-float-sign.v` checks absolute value and copy-sign against
native LLVM and independent bit masks, including every half encoding, float
class/payload boundaries, cached-declaration chains and poison/undef controls.
Its native JIT uses the host CPU target to avoid generic ARM64 half-to-float
promotion quieting signaling NaNs; target receipts are saved with results.
`tests/ios/air-memory-rounding.v` compares all seven rounding operations with
native LLVM, including every half encoding, float class/tie/precision limits,
cached idempotent chains, host rounding modes and poison/undef controls. It
checks exact default-environment results and unchanged host exception flags
for rint/nearbyint, plus metadata/type rejection after cached calls and stores.
Arithmetic NaNs compare by class; the interpreter's preferred choice is
checked separately. Other results compare exact raw bits, including zero signs.
With a trailing `sqrt` argument, the same checker tests square root and
`sqrt(fabs(x))`, every half encoding, float midpoint-square neighbors across
the normal exponent range, domain/NaN cases and host rounding independence.
`tests/ios/air-memory-float-extrema.v` compares minimum/maximum and mixed cached
chains with native LLVM, including every half encoding with zero/unit anchors,
both precisions' class/NaN/zero-order matrices and independent chain identities.
`tests/ios/air-memory-fpclass.v` checks all 1024 masks against native LLVM and
independently labeled class boundaries, exhaustive half encodings under each
individual class and empty/full masks, i1 padding, cached-call immediate
validation, poison/undef and rounding/exception behavior.
`tests/ios/air-memory-fma.v` compares fused results and cached-call chains
against native LLVM, exhausts half inputs in two cancellation/scaling patterns,
checks boundary triples, and distinguishes fused results from separate
multiply/add for cancellation, overflow and underflow in both precisions.
It qualifies `fmuladd` against native FMA for the chosen fused refinement,
retains native optional-fusion diagnostics, and mixes both declaration names.
`tests/ios/air-memory-ldexp.v` compares scaling and zero-scale chains against
native LLVM, exhausts half inputs under signed scales, checks exponent limits
and subnormal ties, and rejects malformed later cached calls before stores.
The opt-in software Metal runner uses this profile for its bounded single-thread
compute pipeline. General shader execution and GPU dispatch remain pending.

`tests/ios/air-memory-clmul.v` compares all i1..i64 widths against native LLVM
and independent polynomial convolution, exhausts i1..i8 pairs, checks cached
distributive identities and rejects malformed later calls before stores.
`tests/ios/air-memory-overflow.v` compares all six overflow families at i1..i64
against native LLVM, exhausts i1..i8 pairs with independent widened arithmetic,
checks both extracted fields and rejects malformed extraction/cached calls
before earlier stores, alongside poison, constants and aggregate exclusions.

`tests/ios/air-memory-control.v` compares forward branch diamonds and nested
joins against native LLVM across all scalar integer widths, half/float and
overflow pairs. It checks exact path costs, conservative budgets, PHI
predecessors, inactive metadata/access requirements, lazy incoming values,
poison/undef/freeze, early returns and rejection of loops and varying pointer PHIs.

`tests/ios/air-memory-pointer-phi.v` compares invariant pointer PHIs with native
LLVM across all scalar widths, branch/switch/nested joins, mixed PHI orders,
direct/derived incoming pointers and aliases. It checks executed path costs,
budgets, bindings, malformed metadata/types/predecessors, unequal or invalid
incoming pointers and poison/undef branch conditions with earlier writes.

`tests/ios/air-memory-pointer-select.v` checks invariant pointer selects with
native LLVM across every supported scalar width, select/GEP/PHI chains, nested
joins and aliases. It checks metadata/types, budgets, bindings, unequal or
invalid arms, poison/undef conditions with used/unused results and prior writes,
and defined frozen conditions and untaken poison selects.

`tests/ios/air-memory-pointer-identity.v` compares pointer freeze/bitcast chains
with native LLVM through direct arguments, GEPs, selects, PHIs and nested joins.
It checks exact costs/extents, aliases, malformed shape/type/address-space
metadata, literal pointer exclusions and forbidden pointer conversions, and
verifies that freeze does not suppress earlier pointer-select condition errors.

`tests/ios/air-memory-pointer-compare.v` compares all six supported predicates
with native LLVM across spaces 0/1/2, direct/derived pointers and
PHI/select/freeze/bitcast chains. It checks scalar/select/branch consumers,
one-past extents without source reads, aliases, exact costs, budgets, bindings,
metadata/types, cross-binding and signed-predicate exclusions, and poison/undef
select conditions with prior writes, plus frozen and untaken conditions.

`tests/ios/air-memory-memset.v` compares all 256 fill bytes with native LLVM
across i32/i64 lengths, direct/derived destinations, pointer control chains,
aliases and zero-length indeterminate bytes. It checks exact extents, costs,
permissions, malformed call/type metadata, literal/volatile/length exclusions,
dynamic byte errors, frozen/untaken fills and cumulative/million-step budgets.
An optional trailing `inline` argument selects inline-fill overloads and adds
overlapping mixed ordinary/inline fills in both call orders. Invalid lengths
are also checked by retargeting decoded ordinary guards to matching inline
declarations. Rejection-only bodies are excluded from native compilation;
large inline budget bodies remain interpreter-only, and the projected
`native-input.bc` is saved.

`tests/ios/air-memory-memmove.v` compares i32/i64 moves with native LLVM,
including both overlap directions, identical/disjoint ranges, cross-binding
aliases and overlapping borrowed slices, pointer-control chains and repeated
moves of different lengths. It checks empty readonly bindings, exact extents
and costs, malformed metadata/types, forbidden pointers/attributes/lengths,
condition errors and cumulative/mixed/million-step budgets. Rejection-only
bodies remain in the interpreter fixture but are excluded from native
compilation; the verified native input is saved separately.

`tests/ios/air-memory-memcpy.v` compares disjoint copies with native LLVM and
rejects overlaps through direct bindings and borrowed slices before stores.
It covers adjacent ranges, zero length, pointer-control chains, scratch reuse
with shifted source data, exact costs/bounds, late and inactive overlapping
copies, excluded shapes/attributes/lengths and cumulative/mixed budgets.
An optional trailing `inline` argument selects inline-copy overloads, adds
mixed ordinary/inline sequences in both orders, and exercises the same copy,
alias, binding, metadata and budget checks. Large inline budget bodies remain
in the interpreter module but are omitted from native compilation to avoid
expanding hundreds of thousands of copy bytes into machine instructions.

`tests/ios/air-memory-alignment.v` compares aligned memset/memmove/memcpy
calls with native LLVM for both length widths, destination spaces 0/1 and
source space 2. Physically aligned backing views and shifted bindings exercise
destination alignments 1..64, independent source requirements, mixed calls and
cache collisions. Controls check weak base alignment, unaligned binding/derived
offsets, compensating offsets, inactive calls, unsupported combined attributes,
exact budgets and aligned empty readonly zero-length calls in spaces 0/1/2.
Its optional trailing `inline` argument substitutes inline fills and copies
for ordinary ones, including declarations without the optional length immarg.

`tests/ios/air-memory-address-space.v` compares all six admitted casts with
native LLVM across i1..i64, half and float, including round trips, pointer flow,
shifted and aliased bindings. It checks original argument requirements, exact
budgets, type/flag mutations, layout exclusions, readonly scalar/intrinsic
writes in active/inactive blocks, literal pointers, vectors, unsupported spaces,
zero operations and preservation of binding identities after conversion.

`tests/ios/air-memory-switch.v` compares every case/default path across all
integer widths and scalar/floating/pair PHIs against native LLVM, including
empty and 64-case edges and nested switches. It checks exact comparison costs,
65-case rejection, malformed literals/targets/metadata, inactive default blocks,
conservative budgets and poison/undef conditions with earlier writes retained.
