# Software Metal vector interleave checkpoint — 2026-11-16

Source revision: `bd3ea34f496ac00935cd69407510102fc432934a`.

The AIR interpreter executes `llvm.vector.interleave2` through `interleave8`
for fixed i1..i64/half/float vectors with at most 16 result lanes, following the
[LLVM interleave contract](https://llvm.org/docs/LangRef.html#llvm-vector-interleave2-3-4-5-6-7-8-intrinsic).
Each of F inputs has K lanes; the result contains F*K lanes in input0[0],
input1[0], ..., input0[1], input1[1], ... order. All 26 admitted factor/count
shapes preserve raw bits and selected poison/undef tags, including signaling
NaNs, signed zero and subnormals. Undef observation remains deferred, allowing
unused results to be discarded and source/result freezes to repair lanes.
Integer-only execution excludes floating types. Scalar, void and both memory
APIs retain exact direct declaration/signature/metadata checks. A call costs one
executed step, one existing vector slot and 2*result_count validation work units.
Keys 40000..41715 append 1,716 identities without moving older intervals; scalar
cache entries remain 2,154. Existing scalable/wider-vector, vector-return and
memory control-flow restrictions remain. Deinterleave aggregate results are
outside this change.

Pure integer address graphs use two packed shuffle words, existing selector and
rebasing nodes, a fixed eight-parent table and nested projected-shuffle choices.
Invalid selectors poison the extraction before writes; unchosen poison/undef
does not propagate. All source heights and capacity costs are checked. Existing
256-node/32-depth limits, source-plus-selector caching and profile cleanup remain;
loaded vectors, vector PHIs and floating address dependencies remain excluded.
No node kind, owner or profile field is added.

`tests/ios/air-vector-interleave.v` passes with ASan/UBSan:

- 498,300 cases across 66 formats, all 26 factor/count shapes, five source forms
  and five constructions: 161,832 exact native raw values, 105,336 explicit
  frozen choices, 198,000 poison results and 33,132 selected-undef failures.
  Both memory APIs check every output byte, preceding markers, shifted views
  and nonmutating validation. Scalar/integer APIs pass 996,600 checks; short
  memory budgets and metadata pass 85,800 and 13,728 refusals respectively.
- 38,656 address API checks and 16,000 native address values cover every integer
  width/shape and selector, changing source values, upper-bit masking and
  prewrite invalid-selector refusal. Another 38,000 typed/loaded lane copies
  cover all formats and shapes; loads cover the byte-aligned subset.
- 687 controls check selected poison/undef, result freezes, discarded
  indeterminate vectors and duplicate declarations. Seventy graph/resource
  checks scan interleave/shuffle cycles and shared-extraction limits using
  public admission. Recorded maxima: `factor2=4 factor8=2, 245 shared extractions`. Each next larger fixture is
  rejected. Eight checks cover memory/void admission at 4,096 versus 4,097
  slots and 1,000,000 versus 1,000,016 work units. The work fixture uses 4,096
  sixteen-lane eight-input calls and 54,308 extractions; one extra rejects
  before writes.
- 1,040 exact native vector-PHI loop results, 1,664 scalar/integer checks and
  1,040 executed-budget refusals cover every factor/count shape at
  i1/i7/i64/half/float and 1, 2, 3, 7, 16, 257, 513 and 1,024 iterations.
  Calls and shuffles feed reusable PHI slots while preserving raw NaN bits.

Total new native comparisons: 178,872. Original AIR bitcode is LLVM-verified.
The independent native reference expands interleaves into constant extracts
and inserts and runs LLVM always-inline before JIT. It calls no production
interleave evaluator. Native indeterminate results are not observed; poison,
undef and explicit freeze choices have separate checks. This is an expanded
native reference rather than a claim about direct native intrinsic lowering.

The initial combined control module exceeded the unchanged reader record limit
after all format batches passed. The maintained checker now partitions address
and typed/loaded cases into nine modules and keeps state/graph/resource guards
in group zero. Aggregate coverage assertions preserve every case. The complete
qualified rerun passes. The rejected module and diagnostics remain retained;
reader and execution limits were not relaxed.

Units pass 1,024,000 raw lane/state comparisons, source snapshots and all 1,716
canonical overload/key identities and shape/name/tag guards. Splice, reverse,
rounding/cache, canonicalization and multiply-high units also pass; cache checks
cover all 41,716 entries with earlier family intervals intact. The complete
shuffle-index regression passes 879,093 exact outputs and 919,947 prewrite
refusals, including 123,670 selected-undef cases and 46 controls. Computed-index,
prepared-memory, pointer-PHI and full pair-freeze self-test checks pass. Other
full intrinsic matrices and kernel/guest builds were not repeated.

Fresh normal and deterministic software Metal processes each pass 106 geometry
dispatches, 192 shader images, 298,110 checked invocations, 106 rejected pipelines
and two prewrite bounds failures. The new shader observes integer coordinates
from eight inputs, raw float NaNs from three inputs and half payload/negative
zero/subnormal bits from two inputs. Queued dispatch, both selectors, clipped
groups, RGBA8 buffer/texture readback, padding, repeated commits and two drained
runtimes pass.

Generated checker and focused host C confirm fixed source/result records and
parent tables, with no array allocation in the interleave lane evaluator.
Existing owned result slots, graph arrays and cleanup remain. Declaration
caches gain 1,716 integer entries. Existing boxed errors and machine/SSA/profile
allocations remain; heap retention was not measured, leak detection was disabled
and native JIT code was not sanitizer instrumented. This extends CPU software
Metal. Native GPU execution, Fortnite launch gates, a Fortnite frame and
complete Metal support remain unverified.

## Retained evidence

Canonical original workspace:
`/Users/alex/Library/Caches/vinix-ios/vector-interleave-20261116-r1`.

Complete archive:
`/Users/alex/Library/Caches/vinix-ios/vector-interleave-20261116-r1.tar.gz`.

- Archive SHA-256: `12c3af64dd56f4bb4599b711b0234ec6c08d0a671e8c118ca2c2d1790a1466be`.
- Complete typed inventory: sibling `.inventory.json`, SHA-256 `18fa8982cfcbd2f3f7367510010490c5619dfec31ecbe5bb63092ece911120d7`.
- Source snapshot: workspace `source.tar`, SHA-256 `abe683f0dadabd443216bd4421ef7d30c87693784847f14f170eb7ecc94a03ad`.

Inventory and archive checks compare every path, type, mode, link, size and
logical file hash, including root mode. Originals remain retained. This records
integrity without restoration replay or permission to delete evidence. Source,
commands, executable/tool identities, native targets, generated C, attempts and
sanitizer logs remain; sealing receipts are siblings outside the sealed workspace.
