# Shuffled vector lanes in buffer indices — 2026-11-16

Source revision: `5a88726078816db72208b438cd4f4dfd71cfbb2a`.

Pure integer buffer address graphs now accept `shufflevector` over supported
arguments, constants, freezes, scalar-condition selects, insertions and earlier
shuffles. Input and result counts independently range from 1..16 with matching
i1..i64 elements. A fixed i32 mask selects across both inputs; poison and legacy
undef entries produce poison lanes. Selected source undef remains deferred until
final extraction or source repair. All complete source dependencies and original/
normalized mask entries validate, including ignored inputs and mask lanes.
Vector conditions, arithmetic and loaded/PHI sources remain excluded from
addresses. Immediate source errors and extracted undef cannot be concealed by
later scalar recovery. Source freeze repairs poison mask entries and selected
indeterminate lanes but leaves invalid extraction selectors poisoned.

Two existing POD words pack sixteen mask bytes, reserving 255 for poison.
A mapping node checks full unsigned selector bounds before shifting; a rebasing
node supplies a source lane and a shuffle node copies only the selected source
tags. All three nodes and source projections count toward the existing 256-node/
32-level budgets, including cached subtrees. Existing selector-keyed cache,
noslices graph storage and free paths remain. No owned field/map/array is added.
Generated C confirms fixed runtime arrays, guarded shifts, stack push records
and by-value return, without successful-path allocation beyond existing graph/
cache storage. Heap retention is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 1,799,040 cases: 879,093 exact outputs and 919,947 prewrite refusals,
  including 123,670 selected-undef errors. All 64 lane widths and selector
  widths 1/32/64 cover input counts 1/3/16, output counts 1/2/3/16 and every
  input/output count pair at i32. Four source patterns, eight mask patterns and
  frozen/unfrozen selection exercise both sources, broadcasts, resized results,
  upper mask bytes, poison/legacy-undef/zero masks, poison/undef sources and noisy
  argument padding. Defined native LLVM shuffles use zero for indeterminate
  source lanes and explicit vector selection for poison mask entries, with
  guarded extraction. A separate lane-state model checks errors, poison and
  the backend zero choice. No invalid native extraction or poisoned memory
  operation executes. Validation, ordinary and prepared execution agree and
  preserve all bytes on refusal.
- Forty-six controls check exact cached left/right/selector/freeze/nested
  depths 32/33, exact 256/257-node limits, distinct selector cache keys,
  selected/ignored undef, source/scalar recovery limits, poison/legacy masks,
  insertion/selection/nested-shuffle composition, independent roots in both
  orders, cold dependencies, unchosen immediate source errors, unsupported
  dependencies, malformed flags/arity/type/mask count and changed unselected
  normalized mask entries, including negative-integer impostors.
- All 41 existing core programs and eight vector/operand unit suites pass,
  including 626,688 independent shuffle lane-state comparisons. Five maintained
  shuffled-source rejection fixtures now use unsupported vector arithmetic;
  rejection assertions remain. Other core checks are unchanged. Historical
  retained bundles and auditors remain untouched.
- The image shader shuffles lanes from its inserted and selected permutations,
  then freezes the result. Independent red-channel expectations observe both
  sources, insertion choices and repaired undef. Four sizes pass exact RGBA/
  padding readback in both hashing modes, using fresh processes and freshly
  compiled binaries. Each mode reports 106 geometry dispatches, eight shader
  images, 93,962 checked invocations, 106 rejected pipelines and two prewrite
  bounds failures.

The first control smoke passed. Two preliminary matrices were stopped before
completion while splitting the i32 count-pair module to stay within the existing
parser record budget; a helper compilation error initially left the old generator
in use. Both partial runs and the initial source/binary remain. The final generator
partitions by input count with unchanged coverage; its complete matrix passes.
Production remained unchanged throughout qualification.

Evidence: `/Users/alex/Library/Caches/vinix-ios/vector-shuffle-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/vector-shuffle-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass.
Originals remain retained; no restoration replay is claimed.

- Archive SHA-256: `417b3f377ee21369314bfbcb1cb342fb56b552445c33f0ea17bf6a0254bb1379`.
- Inventory SHA-256: `afb6874d69db5b822824699997d726609eba2fd73f8f591c48bde464a9c8563a`.
- Source archive SHA-256: `2550a8362b5ea1ed66f522376a9d77c623c10064c0f900f904daa75e914134e5`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs match the feature commit.
Reproduce with `tests/ios/air-memory-vector-shuffle-index.v LLVM_AS FRESH_EXTERNAL_DIR`
and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`, using repository
module paths and the retained toolchain. Dependencies remain referenced; this is
not hermetic. Native JIT is uninstrumented and leak detection is disabled.
CPU software Metal only is qualified; no broad runtime suite, native GPU,
guest launch or new Fortnite frame is verified.
