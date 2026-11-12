# Software Metal buffer/texture transfers — 2026-11-12

`7f10682fb` adds both standard buffer-to-texture and texture-to-buffer blit
selectors without options to the opt-in `ios_metal_software` backend. Both
record existing deferred row-copy commands and retain their resources through
command-buffer destruction. Uploads, texture copies, readbacks and buffer
copies execute in one ordered array at commit. No new owned array or executor
is introduced. See [the supported API](../../compat/ios/runner/METAL.md).

The bounded profile accepts positive regions in the four existing 2D formats,
slice/level zero, z zero and depth one. Buffer offsets/row pitches must be
pixel aligned, pitch must cover a row and cannot exceed 16,384 pixels, and
bytes-per-image must be zero. Texture bounds and the complete padded buffer
span are checked before recording. Row arithmetic follows bounded dimension/
pitch checks; subtraction-based buffer checks avoid offset overflow. Only
pixel bytes are copied. Options, 3D, compressed formats and private storage
remain unsupported.

ASan/UBSan host checks pass with normal and deterministic Swift hashing.
Both long Objective-C selectors, including aggregate/stack arguments, execute
mixed buffer-upload → texture-copy → buffer-readback → buffer-copy chains.
Exact bytes, padded rows, nonzero offsets, pre-commit source updates, deferred
visibility and resource survival after caller releases pass for all four
formats. Ten invalid modes per direction/format cover offsets/full-span
overrun, row constraints, image stride, slice/level, texture bounds, device
mismatch and ended encoders across two drained runtimes per run. Existing
texture-blit, shared-texture, buffer/state/lifetime/eight-worker tests pass.
The default/native Metal suite was not rebuilt in this checkpoint.

Qualified complete evidence is outside Git:

`/Users/alex/Library/Caches/vinix-ios/metal-buffer-texture-validation-20261112-r2/`

r1 remains diagnostic: one rejection fixture originally ended exactly at the
R8 buffer boundary, which is valid; r2 correctly exceeds it. The archive was
decoded/extracted to `metal-buffer-texture-restoration-20261112-r2/`. Saved
source/compiler/header/executable identities match. The restored sanitizer
binary passes all four test groups again; the archive checksum passes afterward.
Receipts remain beside the bundle. The harness retains its documented compiler
preamble corrections. Toolchain library symlinks, host dylibs and SDKs remain
external prerequisites; complete dependency closures are not sealed. This is
not a full typed-inventory audit. Leak detection is disabled; object drainage
is checked, retained heap allocation is not measured. No guest, shader, iOS
app or GPU command ran. Rendering/presentation remain pending; no Fortnite
frame or launch boundary is advanced.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `6e8357f14e42b1bd73cf3839c725aff6d02e13a127e71c52edae99f837958d1a` |
| `source.tar`, revision `7f10682fb` | `873bf26a04b740b2843616e0efe199499d2ea65c98833ce2b08c2c600e14c9dd` |
