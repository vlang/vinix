# Multidimensional software grids checkpoint — 2026-11-16

Source revision: `9be76b1db68b34ce1b775fe43d2a1ad1f9fc299d`.

Software Metal accepts nonempty 1D/2D/3D grids and threadgroups through both
dispatch selectors. Limits remain 4,096 invocations, 256 threads per group and
1,000,000 conservative instruction steps per dispatch. Checked volume products
precede normalization and multiplication; zero/oversized/overflowing dimensions
reject. `dispatchThreadgroups` multiplies each grid axis by its group axis;
`dispatchThreads` retains exact dimensions, including partial edge groups.

Snapshots carry all normalized grid/group dimensions by value. Scalar grid
positions receive x; uint3 positions receive x/y/z. Local indices flatten actual
group coordinates with x varying fastest, using clipped width/height for partial
groups. Serial execution varies x, then y, then z. All invocation addresses still
validate before dispatch writes; arithmetic poison retains earlier writes.
Computed SSA addressing, barriers, threadgroup memory, GPU execution and rendering
remain unsupported.

No new execution allocation or object lifetime is introduced. The coordinate
helper returns a fixed four-word array; generated C uses stack locals and a
by-value return. Existing owned builtin words and borrowed buffer/value slices
retain their cleanup paths. Snapshot ownership and resource reference release
are unchanged. Retained heap is unmeasured.

AddressSanitizer and UndefinedBehaviorSanitizer checks pass on macOS ARM64:

- Both hashing modes each complete 472 multidimensional dispatches covering
  629,808 successful invocations: 944 dispatches and 1,259,616 invocations total.
  Each mode checks 235 first/edge-group fixtures across both selectors and two
  drained runtimes, including full/partial 2D/3D groups and maximal volumes.
  AIR writes coordinate/local-index vectors through direct local-index GEPs;
  exact output, buffer offsets and untouched padding are checked.
- An independent nested group/local enumeration checks all 314,892 coordinate
  cases per mode, with one visit per grid position and compact local indices.
  Reordered metadata, scalar x projection and all uint3 coordinate lanes pass.
- Each mode checks four cold-address/poison command failures and 35 hostile
  dimension, volume/product and exact step-budget controls. Late cold-address
  failure preserves the complete output; poison preserves earlier invocations.
- Fresh processes of the same executable pass the existing 676 completed 1D
  dispatches (344,716 successful invocations), 12 expected command failures,
  196 geometry/budget controls and 10 encoding refusals across both modes.
  Previously rejected nonunit dimensions now use zero/oversized guards.
- Existing builtin/vector/prepared-reuse runtime checks also pass: 12 builtin
  dispatches, 76 invalid pipelines, 80 vector and 16 prepared-reuse dispatches.

The first generation attempt rejected a compact match expression in the checker.
A fixed expected-value array replaces it. Its logs remain retained; only
`software-multigrids-r2` qualifies final execution. No native GPU comparison or
complete broad runtime-suite pass is claimed.

Evidence is retained at `/Users/alex/Library/Caches/vinix-ios/compute-multigrids-20261116-r1`;
its verified archive is `/Users/alex/Library/Caches/vinix-ios/compute-multigrids-20261116-r1.tar.gz`.
Complete typed inventory and archive logical-content/metadata comparison pass.
Originals remain retained; no restoration replay is claimed.

- Archive SHA-256: `aee4ddfdd0524d072348b65b67a2537e72832fafc2f8a77a6106508400a250a4`.
- Inventory SHA-256: `1a5a93576a1bf891f3429a2246256ed21583a8be83b0b053228826fef7861edf`.
- Committed source archive SHA-256: `bce05fec3060b03b0a842470ee33f982c16c96f6191cc491df5c0016e41de3b3`.

The bundle includes comparison rows, generated AIR/bitcode/C, commands/logs,
tool/executable identities, ownership review and reviewed source hashes compared
with the feature commit. Reproduce using
`tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR multigrids` with repository
module paths and the retained captured toolchain. Local dependencies remain
referenced; this is not a hermetic rebuild. Leak detection is disabled. These
checks add no GPU rendering, guest launch or verified Fortnite frame.

The [Metal language specification](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf)
defines local indexing and actual versus dispatch-specified group sizes. The
checks exercise synthetic AIR on the CPU and establish no parallel-memory
ordering guarantee.
