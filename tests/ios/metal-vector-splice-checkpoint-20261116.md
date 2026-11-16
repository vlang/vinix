# Software Metal vector splice checkpoint — 2026-11-16

Source revision: `8c3478b8633cc69af28a9742f0339f5a494e79b8`.

The AIR interpreter executes fixed 1..16-lane i1..i64/half/float
`llvm.vector.splice.left` and `.right` with unsigned scalar i32 runtime offsets,
following the [LLVM left](https://llvm.org/docs/LangRef.html#llvm-vector-splice-left-intrinsic)
and [right](https://llvm.org/docs/LangRef.html#llvm-vector-splice-right-intrinsic)
contracts. It copies a window of the concatenated vectors starting at offset
for left and N-offset for right. Offsets above N poison every lane. Copying
preserves raw bits, selected poison and deferred undef, including signaling NaN
payloads, signed zero and subnormals. Both memory APIs, scalar/void execution,
freezes, later insertion and vector-PHI slot reuse follow existing rules.
Integer-only execution excludes floating lanes; scalar undef offsets require
freeze before use. Calls cost one executed step, one shared vector slot and
3*N validation work units. Keys 37888..39999 append 2,112 distinct identities;
scalar cache entries remain 2,154. Existing metadata/signature/declaration,
scalable/wider-vector, vector-return and memory control-flow restrictions apply.

Pure integer address graphs add a splice-selector node using existing POD
fields. It guards the original selector and offset before computing the
concatenated index; existing lane-rebasing and projected-shuffle nodes select
the source. Selected undef stays deferred, and result freeze can repair offset
poison without repairing an invalid final extraction. Selector, offset and both
source dependencies contribute graph height. Existing 256-node/32-depth checks,
caching and profile cleanup remain; loaded vectors, vector PHIs and floating
address dependencies remain excluded. No owner or profile field is added.

`tests/ios/air-vector-splice.v` passes with ASan/UBSan:

- 712,800 cases across 66 formats, every count, both directions, five source
  forms and five constructions: 201,300 exact native raw values, 146,256
  explicit frozen choices, 320,628 poison results and 44,616 selected-undef
  failures. Both memory paths check every output byte, preceding markers,
  shifted bindings and nonmutating validation. Scalar/integer APIs pass
  1,425,600 checks; short memory budgets and metadata pass 105,600 and
  16,896 refusals respectively.
- 581,632 address API checks and 208,896 native address values cover all integer
  widths/counts/directions, every valid offset/selector pair, changing source
  values, maximum unsigned offsets/selectors and prewrite refusal.
- 18,240 typed-argument/loaded-vector lane copies cover all formats, counts
  1/3/16 and offsets 0/N/halfway. Loads cover the byte-aligned subset.
  Another 487 controls check selected states, result and offset freezes, scalar
  poison/undef offsets, discarded indeterminate vectors and duplicate names.
- 52 graph/resource checks scan both sides of depth/node limits: nine chained
  splices accepted versus ten rejected, and 250 shared extractions accepted
  versus 251 rejected. Eight checks cover memory/void admission at 4,096 versus
  4,097 slots and 1,000,000 versus 1,000,016 lane-work units. The work fixture
  uses 4,096 sixteen-lane splices plus 50,212 extractions; one extra rejects
  before writes. These use public admission rather than private graph storage.
- 120 exact native vector-PHI loop results, 192 scalar/integer checks and
  120 short executed-budget refusals cover i1/i7/i64/half/float, counts 1/3/16
  and 1, 2, 3, 7, 16, 257, 513 and 1,024 cyclic iterations.

Total new native comparisons: 410,316. Original AIR bitcode is LLVM-verified.
The native reference independently expands splices into index arithmetic,
extract/select/insert operations and runs LLVM always-inline before JIT. No
production splice evaluator is called. Native indeterminate results are not
observed; poison/undef and explicit freeze choices have separate checks.
The initial direct-intrinsic native run aborted during lowering. A first
expanded reference then disagreed at a v12i6 helper call; inlining removed that
call boundary and the focused i6 and complete final comparisons pass. Earlier
failing logs and IR are retained. This is an expanded native reference, not a
claim that LLVM directly lowers every admitted splice shape.

Units pass 3,620,864 raw lane/state comparisons, mirrored-direction identity,
source snapshots, poison offsets and all 2,112 canonical overload/key guards.
Existing reversal, rounding/cache, canonicalization and multiply-high units
pass; rounding checks all 40,000 cache entries with prior family intervals
preserved. The complete shuffle-index regression passes 879,093 exact outputs
and 919,947 prewrite refusals, including 123,670 selected-undef cases and 46
controls. Computed-index, prepared-memory, pointer-PHI and complete pair-freeze
self-test checks also pass. Other full intrinsic matrices and kernel/guest
builds were not repeated.

Fresh normal and deterministic software Metal processes each pass
106 geometry dispatches, 184 shader images, 289,234 checked invocations,
106 rejected pipelines and two prewrite bounds failures. The new image composes
dynamic left/right splices for integer coordinates and half/float values,
observing raw signaling-NaN payloads, negative zero and subnormal bits. Queued
dispatch, both selectors, clipped groups, RGBA8 buffer/texture readback,
padding, repeated commits and two drained runtimes pass.

Generated checker and focused host C confirm fixed vector records with no
array allocation in the splice lane evaluator. Existing owned result slots,
profile graph arrays and cleanup remain. Declaration caches gain 2,112 integer
entries. Existing boxed errors and machine/SSA/profile/graph allocations remain;
heap retention was not measured, leak detection was disabled and native JIT
code was not sanitizer instrumented. This extends CPU software Metal. Native
GPU execution, Fortnite launch gates, a Fortnite frame and complete Metal
support remain unverified.

## Retained evidence

Canonical original workspace:
`/Users/alex/Library/Caches/vinix-ios/vector-splice-20261116-r1`.

Complete archive:
`/Users/alex/Library/Caches/vinix-ios/vector-splice-20261116-r1.tar.gz`.

- Archive SHA-256: `479932d0cf78e70dabc663fe6f4a1f1d70e12671d7e05659093c6a9340d26a50`.
- Complete typed inventory: sibling `.inventory.json`, SHA-256 `6b5f11b72905bb5d640dd21ecae8daff739b94e7727cbd70880783cf2eefab73`.
- Source snapshot: workspace `source.tar`, SHA-256 `fedec448c314a81bc2a183b2d288c9c376d1afe91a8e42e9f2afbe102bb1e0e7`.

Inventory and archive checks compare every path, type, mode, link, size and
logical file hash, including root mode. Originals remain retained. This records
integrity without restoration replay or permission to delete evidence. Source,
commands, executable/tool identities, native targets, generated C, attempts and
sanitizer logs remain; sealing receipts are siblings outside the sealed workspace.
