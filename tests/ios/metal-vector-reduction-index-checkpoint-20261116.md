# Software Metal reduction address checkpoint — 2026-11-16

Source revision: `271f7961d7e44f2f9951eaed0fca8df220bc7e19`.

The bounded AIR address evaluator now accepts the nine integer vector
reductions as buffer-index dependencies. It projects and observes every source
lane, then uses the existing reduction arithmetic to produce a scalar. This
preserves eager undef errors before writes, including cold GEP roots and
results subsequently discarded by scalar select/freeze. Source freeze repairs
indeterminate lanes; scalar result freeze repairs poison only. Source poison
propagates even for annihilating operands. Existing 256-node/32-level bounds
cover all projections, observations and cached heights. Loads, PHIs, floating
and scalable dependencies remain outside pure address graphs.

`tests/ios/air-memory-vector-reduction-index.v` passes with ASan/UBSan:

- 240,192 address cases: 157,235 exact outputs and 82,957 prewrite refusals,
  including 52,542 whole-source undef cases. Validation stays nonmutating;
  ordinary and prepared execution check every backing byte and marker ordering.
- 80,064 native LLVM values match an independent arithmetic/extrema oracle.
  Native code executes only defined replacement inputs. Poison, undef, source
  and result freeze choices, scalar select and bounds are modeled separately.
- Coverage includes nine operations, all i1..i64 widths with three lanes and
  every count 1..16 at widths 1/8/16/32/64: 1,251 operation/width/count shapes,
  eight patterns and eight expression modes. Sources include vector arguments,
  literal states, source/result freeze, insertion, chosen vector select,
  unchosen scalar results and mixed earlier-poison/later-undef lanes. Three
  changing output extents reuse each prepared plan with shifted bindings.
- Every one of 240,192 short budgets rejects with a budget diagnostic before
  writes, including cases that would otherwise fail address validation.
- 150 controls cover composition with binary/shuffle/select, loaded-source
  exclusions, signed/large addresses, cold GEP roots, shared reduction results,
  nested reductions through scalar/vector bitcast, poison/undef/freezing and
  exact versus exceeded node/depth limits. The node boundary is four reduction
  nodes, one shared zero and 251 independent OR nodes. Scalar and vector-source
  depth boundaries cover 28 versus 29 additional operations, including cached
  scalar ancestor heights.

Existing sanitized unit suites pass: 860,148 independent reduction values,
156,672 all-lane poison/undef states and 8,640 mixed-state checks; 7,340,032
binary16 rounding values, 22,848 states and all 34,496 cache identities; and
157,024 independent vector carry-less multiply values, 139,264 algebraic
identities and 208,896 states. Cache size and previous identities are unchanged.

Computed-index regression passes 26,029 exact native cases, 50,771 prewrite
refusals (21,399 LLVM overflow cases) and 4,096 vector-coordinate cases.
Prepared memory passes 28,928 byte comparisons and 3,314 changing-input,
recovery, bounds/budget and copied-metadata controls. Earlier controls pass:
118 scalar reduction controls, 650 vector carry-less multiply and 67
scalar/vector bitcast address controls. The maintained scalar reduction
checker now expects its previously excluded address fixture to execute and
checks both memory APIs; its other exclusions and limits are preserved.
Other full vector matrices were not repeated.

Fresh normal and deterministic software Metal processes each pass 106 geometry
dispatches, 112 shader images, 209,350 checked invocations, 106 rejected
pipelines and two prewrite bounds failures. The new image uses a three-lane
sum to reconstruct its destination x coordinate and a separate four-lane sum
in its red channel. Tests cover queued dispatch, RGBA8 buffer/texture readback,
padded backing bytes, both dispatch selectors, clipped groups, repeated
commits and two drained runtimes per process.

The implementation appends one POD evaluator kind without changing node
fields, declaration-cache sizes, profile ownership or cleanup. The builder
uses fixed parent indices and appends copied nodes to the existing bounded
array. The evaluator reconstructs a fixed by-value vector and calls the
previously qualified helper. Generated checker and host C show fixed locals,
existing array pushes and no new arrays or escaping local source/parent
storage in these paths. No borrowed source pointer, lifetime extension or
free path is added. Both focused programs contain their used memory-profile
cache and omit their unused integer profile. Existing allocation/error paths
remain. Heap retention was not measured, leak detection was disabled and
native JIT code was not sanitizer instrumented. Broader runtime and
kernel/guest builds were not repeated.

Both probe builds succeeded. Before the controls probe ran, its node-boundary
fixture and large-index diagnostic expectation were corrected. The probe
passes 150 controls. Final qualification adds exact controls-count and
short-budget diagnostic assertions. All qualified checks pass without
production corrections or runtime failures. All original evidence is retained.

This is CPU software Metal evidence. Native GPU execution, guest/Fortnite
launch gates, a Fortnite frame and complete Metal support remain unverified.

## Retained evidence

Canonical original workspace (retained in place):
`/Users/alex/Library/Caches/vinix-ios/vector-reduction-index-20261116-r1`.

Complete archive:
`/Users/alex/Library/Caches/vinix-ios/vector-reduction-index-20261116-r1.tar.gz`

- Archive SHA-256: `e7cb3a78257a557ee1b5da0263d23d6336920cb20037a7e9c9c21bbaebc768d8`.
- Complete typed inventory: sibling `.inventory.json`, SHA-256 `f7bb0c31503092cef8cc729ee01da1d88cb2de43890ccf0e5acfd74bb85a2c85`.
- Source snapshot: workspace `source.tar`, SHA-256 `01333706be0eb39e807b3decedfd8918b4a24b7531d0969de1967cd7f233d6e5`.

The archive check decodes all logical payloads and compares the complete
workspace's paths, types, modes, symlink targets, sizes and hashes, including
root mode. Inventory comparison passes before compression and is rechecked by
the archive tool afterward. This records integrity with originals retained;
it does not claim a restoration replay or authorize deletion. Commands,
source revision, LLVM target/features, generated C, captured compiler,
executable identities and sanitizer logs are in the bundle. Sealing
commands/statuses are siblings outside the sealed workspace.
