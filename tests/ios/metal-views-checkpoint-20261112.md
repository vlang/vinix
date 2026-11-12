# Software Metal texture views — 2026-11-12

`a4fbb3acb` adds `newTextureViewWithPixelFormat:`, `parentTexture`,
`parentRelativeLevel` and `parentRelativeSlice` to software textures.
Full single-level 2D views share storage and retain their immediate parent,
including for nested views. Views preserve the device, dimensions, usage,
IOSurface plane identity and padded stride. Normal object fields retain the
parent/device/surface; existing metadata cleanup frees each view's snapshot.
Views borrow bytes and never free parent storage themselves.

Same-format views work for all four supported formats. BGRA 80/81
reinterpretation requires PixelFormatView usage (16) in this conservative
profile. Other format changes return nil. CPU transfers preserve raw bytes;
no color conversion occurs. Parent-relative level/slice are zero. Subrange,
swizzle and texture-type view selectors remain unsupported. See
[METAL.md](../../compat/ios/runner/METAL.md).

All thirteen software groups pass under ASan/UBSan on macOS ARM64 with normal
and deterministic Swift hashing. New checks cover four formats on owned and
IOSurface storage, nested parent queries, shared CPU uploads/readback, BGRA
reinterpretation, retained ownership after caller references are released,
padded/narrow surface rows, deferred disjoint alias blits, overlapping alias
rejection and unsupported format/usage rejection across two drained runtimes.
The ordinary runner suite was not rebuilt for this opt-in change.

Evidence bundle:

`/Users/alex/Library/Caches/vinix-ios/metal-views-validation-20261112-r2/`

The sibling archive was decoded/extracted into a fresh `-restored` directory.
Saved source/compiler/header/executable hashes match, and the restored
sanitizer executable passes all thirteen groups. The archive checksum passes
afterward; receipts remain beside the bundle. The harness retains its
documented compiler-preamble corrections. Toolchain library symlinks, host
SDKs and dylibs remain external prerequisites; dependency closures are not
sealed. This is not a full typed-inventory audit. Leak detection is disabled;
object drainage is checked, retained heap is not measured. Shader execution
and presentation remain pending. No Fortnite frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `a39bb501cc08f80c17e26c01170e6ebaf35edfc67cf972838e8d0ffbe8e9aebf` |
| `source.tar`, revision `a4fbb3acb` | `456db794c60601fcbaf9727994c84572f9aecaf68554adc3eea00ec08e547bfa` |
