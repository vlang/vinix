# Compute geometry sizes checkpoint — 2026-11-16

Source revision: `fca8b0f98ad07d895790d31a33c43ebfeda30590`.

Software Metal now accepts `air.threads_per_grid`, `air.threads_per_threadgroup`
and `air.dispatch_threads_per_threadgroup` as uint or uint3. They expose the
normalized grid, actual clipped group and requested group dimensions. Scalar
arguments receive x. Grid position/size types must match each other, as must
actual/requested group sizes. Existing strict builtin metadata checks apply.

The dispatch retains its validated geometry as before. Both address prevalidation
and execution refresh all builtin words for every invocation. The new helper
uses fixed stack arrays, confirmed in generated C. Bindings borrow the owned
15-word dispatch array, freed on success and error through existing defers.
No new retained resource lifetime is introduced. Retained heap is unmeasured.

AddressSanitizer and UndefinedBehaviorSanitizer checks pass on macOS ARM64
in normal and deterministic Swift hashing modes, each with two drained runtimes:

- 212 geometry dispatches reuse scalar/uint3 pipelines over both selectors,
  1D/2D/3D grids, maximum grids, partial and oversized groups. Independent
  group/local enumeration checks every word and all output padding.
- 16 image dispatches reuse one image pipeline per runtime for 7x5, 17x3,
  32x8 and 64x64 images. Shader-written RGBA8 buffer pixels are read through
  existing buffer-backed textures; every channel, row padding, prefix and suffix
  matches. PPM files preserve actual readback pixels. Caller buffer references
  are released before commit; texture/command ownership preserves storage.
- The 228 successful dispatches cover 187,924 invocations. Another 212 pipeline
  rejections cover 53 distinct invalid fixtures across four runtimes: each new
  semantic has 17 bad type/metadata/duplicate cases, plus two family mismatches.
  Four late bounds failures leave every output byte untouched.
- Fresh processes of the same executable pass existing builtin, 1D grid,
  multidimensional grid, computed-index, vector-memory and prepared-reuse
  checks in both hashing modes. No interpreter source changed.

`software-sizes-final` qualifies the committed source. The first run caught an
extra release of an autoreleased texture descriptor in the new fixture at pool
cleanup. That fixture release was removed; the failed run remains preserved.

Evidence: `/Users/alex/Library/Caches/vinix-ios/geometry-builtins-20261116-r1`.
Verified archive: `/Users/alex/Library/Caches/vinix-ios/geometry-builtins-20261116-r1.tar.gz`.
Complete typed inventory and archive logical-content/metadata comparison pass.
Originals remain retained; no restoration replay is claimed.

- Archive SHA-256: `3e7c0d07d8d2fc7850c516e75a422daf7568ff3da6e357dd273c8d6078b4e3d4`.
- Inventory SHA-256: `4b8fef7df155a0f7a1e83f7d7047371b75f20d6ed71e185dfc08ebb97b610d10`.
- Committed source archive SHA-256: `aab2f925b8d0efcd721d7efd7a5501cdcf0b6d24f7c1b2134f6fb1fe73c7368b`.

The bundle retains comparisons, generated IR/bitcode/C, images, binaries,
commands/logs, tool identities, ownership review and source hashes verified
against the feature commit. Reproduce with `tests/ios/metal-software-checks.v
FRESH_EXTERNAL_DIR sizes` using the repository module path and retained
captured toolchain. Local dependencies remain referenced; this is not a hermetic
rebuild. Leak detection is disabled. No complete broad runtime suite, native GPU
rendering, AIR texture intrinsics, guest launch or new Fortnite frame is verified.

The size and type-family semantics follow the
[Metal Shading Language specification](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf).
