# Software Metal shared textures — 2026-11-12

`210f54485` adds shared 2D textures to the opt-in `ios_metal_software` backend.
The descriptor factory, setters, texture allocation, property queries and
CPU upload/readback execute through the Objective-C ABI. R8Unorm, RG8Unorm,
BGRA8Unorm and BGRA8Unorm_sRGB preserve raw bytes. Storage is zero initialized,
single-level/single-sample, bounded to 16,384 per dimension and 64 MiB total.
Unsupported allocations and mipmapped factory requests return nil.

Textures snapshot descriptors and independently retain their device. Existing
object cleanup frees pixel storage, device references and the reused CoreVideo
metadata allocation. Transfers check positive 2D bounds, level, pitch,
pixel alignment and pointer arithmetic before copying requested row bytes.
Single-row transfers accept zero pitch. See the
[supported API](../../compat/ios/runner/METAL.md) and
[Apple's transfer contract](https://developer.apple.com/documentation/metal/mtltexture/replace%28region%3Amipmaplevel%3Awithbytes%3Abytesperrow%3A%29).

ASan/UBSan host runs pass in normal and deterministic Swift-hashing modes:
four formats; 48-byte region ABI; padded full/subregion transfers; untouched
row padding and guards; zero-pitch single rows; invalid descriptors, dimensions,
formats, storage, usage, levels, regions, pitches and pointers; descriptor
snapshots and independent device lifetimes. Nine invalid-transfer cases per
format run across two drained runtimes. Existing deferred buffer-blit,
completion, invalid-state, eight-worker and lifetime regressions pass too.
The default-device/native Metal suite was not rebuilt in this checkpoint.

Qualified complete evidence is outside Git:

`/Users/alex/Library/Caches/vinix-ios/metal-texture-validation-20261112-r3/`

The complete archive was decoded/extracted into
`metal-texture-restoration-20261112-r3/`. Saved source, compiler, header and
executable identities match; its sanitizer executable passes texture and
buffer regressions again. The archive checksum passes afterward. Receipts are
beside the bundle. Earlier r1/r2 attempts are diagnostic, not qualification.
The maintained harness retains its documented compiler-preamble corrections.
Toolchain library symlinks, host dylibs and SDKs remain external prerequisites;
their complete closures are not sealed. This is not a full typed-inventory
audit. Leak detection is disabled; runtime object drainage is checked, retained
heap allocation is not measured. No guest, shader, iOS app or GPU command ran.
Texture blits, rendering and presentation remain unimplemented; no new
Fortnite frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `8e521435115769e3a047c0e5470af1f7f0120d76948b5dd7aae3099d542a56ef` |
| `source.tar`, revision `210f54485` | `be7a19896f39238066d1f30b44858fa211afa63a5836f45108da4ae4b7a140c2` |
