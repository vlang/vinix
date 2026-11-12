# Software Metal RGBA8 — 2026-11-13

`eafc8701c` adds RGBA8Unorm (70) and RGBA8Unorm_sRGB (71) to software
texture storage, CPU transfers, buffer-backed textures, blits and alignment
queries. Both use four bytes per pixel and report 256-byte linear alignment.
Linear/sRGB reinterpretation within the RGBA pair requires PixelFormatView
usage, as with BGRA. RGBA/BGRA cross-family views remain rejected. Transfers
preserve channel bytes without swizzling or gamma conversion; texture blits
still require matching pixel formats. IOSurface import formats remain limited
to the existing BGRA/YUV profile. See
[METAL.md](../../compat/ios/runner/METAL.md).

All twenty-one software groups pass under ASan/UBSan on macOS ARM64 with
normal and deterministic Swift hashing. New RGBA checks cover zero storage,
distinct R/B channel bytes through short/full CPU selectors, nested compatible
views, owned/buffer-backed storage, alignment queries, deferred texture copies
and padded buffer readback observing writes made after encoding, retained
resources and incompatible format/usage rejection across two drained runtimes.
The older four-format regressions remain in place. The ordinary runner suite
was not rebuilt for this opt-in change.

Evidence bundle:

`/Users/alex/Library/Caches/vinix-ios/metal-rgba8-validation-20261113-r1/`

The sibling archive was decoded/extracted to a fresh `-restored` directory.
Saved source/compiler/header/executable identities match, and the restored
sanitizer executable passes all twenty-one groups. The archive checksum passes
afterward; receipts remain beside the bundle. The maintained harness retains
its documented compiler-preamble corrections. Toolchain library symlinks,
host SDKs and dylibs remain external prerequisites; dependency closures are
not sealed. This is not a full typed-inventory audit. Leak detection is
disabled; object drainage is checked, retained heap is not measured. Shader
execution and presentation remain pending. No Fortnite frame or new launch
gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `72265e045da82077102560240b8a6a020bbeb335011501084d4d35bb0c2c09fd` |
| `source.tar`, revision `eafc8701c` | `0cd1b76c4554352fa8b6129fbecde4f3d2bebeccece6e99c599ebe2478d562fd` |
