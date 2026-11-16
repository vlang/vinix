# Software Metal vector PHI checkpoint — 2026-11-16

Source revision: `b115dd173d59f05149bbc107b8d8b6ba115d78a0`.

The AIR interpreter carries fixed 1..16-lane i1..i64/half/float vectors through
PHIs. It selects only the executed predecessor, preserving raw encodings and
lane poison/undef. Incoming values are checked at their predecessor edges,
following the [LLVM PHI contract](https://llvm.org/docs/LangRef.html#phi-instruction).
Selected vectors are copied into a bounded snapshot buffer before any PHI is
assigned, then copied into stable vector result slots. This prevents aliasing
during simultaneous swaps and reuse of constructions across loop visits.

Integer/scalar and void APIs admit vector PHIs, including scalar-loop
backedges and producers later in the instruction stream. Integer-only execution
excludes floating lanes. Memory APIs preserve forward-only control flow and
admit constants, typed arguments, earlier constructions and loaded vectors at
joins. Pointer/scalar/pair PHIs retain their paths and may interleave with
vector PHIs. Pure address graphs still reject vector PHI dependencies.
Fast-math PHIs, scalable/wider vectors, vector returns and general aggregates
remain excluded; valid LLVM IR and immutable indexes remain preconditions.

Each vector PHI costs one executed step, N*(incoming-count+1) validation work
units and one of the existing 4,096 construction slots. Both execution paths
allocate one additional snapshot array per call, sized by the profiled vector
PHI count and bounded by that slot limit. Blocks reuse this buffer, and deferred
cleanup releases it on success and error. Profile additions are integer counts;
existing ownership and prepared-profile cleanup stay unchanged. All 34,752
declaration cache identities stay unchanged.

`tests/ios/air-vector-phi.v` passes with ASan/UBSan across all 66 element formats
and every count from 1 through 16:

- 421,344 branch cases: 331,056 defined/frozen values, 50,160 poison results and
  40,128 strict undef failures. Scalar, integer where applicable, and both memory
  APIs check values, every destination byte, earlier markers, shifted bindings,
  nonmutating validation and source/result freeze behavior. Scalar/integer
  branch checks total 829,920. Unselected, unavailable branch constructions
  are not read; selected undef remains tagged until an observing instruction.
- 215,424 exact native branch comparisons and 27,720 exact native loop
  comparisons, including floating NaN payload/signaling bits as raw data.
  Loop cases rotate three interleaved vector/scalar PHIs with and without a
  reversed construction on the backedge, for 0, 1, 2, 3, 7, 16 and 1,024 visits.
  An independent fixed-array simulation checks the expected rotation.
  Native references execute only defined inputs; poison/undef/freeze choices
  are checked separately in the interpreter.
- 421,344 short memory budgets reject before writes; 4,620 scalar-loop short
  budgets reject at the executed step limit. There are 660 memory-loop and
  384 floating-to-integer-API exclusions, preserving the existing boundaries.

`tests/ios/air-vector-phi-controls.v` passes 36,432 void observations; 144 typed
argument/loaded-vector copies through both memory APIs with interleaved pointer
and scalar PHIs; 17 malformed metadata/source/address refusals; and eight
exact storage/work boundaries. The latter cover 4,096 versus 4,097 vector PHIs
and 1,000,000 versus 1,000,001 lane-work units in memory/void APIs. The work
boundary comprises one 16-lane/two-input PHI (48 units) and 62,497 extractions
(999,952 units). All invalid admission/budget cases retain the output bytes.

The snapshot unit suite passes 731,136 independent lane/state comparisons for
seven successive three-way rotations, stable owned slots, poison/undef and
availability/snapshot guards. Pair-flow, vector-select and rounding units pass,
including complete cache coverage. Twenty-five legacy vector checker programs
now test marker-only success for their formerly rejected PHI fixtures; all
their focused control drivers pass. Select, shuffle, freeze and lane-select
drivers use six representative element formats; other focused control suites
run their complete default coverage. Their broader full matrices were not
repeated. Derived drivers preserve all maintained functions, replacing only
the entry point.

Computed-index passes 26,029 native exact cases, 50,771 prewrite refusals and
4,096 coordinate cases; prepared memory passes 28,928 byte comparisons and
3,314 recovery/bounds/budget/metadata controls. Pointer-PHI regression and the
complete pair-freeze self-test pass, including 524,288 native defined/property
comparisons. Modern number reduction, sequential reduction and integer reduction
address controls pass 82, 161 and 150 checks. Other full reduction matrices
were not repeated.

Fresh corrected normal and deterministic software Metal processes each pass
106 geometry dispatches, 152 shader images, 253,730 checked invocations,
106 rejected pipelines and two prewrite bounds failures. The new image branches
on the x coordinate, joins constructed float vectors and a scalar tag through
PHIs, reduces the chosen vector and includes the result in its red channel.
Checks cover queued dispatch, RGBA8 buffer/texture readback, padded bytes, both
dispatch selectors, clipped groups, repeated commits and two drained runtimes.

Generated checker and host C use fixed records and array copies in the PHI
read/assignment helpers, with no per-step array allocation or push. Snapshot
references do not escape; result slots retain their owned vector identities.
Deferred snapshot frees accompany existing result/scratch frees on return/error
paths. No evaluator kind or address node field is added. Existing allocations
and error paths remain; heap retention was not measured, leak detection was
disabled and native JIT code was not sanitizer instrumented. Broad runtime and
kernel/guest builds were not repeated.

Initial derived-driver compile diagnostics, a pair-freeze CLI usage failure
and a duplicate fixture declaration that stopped the first host run at LLVM
assembly are retained. Corrected drivers, invocation and fresh host builds all
pass; the main matrix, dedicated controls and units have no runtime/sanitizer
failures. An ownership-receipt assertion was corrected to check both captured
compilers' explicit array-constructor forms. Original artifacts remain.

This is CPU software Metal evidence. Native GPU execution, guest/Fortnite
launch gates, a Fortnite frame and complete Metal support remain unverified.

## Retained evidence

Canonical original workspace:
`/Users/alex/Library/Caches/vinix-ios/vector-phi-20261116-r1`.

Complete archive:
`/Users/alex/Library/Caches/vinix-ios/vector-phi-20261116-r1.tar.gz`

- Archive SHA-256: `16af54fcd4af465c26a1db8b4fa15ff6458942fb5d414ccbe237ce001de294e8`.
- Complete typed inventory: sibling `.inventory.json`, SHA-256 `85e078176d8e97081f8982086005345892c17dfde6ce5a65912743e170accdcf`.
- Source snapshot: workspace `source.tar`, SHA-256 `0e27e1228c09faf7e38d6aed60dfe9f8e7277d995f3b5986737c915a48190bcb`.

Inventory and archive checks compare every path, type, mode, link, size and
logical file hash, including root mode. Originals remain retained. This records
integrity without claiming restoration replay or authorizing deletion.
Commands, source revision, compiler/executable identities, LLVM target/features,
generated C, failed attempts and sanitizer logs are retained. Sealing commands
and statuses are siblings outside the sealed workspace.
