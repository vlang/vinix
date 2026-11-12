# Software Metal linear alignment — 2026-11-13

`c7646e3f4` adds `minimumLinearTextureAlignmentForPixelFormat:` to the
software device. It returns 256 for the four supported formats and rejects
unsupported formats explicitly. The query and buffer-backed texture allocator
share one alignment policy. Applications can calculate aligned offsets and
row pitches instead of embedding that backend constant. This does not expose
texture-buffer alignment or add new pixel formats. See
[METAL.md](../../compat/ios/runner/METAL.md).

All seventeen software groups pass under ASan/UBSan on macOS ARM64 with
normal and deterministic Swift hashing. New checks exercise the NSUInteger
query ABI, four formats and eight boundary widths per format, calculated
pitches, exact-fit backing spans, CPU access to the last pixel, rejection of
one-byte-short/misaligned layouts and five unsupported format queries across
two drained runtimes. The ordinary runner suite was not rebuilt for this
opt-in change.

Evidence bundle:

`/Users/alex/Library/Caches/vinix-ios/metal-linear-alignment-validation-20261113-r1/`

The sibling archive was decoded/extracted to a fresh `-restored` directory.
Saved source/compiler/header/executable identities match, and the restored
sanitizer executable passes all seventeen groups. The archive checksum passes
afterward; receipts remain beside the bundle. The maintained harness retains
its documented compiler-preamble corrections. Toolchain library symlinks,
host SDKs and dylibs remain external prerequisites; dependency closures are
not sealed. This is not a full typed-inventory audit. Leak detection is
disabled; object drainage is checked, retained heap is not measured. Shader
execution and presentation remain pending. No Fortnite frame or new launch
gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `81ec681425c0783814f26fcdc3b3589833f9fd7a367eda751bed741b5b448111` |
| `source.tar`, revision `c7646e3f4` | `19e4e00f6afd6651869c2f25c5cc64b1192f9d9e26a937e21bf52f8b080c4e18` |
