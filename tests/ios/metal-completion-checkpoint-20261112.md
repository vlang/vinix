# Software Metal completed handlers — 2026-11-12

`110ada828` adds `addCompletedHandler:` to the opt-in `ios_metal_software`
backend. Registration copies a valid block before commit, with at most 4,096
handlers. Commit retains the command buffer, executes copies under the runtime
lock, sets status 4, then invokes handlers in registration order outside that
lock. Each handler receives the command buffer and is released after invocation.
The separate finished flag is published under the lock after all handlers
return. Concurrent `waitUntilCompleted` calls poll that flag using short lock
acquisitions, so they cannot return while a handler is still running.

Abandoned buffers release uncalled handlers. Their owned array uses noslices
and is freed with command state. Copy/dispose helpers run outside the runtime
lock during registration/rejection, and callbacks can query from other threads.
Waiting before commit rejects. Waiting on the same command from its own handler
would deadlock; scheduled handlers remain unsupported. See
[the supported API](../../compat/ios/runner/METAL.md) and
[Apple's handler contract](https://developer.apple.com/documentation/metal/mtlcommandbuffer/addcompletedhandler%28_%3A%29).

ASan/UBSan host checks pass with normal and deterministic Swift hashing:
three copied stack blocks/capture retains, status and destination-byte
visibility in callbacks, exact invocation/disposal counts, callbacks joining
worker-thread status queries, a concurrent waiter held until handlers finish,
abandoned command disposal, null/late handler rejection and two drained
runtimes. All previous buffer, texture, transfer, blit, state/lifetime and
eight-worker tests pass. The default/native Metal suite was not rebuilt.

Qualified complete evidence is retained outside Git:

`/Users/alex/Library/Caches/vinix-ios/metal-completion-validation-20261112-r4/`

The archive was decoded/extracted to `metal-completion-restoration-20261112-r4/`.
Saved source/compiler/header/executable identities match; the restored
sanitizer executable passes all five groups again. The archive checksum passes
afterward, with receipts beside the bundle. Earlier attempts remain diagnostic.
The harness retains its documented compiler-preamble corrections. Toolchain
library symlinks, host dylibs and SDKs remain external prerequisites; complete
dependency closures are not sealed. This is not a full typed-inventory audit.
Leak detection is disabled; object/block drainage is checked, retained heap
allocation is not measured. No guest, shader, iOS app or GPU command ran.
Rendering and presentation remain pending; no Fortnite frame or launch
boundary is advanced.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `c76e72b29afe0f19f9d868d009a72b8b0e007c90c7d4430fbb38bb59724993bf` |
| `source.tar`, revision `110ada828` | `7d65a694c2ea6be274cc9895c0a9a36839b42cfb937fbf1d7e353b80f8bc79e0` |
