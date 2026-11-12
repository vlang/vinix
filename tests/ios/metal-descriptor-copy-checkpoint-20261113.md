# Software Metal descriptor copies — 2026-11-13

`1229b3bfe` adds `copy` and `copyWithZone:` to software texture descriptors
produced by the existing 2D factory. Each returns a caller-owned descriptor
with independent metadata. Copies survive the source pool and can be changed
without affecting the original or already allocated textures. Existing
CoreVideo descriptor getters and metadata cleanup are reused. General `init`
construction and additional descriptor fields remain unsupported. See
[METAL.md](../../compat/ios/runner/METAL.md).

All eighteen software groups pass under ASan/UBSan on macOS ARM64 with normal
and deterministic Swift hashing. A shared native/runner probe checks factory
dimensions/format, five property getters, both copy selectors and independent
mutations. Software checks allocate all four texture formats from copies after
the source autorelease pool drains, verify immutable texture snapshots and
copy-of-copy lifetime, and drain two runtimes. The ordinary runner suite was
not rebuilt for this opt-in change.

Evidence bundle:

`/Users/alex/Library/Caches/vinix-ios/metal-descriptor-copy-validation-20261113-r2/`

The sibling archive was decoded/extracted to a fresh `-restored` directory.
Saved source/compiler/header/executable identities match, and the restored
sanitizer executable passes all eighteen groups. The archive checksum passes
afterward; receipts remain beside the bundle. The maintained harness retains
its documented compiler-preamble corrections. Toolchain library symlinks,
host SDKs and dylibs remain external prerequisites; dependency closures are
not sealed. This is not a full typed-inventory audit. Leak detection is
disabled; object drainage is checked, retained heap is not measured. Shader
execution and presentation remain pending. No Fortnite frame or new launch
gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `6109d230531ff57d71db84fd3ac60e128cb68f0ab9fdefc6c7e297564b441ec0` |
| `source.tar`, revision `1229b3bfe` | `954520e9b7d1d900e0ef31c000cad79f8a71740630684dfcef14f25e86128865` |
