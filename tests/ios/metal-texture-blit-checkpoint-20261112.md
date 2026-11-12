# Software Metal texture blits — 2026-11-12

`964e0289d` adds deferred texture-to-texture region copies to the opt-in
`ios_metal_software` backend. The standard long copy selector accepts the
existing four uncompressed formats, identical source/destination formats,
slice/level zero and positive 2D regions. Both textures must belong to the
queue's device. Out-of-range sizes reject under this bounded profile;
overlapping same-texture regions reject, while disjoint regions work. See
[the API contract](../../compat/ios/runner/METAL.md).

Each command retains both textures and records byte offsets, row count and
independent row strides in the existing ordered command array. Commit reads
source bytes then, so preceding uploads and earlier copies are observed.
Buffer copies default to one row. Destruction releases both resource
references for every operation through the existing command cleanup.
No new owned array or separate execution path is added.

ASan/UBSan host checks pass in normal and deterministic Swift-hashing modes:
four formats; aggregate and stack-passed Objective-C arguments; different
texture dimensions/row strides; zero destination bytes before commit;
source updates after encoding; dependent copies across encoders; disjoint
same-texture copies; exact destination pixels and untouched neighbors;
resource survival after caller releases. Ten rejection modes per format
cover slices, levels, overflow/out-of-range origin, zero size, format/device
mismatch, overlap and ended encoders, across two drained runtimes per run.
Existing shared-texture and buffer-blit/state/lifetime/eight-worker checks
also pass. The default/native Metal suite was not rebuilt in this checkpoint.

Complete qualified evidence is retained outside Git:

`/Users/alex/Library/Caches/vinix-ios/metal-texture-blit-validation-20261112-r1/`

Its archive was decoded/extracted to `metal-texture-blit-restoration-20261112-r1/`.
Saved source/compiler/header/executable identities match; the restored
sanitizer executable passes all three test groups again, and the archive
checksum passes afterward. Receipts remain beside the bundle. The maintained
harness retains its documented compiler-preamble corrections. Toolchain
library symlinks, host dylibs and SDKs remain external prerequisites; their
complete closures are not sealed. This is not a full typed-inventory audit.
Leak detection is disabled; object drainage is checked, retained heap is not
measured. No guest, shader, iOS application or GPU command ran. Buffer/texture
transfers, rendering and presentation remain pending; no Fortnite frame or
launch boundary is advanced.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `955ae1a2d2bf339576e997cae182879cd8038ba23111e82a5db666b70bea03f7` |
| `source.tar`, revision `964e0289d` | `4edd8c8dbe14bf3f1d8ddff642198d8139b70554cabbf713ef9e111758885b78` |
