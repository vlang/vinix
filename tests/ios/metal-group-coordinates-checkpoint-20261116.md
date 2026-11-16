# Compute threadgroup coordinates checkpoint — 2026-11-16

Source revision: `1e0744e33a600620627d5f479a714399f8d56dd2`.

Software Metal accepts `air.thread_position_in_threadgroup`,
`air.threadgroup_position_in_grid` and `air.threadgroups_per_grid` as uint or
uint3. They expose local coordinates, group coordinates and per-axis group
counts, with scalar x projections. Local coordinates use modulo of requested
group dimensions, group coordinates use division, and counts round up to cover
partial edge groups. Local position, actual size and requested size must use
matching types when present together. Existing strict metadata checks apply.

All eight supported geometry semantics fit the existing u8 identity mask. The
owned dispatch words array grows from 15 to 24 words; borrowed builtin slices
retain the existing success/error cleanup. Generated C confirms fixed stack
arrays in the per-invocation helper. Both prevalidation and execution refresh
every word using the previously captured validated geometry. No new retained
resource lifetime is introduced. Retained heap is unmeasured.

AddressSanitizer and UndefinedBehaviorSanitizer checks pass on macOS ARM64 in
normal and deterministic hashing, each with two drained runtimes:

- 320 dispatches and 258,748 invocations reuse scalar, uint3 and mixed pipelines
  declaring all eight semantics together. Vector/scalar kernels reconstruct
  output addresses from local positions plus group positions times requested
  group sizes. Mixed kernels check scalar x projections in multidimensional
  grids. Reordered metadata, both selectors, maximum grids, partial groups on
  every axis and oversized groups pass.
- Independent group/local enumeration checks every record, explicitly counts
  group origins, and checks untouched record/buffer padding and offset snapshots.
  Four late bounds failures preserve complete output.
- 220 rejected pipelines cover 55 distinct fixtures across four runtimes:
  17 invalid type/metadata/duplicate cases per new semantic and four local
  position/actual-or-requested-size type mismatches in both directions.
- Fresh processes of the same executable pass existing builtin, 1D grid,
  multidimensional grid, computed-index, size/image-readback, vector-memory and
  prepared-reuse checks in both hashing modes. No interpreter source changed.

`software-coordinates` qualifies the committed source. Evidence is retained at
`/Users/alex/Library/Caches/vinix-ios/group-coordinates-20261116-r1`.
Verified archive: `/Users/alex/Library/Caches/vinix-ios/group-coordinates-20261116-r1.tar.gz`.
Complete typed inventory and archive logical-content/metadata comparison pass.
Originals remain retained; no restoration replay is claimed.

- Archive SHA-256: `30b488c6331151ccba09944e31d54a2e4d6f0ea6cc553f749801239f9f8f4e63`.
- Inventory SHA-256: `db9c45fd0bc97cded11524bdc3072079b256537a3fe615eea8c57cef4b54e194`.
- Committed source archive SHA-256: `f840d9500ea75f9aa97bdff9ab4d36cf2e13cea100d567f9ebda3fad9108ff35`.

The bundle preserves comparisons, IR/bitcode, generated C, binaries, commands,
logs, tool identities, ownership review and source hashes compared with the
feature commit. Reproduce with `tests/ios/metal-software-checks.v
FRESH_EXTERNAL_DIR group-coordinates` using repository module paths and the
retained captured toolchain. Dependencies remain referenced; this is not a
hermetic rebuild. Leak detection is disabled. No complete broad runtime suite,
GPU rendering, shared threadgroup memory, barriers, guest launch or new Fortnite
frame is verified.

Geometry and type-family semantics follow the
[Metal Shading Language specification](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf).
