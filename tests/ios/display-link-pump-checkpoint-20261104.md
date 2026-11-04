# Display-link loop pump checkpoint — 2026-11-04

`0f7dc55d11361b9bd89bb84a8b719840225a5e06` allows a CADisplayLink to
register with a background thread's run-loop handle and delivers its callbacks
on that thread through `NSRunLoop runMode:beforeDate:`. The desktop's polling
path now selects only main-loop links. Targets and links are retained while a
callback is selected; application code and final releases run outside the
registry lock. An already selected callback may finish after invalidation.
`a64b405dc4b6f75e28face3d26214c5948a1b3c2` adds `NSRunLoop run` over
that default-mode pump, returning when no supported sources remain or shutdown
begins. Its mode and distant-future date references are released on return.

Default and common registrations have independent membership bits; duplicate
adds retain one registration, and removing one mode leaves the other active.
The registration retains its loop and link. Invalidation removes the registration
and releases the target, including when called from another thread. This follows
[Apple's documented invalidation ownership and thread-safety contract](https://developer.apple.com/documentation/quartzcore/cadisplaylink/invalidate%28%29).

The pump waits on a native condition variable, waking on scheduling, pause/rate
changes, removal, invalidation and shutdown. It checks its owner thread, rechecks
deadlines after wakes, and returns false for an empty supported mode. Shutdown
signals the pump before joining managed workers. Thread exit detaches its links
before draining autoreleases; native wait primitives are freed after thread users
have stopped. BOOL setters consume the argument's low byte.

The supported profile remains one loop per link, at most 1024 registered links,
default mode as the only runnable/common member, and the existing virtual 60 Hz
clock. Custom registrations and a link spanning multiple loops fail explicitly.
Other timer/input-source classes, CFRunLoop pumping APIs and NSRunLoop methods
beyond `run` and `runMode:beforeDate:` remain outside this change. This is
software timing; physical display synchronization and native callback timing
were not measured.

The expanded `cf_run_loop_main_test.v` passes normal and deterministic ASan/UBSan
runs and standalone guest execution. Native Catalyst checks match all supported
CADisplayLink encodings and the pump's `B32@0:8@16@24` encoding. Runtime tests cover
default/common membership, duplicate adds, pause deadlines, BOOL register
canaries, foreign/self/in-flight invalidation, target retention during callbacks,
main-loop isolation, thread-exit removal, four groups of four concurrent worker
loops per runtime, and managed shutdown with a 15-second guard. Two full runtime
cycles drain to zero live objects and clear both wait-primitive pointers. The
`run` cases return after self-invalidation, foreign removal of the last link,
and shutdown of a paused managed thread. Existing
main/current-loop, NSThread and StoreKit regressions pass. The focused host driver
selects Catalyst for this fixture.

The final guest uses 4096 MiB and four CPUs, records child wait status 0 and
`VINIX iOS RUNLOOP: PASS`. Its state in the focused bundle is
`guest/run-loop-241615516583/`. Managed-thread fixtures explicitly initialize and
stop system data, as required by the existing Linux thread backend.

Fortnite passes the background registration and `run` calls, then stops at:

```text
V panic: iOS: unimplemented Objective-C method GCController startWirelessControllerDiscoveryWithCompletionHandler:
```

All 46 game-probe fixtures pass (45 reused plus freshly rebuilt StoreKit).
Original cooked content is retained and advertising remains skipped. The probe
uses 8192 MiB, one CPU, a 2 GiB application budget and a 60-second desktop window.
The final peer records 19 builds, 18 polls, handshake=true, closed=false,
supervisor_kill=false and wait=256. All six budget event counters are zero.
The final charge of 735758 bytes is after exit, not peak footprint. Application
exit is 1 and capture exit is 0. The next work is controller discovery's
asynchronous completion and cancellation semantics for the existing controller
backend.

Progress remains **four of eight observed gates**: loading/binding, +load,
initializers and application entry. No rendered game frame, menu, login or
playable match is verified. This fraction is not an engineering completion
percentage or a time estimate.

The unchanged saved auditor passes inspect, seal, independent check and all 339
corruption controls. Supplemental StoreKit media comparison and guest-result
checks also pass. Both final bundles remain expanded on persistent storage with
external typed receipts covering every path, file's bytes, type and permissions.
Integrity verification does not establish game rendering.

Complete artifacts under `/Users/alex/Library/Caches/vinix-ios/`:

| Artifact | Location | SHA-256 |
| --- | --- | --- |
| Focused validation | `display-pump-validation-20261104-r2/` | External receipt below |
| Validation receipt | `display-pump-validation-20261104-r2.inventory.json` | `a883e753e2c88ce4dc3f1820fca30ddf28b39bea26cc2ebc8deec9717b40d438` |
| Validation source | `display-pump-validation-20261104-r2/source.tar` | `66716e14b92d6755e6d94d24836aa22d05f320137d05e5d5f31931a8c46e9a91` |
| Complete capture | `display-pump-probe-20261104-r2/` | External receipt below |
| Capture manifest | `display-pump-probe-20261104-r2/manifest.sha256` | `dfd38c08ac1b226ddc296210c90e9edbaa5778e60dca018128abbf89d0ce2b77` |
| Capture receipt | `display-pump-probe-20261104-r2.inventory.json` | `0634693d3c98ad8813f5643e38403d389841b0b213a31ac18ef21c05c8eaf957` |
| Capture source | `display-pump-probe-20261104-r2/source.tar` | `66716e14b92d6755e6d94d24836aa22d05f320137d05e5d5f31931a8c46e9a91` |
| Runtime | `display-pump-probe-20261104-r2/run-ios-gles` | `2e9524f43fac7b2c8bc42ac2367702c793da789206c95a8579d46401c4bae8c2` |
| Serial | `display-pump-probe-20261104-r2/probe-no-ads-132916/serial.log` | `211570d10a47752006fd3f223c21f6450b7c181513a979cc13c543cd28972054` |

Both final bundles pin `a64b405dc4b6f75e28face3d26214c5948a1b3c2`.
The intermediate `display-pump-probe-20261104-r1/` pins `0f7dc55d1`, passes
inspect and the supplemental StoreKit checks, and observes the missing `run`
method. Its complete typed receipt is
`display-pump-probe-20261104-r1.inventory.json`, SHA-256
`442845e610bdd2f29943079f68ec07734b8ccbaaff12b6c1e831ba1a691ecb32`.
That intermediate is retained for integrity/provenance without a sealed launch
qualification. The initial focused bundle and receipt remain at
`display-pump-validation-20261104-r1/` and
`display-pump-validation-20261104-r1.inventory.json` (SHA-256
`c962d4f7b0d5880bb8fb1c901961688da01f01fb541b7cdbaf72511dcdf14824`).

Builds use frozen V
`c6bb06f` and the qualified dictionary checkpoint's existing kernel/media, with
parent manifest `c1163dfbb2bf9b0f096eba6123246028b00a43902ebd9963b115909b999e3dbb`.
The unchanged game executable SHA-256 is
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
Concurrent kernel/Linux/Android workspace changes are outside this qualification.

The first two sealing attempts failed during temporary boot-member/asset
extraction when the shared disk filled. They are retained under
`audio-category-20261027-work/` as `display-pump-seal-r2.log` and
`display-pump-seal-r2-retry1.log`.
No auditor checks were removed. `318f4d51a` adds the read-only
`swift-staging-archive.v check-archive ARCHIVE SHA256 RESTORED` mode: libarchive
streams every payload into an mtree SHA-256 inventory, compared against the
complete restored tree, including root/directory modes and link targets. It
rejects ambiguous paths, duplicate entries and unsupported types; seven
corruption cases and the six existing staging controls pass.

The existing complete restored trees for GKLeaderboard, GKPlayer, GKLocalPlayer
and NSProxy (2026-10-25) each matched their checksum-pinned archive directly and
passed their unchanged saved auditor before their `*-restored-20261025/`
directories were removed. Their original working directories were left alone;
the four `.tar.zst` archives remain intact at the paths pinned by the
[GKLeaderboard](gk-leaderboard-checkpoint-20261025.md),
[GKPlayer](gk-player-checkpoint-20261025.md),
[GKLocalPlayer](gk-local-player-checkpoint-20261025.md), and
[NSProxy](ns-proxy-checkpoint-20261025.md) reports.
This frees scratch space without weakening a historical checker or retiring
either complete game capture from this checkpoint. Restoration is required for
future audits of those cold archives.

The proof bundle is `display-pump-storage-validation-20261104-r1/`, with external
receipt `display-pump-storage-validation-20261104-r1.confirmed.inventory.json`
(SHA-256 `0afea7f2dbde763231181c052e89363398d0fe04fc96fe7128366cbf976904aa`).
It preserves archive checksums, all four manifest copies and saved auditors,
direct archive/tree checks, self-test results and the checker source/executable.

Reproduce using `tests/ios/notification-checks.v` modes `run-loop-host`,
`thread-host` and `storekit-purchase-host`, and `tests/ios/notification-vm.v`
mode `run-loop`, each with fresh external output directories. VM mode requires
`VINIX_IOS_CHECK_NAME=notification-center-checks`; this run sets
`VINIX_IOS_KERNEL` to the qualified dictionary checkpoint kernel. The game uses
`tests/ios/storekit-operation-probe.v --queue-clone`. Preserve the complete
capture at its recorded path for the saved auditor. Verify typed receipts with
`tests/ios/evidence-delta-archive.v check-inventory BUNDLE RECEIPT`.
