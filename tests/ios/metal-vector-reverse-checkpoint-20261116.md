# Software Metal vector reverse checkpoint — 2026-11-16

Source revision: `556a3af687f86a6adeb5eb85550b2709e2140174`.

The AIR interpreter executes `llvm.vector.reverse` for fixed 1..16-lane
i1..i64/half/float vectors, following the
[LLVM reverse contract](https://llvm.org/docs/LangRef.html#llvm-vector-reverse-intrinsic).
It copies raw lane encodings and permutes poison/undef tags without floating
arithmetic. Signaling NaNs, payloads, signed zero and subnormals retain their
bits. Undef remains deferred until an observing consumer, so unused undef
results may be discarded and source/result freezes can repair indeterminate
lanes. Scalar, void and both memory APIs admit exact ordinary direct calls;
integer-only execution excludes floating lanes.

Pure integer address graphs map the selector using two packed shuffle words
and existing shuffle-selector/projected-shuffle nodes. Invalid selectors poison
the projection; selected undef remains deferred through a later freeze. The
parent projection and final node retain existing cache/height/capacity checks.
Loaded vectors, vector PHIs and floating dependencies retain address exclusions.
No node kind or profile owner is added. Calls cost one executed step, one shared
vector slot and 2*N validation lane-work units. Keys 36832..37887 append 1,056
identities, distinguishing integer and floating formats with equal widths;
scalar cache entries remain 2,154. Existing flags, declaration attributes,
scalable/wider-vector, vector-return and memory control-flow restrictions apply.

`tests/ios/air-vector-reverse.v` passes with ASan/UBSan across all 66 element
formats, every count 1..16, five source forms and six constructions:

- 332,640 cases: 99,726 exact native raw values, 58,608 explicit frozen choices,
  145,728 poison results and 28,578 selected-undef failures. Native NaNs compare
  exact payload/signaling bits. Poison/undef and chosen freeze values are checked
  separately, without observing indeterminate native results.
- 665,280 scalar/integer API checks, 63,360 short memory budget refusals and
  16,896 metadata refusals. Both memory APIs check output bytes, preceding
  markers, shifted bindings, nonmutating prepared validation, double reversal
  and independent snapshots after a later insertion.
- 21,504 address API checks and 8,704 exact native address values cover all
  integer widths/counts, changing selectors/inputs and prewrite out-of-range
  refusal. Another 3,040 typed-argument/loaded-vector lane copies cover all
  formats and the byte-aligned load subset at counts 1, 3 and 16.
- 35 selected-state, source/result freeze, unused poison/undef and duplicate
  declaration controls; and 44 graph/resource checks. The scanned fixtures
  admit 14 chained reversals and reject 15, and admit 252 shared extractions
  and reject 253 under the existing depth/node limits. Public admission results
  are checked; private profile internals are not exposed.
- Eight memory/void resource checks cover 4,096 versus 4,097 slots and
  1,000,000 versus 1,000,016 lane-work units. The work boundary comprises
  4,096 sixteen-lane unary calls and 54,308 extractions; one extra extraction
  rejects before writes.
- 120 exact native vector-PHI loop results, 192 scalar/integer checks and
  120 executed-budget refusals cover i1/i7/i64/half/float, counts 1/3/16 and
  1, 2, 3, 7, 16, 257, 513 and 1,024 iterations. Odd/even cycles preserve
  signaling NaNs and exercise reuse of stable result slots.

Total new native comparisons: 108,550. Units pass 8,912,896 raw lane/state
comparisons with double-reverse identity and source snapshots, plus all 1,056
canonical overload/key identities and name/count/tag guards. Existing rounding
units pass 7,340,032 rational checks and complete coverage of 37,888 vector
cache entries. Canonicalization and multiply-high units pass their complete
maintained checks; their broader reference matrices were not repeated.

The complete shuffle-index regression passes 879,093 exact outputs and
919,947 prewrite refusals, including 123,670 selected-undef cases and 46 controls.
Computed-index, prepared-memory, pointer-PHI and the complete pair-freeze self-test
also pass. These retain their existing native/reference counts and controls;
other full intrinsic matrices and kernel/guest builds were not repeated.

Fresh normal and deterministic software Metal processes each pass
106 geometry dispatches, 176 shader images, 280,358 checked invocations,
106 rejected pipelines and two prewrite bounds failures. The new image reverses
integer coordinates for addressing and observes raw float/half signaling-NaN
payloads, a half negative zero and a half subnormal in its red channel. Queued
dispatch, both selectors, clipped groups, RGBA8 buffer/texture readback, padding,
repeated commits and two drained runtimes are checked.

Generated checker and host C confirm fixed vector records and packed selector
words, with no array allocation in the lane evaluator. Existing result
slots and profile-owned graph arrays retain their cleanup; boxed V errors and
existing machine/profile/SSA allocations remain. Declaration caches gain 1,056
integer entries. Heap retention was not measured, leak detection was disabled
and native JIT code was not sanitizer instrumented. This is CPU software Metal
evidence. Native GPU execution, Fortnite launch gates, a Fortnite frame and
complete Metal support remain unverified.

The initial checker compile tried to inspect private graph storage; its retained
diagnostic led to admission scans at both graph boundaries. Corrected matrices
and the final checker with loop coverage pass without unexpected runtime or
sanitizer failures. Earlier source variants and results remain retained.

## Retained evidence

Canonical original workspace:
`/Users/alex/Library/Caches/vinix-ios/vector-reverse-20261116-r1`.

Complete archive:
`/Users/alex/Library/Caches/vinix-ios/vector-reverse-20261116-r1.tar.gz`.

- Archive SHA-256: `7c1d24aa3ba3fe5634c8f45efd63f7a0ec69139b3cb9d2fe4318d2bddb51df09`.
- Complete typed inventory: sibling `.inventory.json`, SHA-256 `7ef65d2a5f444f209514a078aa7fa72401971476538273985d6461fc4acce2d4`.
- Source snapshot: workspace `source.tar`, SHA-256 `7f2d6066126e47852b60be03b174bfcf60f1b98247ade2f601ed54614b379f01`.

Inventory and archive checks compare every path, type, mode, link, size and
logical file hash, including root mode. Originals remain retained. This records
integrity without restoration replay or permission to delete evidence. Source,
commands, executable/tool identities, native targets, generated C, attempts and
sanitizer logs remain; sealing receipts are siblings outside the sealed workspace.
