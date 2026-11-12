# Software Metal full CPU transfers — 2026-11-13

`18a923d20` implements
`replaceRegion:mipmapLevel:slice:withBytes:bytesPerRow:bytesPerImage:` and
`getBytes:bytesPerRow:bytesPerImage:fromRegion:mipmapLevel:slice:`.
The selectors require slice zero and bytes-per-image zero in this bounded 2D
profile, then use the existing transfer validation/storage path. They support
all four formats, views and IOSurface planes, preserving row padding and
single-row zero pitch. Array and 3D transfers remain unsupported. See
[METAL.md](../../compat/ios/runner/METAL.md).

All fifteen software groups pass under ASan/UBSan on macOS ARM64 with normal
and deterministic Swift hashing. New checks exercise both long-selector ABIs,
short/full API comparisons across four formats, subregions, client row guards,
views after parent caller release, single-row zero pitch and nine rejected
inputs in each direction across two drained runtimes. Existing IOSurface
checks now exercise both full selectors across BGRA and YUV planes. The
ordinary runner suite was not rebuilt for this opt-in change.

Evidence bundle:

`/Users/alex/Library/Caches/vinix-ios/metal-cpu-slices-validation-20261113-r1/`

The sibling archive was decoded/extracted to a fresh `-restored` directory.
Saved source/compiler/header/executable identities match, and the restored
sanitizer executable passes all fifteen groups. The archive checksum passes
afterward; receipts remain beside the bundle. The maintained harness retains
its documented compiler-preamble corrections. Toolchain library symlinks,
host SDKs and dylibs remain external prerequisites; dependency closures are
not sealed. This is not a full typed-inventory audit. Leak detection is
disabled; object drainage is checked, retained heap is not measured. Shader
execution and presentation remain pending. No Fortnite frame or new launch
gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `8fd60bb5a1415a5ce2b4fa10a77a2b59fe63cca3b47d0147b7c123a22afcf7de` |
| `source.tar`, revision `18a923d20` | `4dda4fb37798ef1d123ba93b016d3d1ce9ffb94ffa4c697f25eb4352405b9d05` |
