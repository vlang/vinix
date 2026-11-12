# Software Metal texture view ranges — 2026-11-13

`760ceb2e3` adds
`newTextureViewWithPixelFormat:textureType:levels:slices:` to the software
texture API. It accepts 2D type (2) and exactly `{0, 1}` for both NSRange
arguments, matching the backend's single mip and slice. Other types and
empty/nonzero-base/oversized/overflowing ranges return nil before allocation.
Format validation, shared storage and parent ownership use the existing view
constructor. This does not add array or mipmapped storage. See
[METAL.md](../../compat/ios/runner/METAL.md).

All fourteen software groups pass under ASan/UBSan on macOS ARM64 with normal
and deterministic Swift hashing. The new checks exercise both inline range
arguments, four formats, nested aliases, copied bytes after parent caller
references are released, BGRA reinterpretation, ten unsupported texture types,
five invalid ranges independently on each axis and bad formats across two
drained runtimes. Existing IOSurface/padded-row/deferred-blit alias checks now
create their nested view through this selector and pass. The ordinary runner
suite was not rebuilt for this opt-in change.

Evidence bundle (named when the run began):

`/Users/alex/Library/Caches/vinix-ios/metal-view-ranges-validation-20261112-r1/`

The sibling archive was decoded/extracted to a fresh `-restored` directory.
Saved source/compiler/header/executable hashes match, and the restored
sanitizer executable passes all fourteen groups. The archive checksum passes
afterward; receipts remain beside the bundle. The maintained harness retains
its documented compiler-preamble corrections. Toolchain library symlinks,
host SDKs and dylibs remain external prerequisites; dependency closures are
not sealed. This is not a full typed-inventory audit. Leak detection is
disabled; object drainage is checked, retained heap is not measured. Shader
execution and presentation remain pending. No Fortnite frame or new launch
gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `cb1ae1da8fecd00074ef437aadf8244b6ea3e81baff29b2e3b884f599af198db` |
| `source.tar`, revision `760ceb2e3` | `efd79c5b53f8fdabac64ddd864e1ec00f1c73fe274c5b44e84f19e0efa24de14` |
