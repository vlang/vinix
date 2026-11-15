# Scalar leading and trailing zero counts

The mixed scalar interpreter accepts `llvm.ctlz.iN` and `llvm.cttz.iN` for
every N from 1 through 64. Each takes an iN value and a constant i1 flag and
returns iN. `ctlz` counts leading zeros; `cttz` counts trailing zeros. Zero
input with a false flag returns N; with a true flag it produces poison.
Other inputs return exact counts. Incoming high bits are masked before testing
for zero. Poison input propagates and selected undef errors. The integer-only
API rejects these scalar intrinsic calls. Vector leading/trailing-zero calls are supported
through both scalar execution APIs as described below.

Production uses a bounded loop of at most N unsigned bit tests, with shifts
only in 0..N-1. It uses no host builtin, LLVM, FP or new allocation. Evaluation
returns a value/poison pair; untagged numeric evaluators explicitly reject these
operations so no poison payload is silently consumed. A CALL costs one executed
instruction and primitive CALL/return takes two.

The [existing direct-call profile](SCALAR-INTRINSICS.md) checks canonical names,
exact integer width/signature/arity, declaration identity, external linkage,
calling convention, default address space, explicit-type header and flag/attribute
policy. The second operand must resolve to a nonsplat integer/zero constant of
type i1, with raw value 0 or 1. Arguments, SSA results, declarations, opaque/
poison/undef constants and malformed types/values reject. Every call is checked,
including in dead blocks and after another call cached its declaration attributes.
Only `is.fpclass`, `ctlz`, `cttz` and integer `abs` admit parameter two's exact
enum `immarg`
attribute; other parameter/return/string/type attributes still reject. Valid
LLVM IR and matching immutable indexes remain preconditions.

The 1384-entry fixed stack cache reserves forty floating-overload slots and
twenty-one separate 64-width integer ranges. `ctlz` and `cttz` use separate ranges;
their two flag values share a declaration identity, not a cached immediate.
The shared 1,000,000 attribute-work budget and fixed two-ID group storage remain.
The existing three owned execution arrays and cleanup are unchanged. Retained
allocation is not measured.

`scalar_zero_count_test.v` passes **1,310,712** standard-library comparisons
over both operations, every width and both flags (128 poison results), with
all i1..i16 inputs exhausted and 4,096 wide patterns. Explicit zero boundaries,
name/width/arity guards and rejection by untagged evaluators also pass.

