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
other vector operations. Floating vector binary arithmetic remains unsupported.

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
