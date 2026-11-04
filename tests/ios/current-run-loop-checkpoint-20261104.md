# Current run-loop checkpoint — 2026-11-04

`eec4491b22b2dd3570a2a1510977f18ce6ba051a` implements background
`NSRunLoop currentRunLoop` identity and the scoped CoreFoundation export
`CFRunLoopGetCurrent`. Each background Foundation thread lazily owns one cached
handle in its existing TLS sidecar. Repeated NS/CF lookups return the same
borrowed handle, independently of autorelease pools. Concurrent workers have
distinct handles; the main thread keeps its existing runtime-owned main loop.
Thread exit clears and releases the background cache even when a caller retains
the finished NSThread. Caller-retained loop references remain valid until released.
The cache does not use reusable pthread identifiers as lifetime keys.

The change adds inherited class-method discovery and native-measured metadata:
`@16@0:8` for mainRunLoop/currentRunLoop and `^{__CFRunLoop=}16@0:8` for
getCFRunLoop. Direct IMP, message dispatch and NSMethodSignature agree.
Vinix continues using its existing NSRunLoop-backed handle representation;
this does not establish general toll-free bridging. Lookup does not pump a loop.
Background timers, input sources, modes and CADisplayLink callback delivery are
outside this change. Unowned NSRunLoop instances fail getCFRunLoop explicitly.

The expanded `cf_run_loop_main_test.v` passes native Foundation comparisons,
normal and deterministic ASan/UBSan executions, and a standalone guest run.
Tests cover NS-first and CF-first creation, eight distinct worker handles,
128 repeated reads per worker, pool independence, retained thread/loop lifetimes,
four groups of eight workers per runtime, scoped symbol resolution, inherited
metadata, direct IMPs, signatures and two runtimes drained to zero live objects.
Protected no-argument ARM64 calls preserve x20/x21 and do not write through
x0–x8 guard pointers. Existing main-loop display-link schedule/fire/remove/
invalidate tests still pass. The existing NSThread and StoreKit host suites also
pass both sanitizer configurations.

The standalone guest uses 4096 MiB and four CPUs, records child wait status 0
and `VINIX iOS RUNLOOP: PASS`. Its state is
`guest/run-loop-92477393250/` in the focused bundle below.
The maintained V drivers now expose `run-loop-host`, `thread-host`, and a
standalone `run-loop` VM mode; its marker requires successful child completion.

Fortnite gets past the previous background-NSRunLoop rejection and now stops at:

```text
V panic: iOS: CADisplayLink requires the main run loop
```

The next work is background display-link scheduling and loop pumping on the
owning thread. Routing those callbacks through the desktop main loop would lose
thread affinity. `display_link.c.v` currently polls a global display-link list
from the main event loop; production dispatch has no `runMode:beforeDate:` pump.
The next implementation needs owner-thread delivery, wakeups and shutdown/
invalidation lifetimes as well as accepting the new handle. The earlier
[screen checkpoint](screen-checkpoint-20261104.md) remains qualified.

All 46 game-probe fixtures pass (45 reused plus freshly rebuilt StoreKit).
The probe retains original cooked content, skips advertising and uses 8192 MiB,
one CPU, a 2 GiB application budget and a 60-second desktop window. Its desktop
peer records 28 builds, 27 polls, handshake=true, closed=false,
supervisor_kill=false and wait=256. All six budget event counters are zero.
The final charge of 719374 bytes is after exit, not peak footprint. Application
exit is 1; capture exit is 0.

Progress remains **four of eight observed gates**: loading/binding, +load,
initializers and application entry. No rendered game frame, menu, login or
playable match is verified. This fraction is not an engineering completion
percentage or a time estimate.

The unchanged saved auditor passes inspect, seal, independent check and all 339
corruption controls. Supplemental StoreKit media comparison and guest-result
checks pass. Both complete bundles remain expanded on persistent storage with
external typed receipts covering every path, file's bytes, type and permissions.
No complete evidence was retired and no historical checker was weakened.
Integrity verification does not establish game rendering.

Complete artifacts under `/Users/alex/Library/Caches/vinix-ios/`:

| Artifact | Location | SHA-256 |
| --- | --- | --- |
| Focused validation | `run-loop-validation-20261104-r1/` | External receipt below |
| Validation receipt | `run-loop-validation-20261104-r1.inventory.json` | `eebe8b359fa903e1bd0c48f509f3ddee980c779bca146525453ad71b4dfddaf8` |
| Validation source | `run-loop-validation-20261104-r1/source.tar` | `4e859061c43664b2611f8807ac9d76f6feb25956bad1bfd897d801153f1cd4a7` |
| Complete capture | `run-loop-probe-20261104-r1/` | External receipt below |
| Capture manifest | `run-loop-probe-20261104-r1/manifest.sha256` | `02123e1563d6a3420848bc299abdf3c766fd268f8750c563c4f9fdf593b697be` |
| Capture receipt | `run-loop-probe-20261104-r1.inventory.json` | `15775b80c1f3892f52aeb09fc9946fbd68cf8a89a090acb91be24e2ef7adbb79` |
| Capture source | `run-loop-probe-20261104-r1/source.tar` | `4e859061c43664b2611f8807ac9d76f6feb25956bad1bfd897d801153f1cd4a7` |
| Runtime | `run-loop-probe-20261104-r1/run-ios-gles` | `883a824af430cf723721843576349e475a866ac59f4bb119122f7d85f409c19e` |
| Serial | `run-loop-probe-20261104-r1/probe-no-ads-132916/serial.log` | `61e4252e1e867c55498844fa061056a4bcdccf3d979550ca91c275529da6f75b` |

Both bundles pin the implementation revision above. Builds use frozen V
`c6bb06f` and the qualified dictionary checkpoint's existing kernel/media, with
parent manifest `c1163dfbb2bf9b0f096eba6123246028b00a43902ebd9963b115909b999e3dbb`.
The unchanged game executable SHA-256 is
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
Concurrent kernel/Linux/Android changes are outside this qualification.

Reproduce with `tests/ios/notification-checks.v` modes `run-loop-host`,
`thread-host` and `storekit-purchase-host`, and `tests/ios/notification-vm.v`
mode `run-loop`, using fresh external directories. VM mode requires
`VINIX_IOS_CHECK_NAME=notification-center-checks`; this run sets
`VINIX_IOS_KERNEL` to the qualified dictionary checkpoint kernel. The game uses
`tests/ios/storekit-operation-probe.v --queue-clone`. Preserve the complete
capture at its recorded path for the saved auditor. Verify typed receipts with
`tests/ios/evidence-delta-archive.v check-inventory BUNDLE RECEIPT`.
