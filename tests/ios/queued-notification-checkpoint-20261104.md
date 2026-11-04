# Queued notification observer checkpoint — 2026-11-04

`8fadb70a1f46c13b41774c634a00cd16dab471a2` implements the operation-queue
argument of NSNotificationCenter's addObserverForName:object:queue:usingBlock:.
Registrations retain their queue. Posting snapshots pin the recipient, block,
queue and notification until delivery retires. A private completion waits only
for this notification's operation, so unrelated later work cannot delay post.
Same-queue posts run inline, including main-thread posts to mainQueue, avoiding
self-deadlock. Nil-queue delivery keeps its existing posting-thread behavior.

Native Foundation comparisons confirm synchronous posting, main/worker affinity,
nested same-queue delivery, and suppression of a pending callback after removal.
A removed registration clears its active block under the registry lock; capture
destructors, callbacks and waits run outside registry/scheduler locks. Scheduler
discard signals a waiting poster even when its callback never runs. Foreign
posting threads must still join before Foundation teardown; the shutdown test
explicitly stops dispatch, joins its poster, then tears down Foundation.
See [Apple's registration documentation](https://developer.apple.com/documentation/foundation/notificationcenter/addobserver%28forname%3Aobject%3Aqueue%3Ausing%3A%29)
for the queue, copied-block and token contracts.

Both ASan/UBSan host runs (normal and deterministic hashing) pass shared native
and runtime cases, including a blocked later operation proving that post waits
only for its own delivery. Runtime cases also verify registration-owned queue
lifetime with weak references, pending removal, shutdown wakeup and two drained
runtime lifetimes with zero live objects and heap blocks. Existing nil-queue
tests retain filter, token, reentrant removal, unlocked capture and eight-worker
coverage. Both StoreKit host regression runs pass.

A new standalone `notification-block` guest mode runs the expanded fixture.
The 4096 MiB, four-CPU guest exits with child wait status 0 and prints
`VINIX iOS NOTIFICATIONBLOCK: PASS`; state is
`notification-guest/notification-block-47857098708` in the focused bundle below.
All test/tool changes are V, and generated output stays outside Git.

Fortnite gets past queued notification registration and now stops at:

```text
V panic: iOS: unimplemented Objective-C method UIDevice valueForKey:
```

The current diagnostic does not record the key argument. Identify that key and
compare native key-value lookup behavior before choosing the next compatibility
implementation; the existing UIDevice dispatcher exposes direct getters.
The preceding [main operation queue checkpoint](main-operation-queue-checkpoint-20261104.md)
remains qualified.

All 46 game-probe fixtures pass (45 reused and freshly rebuilt StoreKit).
The capture preserves original cooked content and skips advertising. It uses
8192 MiB, one CPU, a 2 GiB application budget and a 60-second desktop window.
The peer records 22 builds, 21 polls, two nodes, zero images, closed=false,
supervisor_kill=false and wait=256. All six budget event counters are zero.
The final charge of 702990 bytes is after exit, not peak footprint. Application
exit is 1 and capture exit is 0.

Progress remains four of eight observed gates: loading/binding, +load,
initializers and application entry. No game frame, menu, login or playable match
is verified. This fraction is not an engineering completion percentage or ETA.

The unchanged saved auditor passes inspect, seal, independent check and all
339 corruption controls. Supplemental StoreKit media/guest-result checks pass.
Both complete bundles are retained expanded on persistent storage with external
typed integrity receipts covering all bytes, paths, types and permissions.
No complete evidence was retired and no historical checker was weakened.

Artifacts under `/Users/alex/Library/Caches/vinix-ios/`:

| Artifact | Location | SHA-256 |
| --- | --- | --- |
| Focused validation | `queued-note-validation-20261104-r1/` | Receipt below |
| Validation receipt | `queued-note-validation-20261104-r1.inventory.json` | `ddd61118c695e07ff8cbedf07e0cc6da65d62b85be78391cd4245d9b51a9470d` |
| Complete game capture | `queued-note-probe-20261104-r1/` | Manifest below |
| Capture manifest | `queued-note-probe-20261104-r1/manifest.sha256` | `8f80dc357e3cae445a373c14277f97db994c20499bdfdace82c83014bf4fdc86` |
| Capture receipt | `queued-note-probe-20261104-r1.inventory.json` | `7a8e4367d84fa73424e7939d24269974a0922c05d3c97f639d1b81e4d5a6d5d6` |
| Source archive (both bundles) | `source.tar` | `5a45ad136573f11ae66ed5f69b086d97bed3314c19bb891faa882275f9cbf9cb` |
| Runtime | `queued-note-probe-20261104-r1/run-ios-gles` | `5b375e32fba9ded7618198a1baeb8fc1a213b2a4cbe0fbb3be705d166f13f444` |
| Serial log | `queued-note-probe-20261104-r1/probe-no-ads-132916/serial.log` | `f9fc345517e79a9e99828452ee776f1057b1bb3c7921763ec5a67cb13a794dcd` |

Both source archives pin the implementation revision above. Builds use frozen
V `c6bb06f` and the dictionary checkpoint's existing kernel/media, with parent
manifest SHA-256 `c1163dfbb2bf9b0f096eba6123246028b00a43902ebd9963b115909b999e3dbb`.
Concurrent kernel/Linux/Android edits are outside this validation.

Maintained drivers: `tests/ios/notification-checks.v notification-block-host`,
`tests/ios/notification-vm.v notification-block`, and StoreKit host regression
mode, each with a fresh external output directory and the frozen toolchain.
VM mode requires `VINIX_IOS_CHECK_NAME=notification-center-checks`; this run sets
`VINIX_IOS_KERNEL` to the qualified dictionary checkpoint kernel. The game uses
`tests/ios/storekit-operation-probe.v --queue-clone` with the complete parent and
fresh host results. Keep the capture at its recorded path for its saved auditor.
Use `tests/ios/evidence-delta-archive.v check-inventory BUNDLE RECEIPT` for the
independent typed integrity check; it does not itself qualify game rendering.
