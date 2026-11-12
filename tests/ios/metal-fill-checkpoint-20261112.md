# Software Metal buffer fills — 2026-11-12

`d0b977bba` adds `fillBuffer:range:value:` to the opt-in `ios_metal_software`
backend. Encoding records an 8-bit value, retained destination and byte range
in the existing ordered operation array. Commit uses memset for fill records
and preserves copy ordering. Fill records retain no source object; normal
command cleanup releases their destination, including abandoned commands.
No new owned array or executor is introduced. See
[the supported API](../../compat/ios/runner/METAL.md).

Byte-granular ranges use subtraction-based bounds checks. Empty ranges at the
buffer end are valid. Overflowing/out-of-range locations or lengths, foreign
devices, non-buffer objects and ended/committed encoders reject. Fills share
the 65,536-operation limit with all copy commands.

ASan/UBSan host checks pass with normal and deterministic Swift hashing:
inline range/byte argument ABI, actual writes for all 256 byte values, full/
partial/last-byte/empty ranges, deferred visibility, interleaved fill/copy
ordering, unchanged neighbors, destination survival after caller release,
abandoned commands, eight invalid modes and two drained runtimes. Object
counts return to the device/queue baseline after each iteration. All previous
completion, buffer/texture transfer, texture-blit, shared-texture and
buffer/state/lifetime/eight-worker groups pass. The default/native Metal suite
was not rebuilt in this checkpoint.

Complete qualified evidence is outside Git:

`/Users/alex/Library/Caches/vinix-ios/metal-fill-validation-20261112-r2/`

Its archive was decoded/extracted to `metal-fill-restoration-20261112-r2/`.
Saved source/compiler/header/executable identities match; the restored
sanitizer executable passes all six groups again, and the archive checksum
passes afterward. Receipts remain beside the bundle. r1 is an earlier test
version; r2 strengthens coverage to ensure every byte value is actually written.
The maintained harness retains its documented compiler-preamble corrections.
Toolchain library symlinks, host dylibs and SDKs remain external prerequisites;
complete dependency closures are not sealed. This is not a full typed-inventory
audit. Leak detection is disabled; object drainage is checked, retained heap
allocation is not measured. No guest, shader, iOS app or GPU command ran.
Rendering/presentation remain pending; no Fortnite frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `86106229d8ea658b4a64b05b0e462b8e4c5370f629924e6b80ff51ff175246e4` |
| `source.tar`, revision `d0b977bba` | `55fc38f5c9b802143408c895732b2a3220ec753684e1851afe4c6ca40d7a94ac` |