`tests/ios/air-zero-count.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates and
LLVM-verifies 256 primitive functions, one per operation/width/flag combination.
Every narrow input is exhausted; wide inputs receive 4,096 mixed-bit patterns.
All overloads also receive zero/all-one/sign/alternating/byte patterns and every
single-set/single-clear bit, with high-bit noise. **1,329,400** exact value/tag
comparisons pass: 1,329,226 defined values and 174 poison results.

The reference wrapper computes the expected poison tag independently from the
input's zero test and constant flag. Before a native true-flag call on zero,
it substitutes one; defined zero cases still use actual zero. Native execution
never evaluates a poison-producing intrinsic. Poison result bits are ignored;
the tag, type, width and steps are checked. This avoids assuming that LLVM's
choice to refine poison to a value establishes an exact poison oracle.

Controls check 128 poisoned inputs, 128 undef rejections, 256 budget/integer-API
rejections, 256 mixed-flag results, 128 nonconstant flags after cached attributes,
fourteen metadata corruptions, twenty-four malformed flags, twelve result
corruptions (including lost poison tags), and two invalid flags in dead blocks.
LLVM/JIT/native code is not sanitizer-instrumented. The tool executes only its
own fixture; source/IR/bitcode, every comparison, binaries, identities and logs
are preserved in complete external bundles.

This is scalar execution groundwork. No AIR shader, Metal device, GPU command
or application launch is qualified.

## Vector leading-zero count

Ordinary direct `llvm.ctlz.vNiW` calls admit fixed 1..16-lane integer vectors
with widths i1..i64, returning the identical vector type. A scalar constant i1
flag chooses a defined count W or poison for zero lanes. Vector trailing-zero
count uses the same rules below. Every call validates its immediate, including calls
after declaration attributes were cached. SSA results, arguments, poison/undef,
splats, wrong types and raw values outside 0/1 reject before execution.

The common direct-call/header/signature/source guards apply. Parameter two
may have the exact `immarg` attribute; return/other parameter attributes and
other immarg encodings reject. The integer-only, mixed scalar, void and memory
APIs support these vector calls. Floating producers still require mixed
execution. Poison propagates per lane, any undef source lane fails even for
discarded results, source freezes choose zero for indeterminate inputs and
result freezes choose zero for poison. A repaired zero source can therefore
produce poison with a true flag. Results are independent snapshots.

The existing scalar leading-zero evaluator supplies value/poison results;
untagged integer evaluators continue to reject these operations. The normal
lane path adds no allocation. Slots 2752..3775 add 1,024 width/count identities
to the shared vector declaration cache. Trailing-zero identities follow them;
the cache now has 10,944 stack entries. Flag values
share an identity but are read separately per call. A call costs one step,
two lane counts of profiling work and one shared construction slot. Existing
4,096-result and 1,000,000-work limits remain unchanged.

`vector_zero_count_intrinsics_test.v` checks 2,065,472 value/poison lane
comparisons with the standard-library leading-zero counter adjusted to the
declared width, including both flags, every i1..i16 encoding, wide patterns,
individual bits, high-bit noise and snapshots. Another 208,896 lane-state
checks cover poison/undef/freezes. The shared cache unit covers all 10,944
identities. Existing units replace newly supported vector name guards with
unsupported vector-abs guards; untagged evaluator rejection remains tested.

`tests/ios/air-vector-ctlz.v LLVM_AS FRESH_EXTERNAL_DIR` exercises all widths,
counts and both flags through 51,200 decoded shapes, native defined-value
comparisons, independent poison checks and both scalar APIs. Bulk comparisons
exhaust narrow encodings for a false flag and nonzero encodings for a true flag,
plus 4,096 wide patterns per flag. True-flag zero bulk inputs use one so the
native calls have defined results; zero/poison checks remain in matrix and unit
cases. Controls repair each cached-flag fixture as a positive baseline before
rejecting its SSA/argument/poison/undef immediate. Raw flag words, immarg slots/
encodings, cold widths, exact budgets and shared limits are also checked.

The software Metal fixture adds 448 dispatches per runtime across 144 kernels:
384 complete and 64 fail as expected. Cases include both flags, explicit zero,
source/result freezes, snapshots, chains, deferred writes and sparse bindings.
A source freeze can still fail a true-flag call on zero; a result freeze repairs
the poison. Retained heap and GPU rendering have not been qualified.

## Vector trailing-zero count

Ordinary direct `llvm.cttz.vNiW` calls support fixed 1..16-lane integer vectors
with widths i1..i64, returning the identical vector type. They share the leading-
zero profile above, including per-call validation of a scalar constant i1 flag,
second-parameter `immarg`, strict undef, lane poison, freezes and snapshots.
A false flag returns W on zero; a true flag produces poison. Nonzero lanes count
least-significant zero bits through the existing scalar poison-aware evaluator.
No new allocation is added on the normal lane path. Both scalar APIs, void and
memory execution support these calls; floating producers still need mixed execution.

Slots 3776..4799 add 1,024 distinct width/count identities after leading-zero
counts. Funnel shifts and integer extrema add another 6,144 identities, making
10,944 shared stack entries. The two zero-count operations and both flag values
retain their independent meanings: flags share an operation/shape identity and
are validated on every call, even after declaration attributes are cached.
Work, construction storage, step budgets and existing limits are unchanged.

`vector_trailing_zero_intrinsics_test.v` uses the standard-library trailing-zero
counter on masked inputs, handling zero separately at the declared width. It
checks 2,065,472 value/poison lane comparisons and 208,896 lane-state checks,
including both flags, every i1..i16 encoding, wide patterns, individual bits,
high-bit noise, snapshots and family/name/shape/tag guards.

`tests/ios/air-vector-cttz.v LLVM_AS FRESH_EXTERNAL_DIR` checks all widths/counts
and both flags using the same 51,200-shape matrix as leading-zero count, plus
655,424 exact native bulk comparisons. The independent oracle counts trailing
zeros; native calls execute only defined inputs/results. True-flag zero bulk
patterns use one, while separate matrix/unit cases check zero poison. Positive
repairs precede cached nonconstant/SSA/poison/undef flag refusals. Raw flag words,
immarg positions/encodings, cold widths, exact budgets and shared limits are checked.

The software Metal fixture adds 448 dispatches across 144 kernels per runtime:
384 complete and 64 fail as expected, including both flags, zero inputs, source/
result freezes, construction paths, chains, deferred writes and sparse bindings.
Tail calls and i65 pipelines reject. Retained heap and GPU rendering are unqualified.

References: [LLVM ctlz](https://llvm.org/docs/LangRef.html#llvm-ctlz-intrinsic),
[LLVM cttz](https://llvm.org/docs/LangRef.html#llvm-cttz-intrinsic),
[poison refinement](https://llvm.org/docs/LangRef.html#poison-values).
