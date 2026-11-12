# Software Metal buffer execution — 2026-11-12

`04c49fb05` introduces an opt-in Metal command backend in V. Build the runner
with `-d ios_metal_software`: default-device creation returns an owned software
device supporting shared buffers, command queues, command buffers and blit
encoders. Copies are deferred until commit and execute in encoding order;
commit completes synchronously with CPU-visible destination bytes. Resource
references survive caller releases until command-buffer destruction.

This is a bounded Metal API implementation, not a complete rendering backend.
Shader libraries/pipelines, compute dispatch, textures, render encoders,
drawables, presentation and GPU execution remain unimplemented. The ordinary
runner still returns nil. No Fortnite frame or launch boundary is advanced.
See [the implemented API and build instructions](../../compat/ios/runner/METAL.md).

ASan/UBSan host checks pass in normal and deterministic Swift-hashing modes:

- Actual Objective-C message-send ABI for device, buffer, queue, command and
  blit methods; scoped default-device import and owned creation results.
- Zero-initialized/shared bytes, copied input, offset copies, deferred visibility,
  ordered dependent copies across encoders, completion/status and wait.
- Buffer limits/options, overflow-safe bounds, same-buffer overlap rejection,
  cross-device rejection and invalid encoding/commit transitions.
- Ten invalid-state cases, eight concurrent workers per runtime, retained
  resources after caller releases and two fully drained runtimes per run.
- Default build retains nil-device behavior, eight-worker checks and invalid
  CoreVideo cache rejection; native macOS device/protocol/release checks pass.

Qualified outputs are `qualified-r6/` and `default-r3/` under:

`/Users/alex/Library/Caches/vinix-ios/metal-software-validation-20261112-r1/`

Earlier failed compiler attempts remain diagnostic. The maintained V harness
preserves generated C before restoring complete captured integer-128/libc
preambles and removing an obsolete sigaction forward declaration in favor of
the SDK declaration. This addresses a captured development compiler reloading
changed absolute-path headers with stale lengths; program function bodies
are preserved. The final harness also requires test execution markers.

The complete archive was decoded/extracted into
`metal-software-restoration-20261112-r1/`. Restored compiler/header/source and
qualified executable identities match their saved checksums; both restored
sanitizer binaries pass again. The archive checksum passes afterward.
Receipts remain beside the archive. Toolchain library/dependency symlinks,
host dylibs and SDKs remain external prerequisites; their complete closures
are not sealed. This is not a full typed-inventory audit. Leak detection is
disabled; object drainage is checked, retained heap allocation is not measured.
No Vinix guest, AIR shader, iOS application or GPU command ran.

| Artifact | SHA-256 |
| --- | --- |
| `.complete.tar.zst` beside bundle | `257812f2bad813196d8b02ac1013d13817115ead42586d1937f3f8e94ba65a68` |
| `source.tar`, revision `04c49fb05` | `59ffd60e2d5a71a6d5f01c2851b386ef1b3dd755b6b7bb27625d7624da9363ef` |
