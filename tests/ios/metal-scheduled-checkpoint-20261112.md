# Software Metal scheduling — 2026-11-12

`a7112ba4a` adds `addScheduledHandler:` and `waitUntilScheduled` to the
opt-in software command buffer. Commit invokes copied scheduled blocks in
registration order outside the runtime lock at status 3, before executing
deferred copies/fills. Scheduled handlers have a separate 4,096-entry limit
and release their captures after invocation or on command abandonment.
Commit retains the command throughout callbacks and work.

`waitUntilScheduled` waits for all scheduled callbacks to return, independently
of completed callbacks. Both waits reject uncommitted commands. Waiting for
scheduling from a scheduled callback on that same command would deadlock.
Scheduling is synchronous CPU notification, with no GPU submission. See
[METAL.md](../../compat/ios/runner/METAL.md).

All twelve software groups pass under ASan/UBSan on macOS ARM64 with normal
and deterministic Swift hashing. The new test checks three copied callbacks
at status 3 while destination bytes are still zero, unlocked cross-thread
status queries, a blocked scheduled waiter, return while a completed callback
remains blocked, eventual copied bytes, capture disposal, abandonment, nil/late
registration rejection and uncommitted-wait rejection across two drained
runtimes. The ordinary runner suite was not rebuilt for this opt-in change.

Evidence bundle:

`/Users/alex/Library/Caches/vinix-ios/metal-scheduled-validation-20261112-r1/`

The sibling archive was decoded/extracted into a fresh `-restored` directory.
Saved source/compiler/header/executable hashes match, and the restored
sanitizer executable passes all twelve groups. The archive checksum passes
afterward; receipts remain beside the bundle. The harness retains its
documented compiler-preamble corrections. Toolchain library symlinks, host
SDKs and dylibs remain external prerequisites; dependency closures are not
sealed. This is not a full typed-inventory audit. Leak detection is disabled;
object drainage is checked, retained heap is not measured. Shader execution
and presentation remain pending. No Fortnite frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `b0b3726e12bfe6401de72192e2ea970018f79b076d333b6bc7797bb3d5ba35be` |
| `source.tar`, revision `a7112ba4a` | `6f5e66c37377db247f85ad999ddb43e5bd62328ce42cf6bfef40be5562a0fc5d` |
