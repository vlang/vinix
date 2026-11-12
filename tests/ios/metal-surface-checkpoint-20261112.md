# Software Metal IOSurface imports — 2026-11-12

`0215f8e8b` adds `newTextureWithDescriptor:iosurface:plane:` to the opt-in
`ios_metal_software` device. The existing CoreVideo Metal cache can now create
textures through this device. BGRA planes support formats 80/81; 420v/420f
luma and chroma planes support 10/30 respectively. Imports snapshot descriptor
metadata, retain the device and surface, and borrow the plane address. The
existing object destructor releases both owners; imported bytes are never
freed as owned texture data. No additional allocation executor is introduced.

CPU transfers, texture blits and buffer/texture blits now use the actual
storage base and plane row stride, including when descriptor width is smaller
than plane width. Separate imports of one plane reject overlapping texture
copy rectangles; disjoint copies remain valid. Imports return nil for invalid
objects, plane, format, dimensions, usage or storage mode, and bound the
addressed span to 64 MiB. Only local runtime IOSurfaces are supported. See
[the API and limits](../../compat/ios/runner/METAL.md).

ASan/UBSan macOS ARM64 checks pass with normal and deterministic Swift hashing:
all four Metal formats, odd-sized BGRA/420v/420f planes, real software device
and CoreVideo cache integration, shared CPU bytes, padded rows, narrower
descriptors, deferred mixed buffer/texture copies, unchanged pixels/padding,
pixel-buffer/cache/view/resource release before commit, eleven invalid import
modes, overlapping alias rejection, valid disjoint alias copies and two drained
runtimes. All six previous Metal groups pass. The default/native Metal suite
was not rebuilt in this checkpoint. No native GPU comparison is claimed.

Complete qualified evidence is outside Git:

`/Users/alex/Library/Caches/vinix-ios/metal-surface-validation-20261112-r2/`

The archive was decoded/extracted into `metal-surface-restoration-20261112-r2/`.
Saved source/compiler/header/executable identities match; the restored sanitizer
executable passes all seven groups again. The archive checksum passes afterward.
Receipts remain beside the bundles. r1 is the earlier passing test version;
r2 adds both BGRA formats and valid disjoint alias copies. The maintained
harness retains its documented compiler-preamble corrections. Toolchain
library symlinks, host dylibs and SDKs remain external prerequisites; dependency
closures are not sealed. This is not a full typed-inventory audit. Leak
detection is disabled; object drainage is checked, retained heap is not measured.
No guest, shader, iOS app or GPU command ran. Rendering and presentation remain
pending; no Fortnite frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `ccf62e586ec431889bc23b8a440293fdd467e1112a1a00861609a68b55002f24` |
| `source.tar`, revision `0215f8e8b` | `e66c4359eb74e7ca17a3bed730a4a7f89e5717b44f6b0756e35834ea92cd13a1` |
