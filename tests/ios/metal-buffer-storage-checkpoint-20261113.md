# Software Metal buffer-backed textures — 2026-11-13

`6adcdb144` adds `newTextureWithDescriptor:offset:bytesPerRow:` to software
buffers, and texture `buffer`, `bufferOffset` and `bufferBytesPerRow` queries.
Shared single-level 2D textures alias retained buffer bytes. Offset and pitch
require 256-byte alignment; pitch must cover a row and be at most 64 MiB.
The addressed span must fit the buffer. Existing descriptor format, dimension,
storage and usage checks apply; invalid allocations return nil.

Views retain the buffer and parent and preserve offset/pitch. CPU transfers,
buffer fills and texture blits access the same storage. Normal object fields
release the owners; metadata uses existing cleanup. Blits reject overlapping
buffer/texture spans, and texture aliases with different bases or strides
reject overlapping bounding spans, including padding. Identical-layout
texture aliases retain rectangle overlap checks. See
[METAL.md](../../compat/ios/runner/METAL.md).

All sixteen software groups pass under ASan/UBSan on macOS ARM64 with normal
and deterministic Swift hashing. New tests cover four formats, CPU alias
coherence and padding, view metadata, twelve invalid layouts/descriptors,
three rejected overlapping texture/texture and buffer/texture copies,
deferred fill followed by a disjoint texture copy, caller storage release
before commit and two drained runtimes. The ordinary runner suite was not
rebuilt for this opt-in change.

Evidence bundle:

`/Users/alex/Library/Caches/vinix-ios/metal-buffer-storage-validation-20261113-r1/`

The sibling archive was decoded/extracted to a fresh `-restored` directory.
Saved source/compiler/header/executable identities match, and the restored
sanitizer executable passes all sixteen groups. The archive checksum passes
afterward; receipts remain beside the bundle. The maintained harness retains
its documented compiler-preamble corrections. Toolchain library symlinks,
host SDKs and dylibs remain external prerequisites; dependency closures are
not sealed. This is not a full typed-inventory audit. Leak detection is
disabled; object drainage is checked, retained heap is not measured. Shader
execution and presentation remain pending. No Fortnite frame or new launch
gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `1bd882e9c523b5fb542cdf1483f08606394f39e709a3291608b5fbfc456a15ff` |
| `source.tar`, revision `6adcdb144` | `617424f14407732b3c4b070531f4adf60acc8af30091f79f9505a1c2c7264050` |
