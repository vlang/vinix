# Software Metal floating textures — 2026-11-13

`d6058bdce` adds R16Float (25), RG16Float (65), RGBA16Float (115),
R32Float (55), RG32Float (105) and RGBA32Float (125). Their pixel sizes are
2, 4, 8, 4, 8 and 16 bytes. Existing shared 2D allocation, CPU transfers,
buffer-backed storage, deferred blits and 256-byte alignment queries support
these formats. Float views require the same format. Transfers copy raw bits
without numeric conversion or NaN canonicalization; shader sampling/arithmetic
is not implemented. IOSurface imports retain their existing BGRA/YUV profile.
See [METAL.md](../../compat/ios/runner/METAL.md).

All twenty-two software groups pass under ASan/UBSan on macOS ARM64 with
normal and deterministic Swift hashing. New checks cover six float formats,
zero initialization, half/float bit patterns for signed zero, finite values,
infinities, NaNs and subnormals, CPU pitches, same-format views, incompatible
view rejection, aligned buffer storage, both buffer/texture transfer directions
and texture blits in one deferred chain, client padding guards, writes after
encoding and two drained runtimes. Existing format regressions remain in
place. The ordinary runner suite was not rebuilt for this opt-in change.

Evidence bundle:

`/Users/alex/Library/Caches/vinix-ios/metal-float-textures-validation-20261113-r1/`

The sibling archive was decoded/extracted to a fresh `-restored` directory.
Saved source/compiler/header/executable identities match, and the restored
sanitizer executable passes all twenty-two groups. The archive checksum passes
afterward; receipts remain beside the bundle. The maintained harness retains
its documented compiler-preamble corrections. Toolchain library symlinks,
host SDKs and dylibs remain external prerequisites; dependency closures are
not sealed. This is not a full typed-inventory audit. Leak detection is
disabled; object drainage is checked, retained heap is not measured. Shader
execution and presentation remain pending. No Fortnite frame or new launch
gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `913297dca9a86441b5d551a3a9520812d9a8567f4423ac0263cf8c7d5dcd3b5c` |
| `source.tar`, revision `d6058bdce` | `1e0d6d5dbe265835a1b057ca23065dab53afc3a034872016de64ae17b8b0e351` |
