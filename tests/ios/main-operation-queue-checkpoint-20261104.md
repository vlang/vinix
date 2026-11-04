# Main operation queue checkpoint — 2026-11-04

`c4443597e80fa00f54090e03d894098947a95334` implements NSOperationQueue's
mainQueue and currentQueue accessors, inherited method metadata and selector
discovery. The runtime owns one lazily published singleton backed by the
existing main dispatch executor. Main operations run serially on the main
thread; changing suspension or maximum concurrency has no effect, matching
native Foundation. Ordinary block queues retain their existing serial workers.
See [Apple's mainQueue documentation](https://developer.apple.com/documentation/foundation/operationqueue/main).

Shared native/runtime tests race eight background lookups, submit copied blocks
from a background thread, verify no execution before the main loop drains,
check currentQueue on workers and on main, and compare dispatch callbacks on
main and on a serial queue targeted at main. Runtime tests also check inherited
selectors, type encodings and direct IMP calls. Pending main operations are
discarded at shutdown, releasing their captures outside scheduler locks;
capture destructors reenter the queue API. Weak references clear, the singleton
cannot be recreated during retired teardown, and two runtime lifetimes finish
with zero live objects and heap blocks.

Both ASan/UBSan host runs (normal and deterministic hashing), the final StoreKit
host regressions and the focused operation-queue guest pass. The focused guest
uses 4096 MiB and four CPUs, exits with wait status 0 and prints
`VINIX iOS OPERATIONQUEUE: PASS`. Its state is
`queue-guest/operation-queue-52608569750` in the validation bundle below.

The fresh Fortnite capture gets past mainQueue and stops at:

```text
V panic: iOS: notification observer operation queues are not implemented
```

The next blocker is NSNotificationCenter's
addObserverForName:object:queue:usingBlock: with a non-nil operation queue.
The existing implementation rejects that argument before registration; it
currently delivers block observers directly on the posting thread. Supporting
queued observers requires retained queue ownership and native comparisons of
delivery, posting completion, reentrancy, removal and shutdown semantics.

All 46 probe fixtures pass (45 reused and a freshly rebuilt StoreKit fixture).
Original cooked content is preserved and advertising remains skipped. The probe
uses 8192 MiB, one CPU, a 2 GiB application budget and a 60-second desktop window.
The peer records 15 builds, 14 polls, two nodes and zero images; closed=false,
supervisor_kill=false, wait=256. All six budget event counters are zero. The
final charge of 702990 bytes is after exit, not peak memory. Application exit
is 1 and capture exit is 0.

Progress remains four of eight observed gates: loading/binding, +load,
initializers and application entry. No rendered game frame, menu, login or
playable match is verified. This milestone fraction does not estimate remaining
engineering work or completion time.

The capture's unchanged saved auditor passes inspect, seal, independent check
and all 339 corruption controls. Supplemental StoreKit media and guest-result
checks also pass. Both complete bundles are retained expanded on persistent
storage, with external typed integrity receipts covering bytes, paths, types
and permissions. No evidence files were retired or checker requirements relaxed.

Artifacts under `/Users/alex/Library/Caches/vinix-ios/`:

| Artifact | Location | SHA-256 |
| --- | --- | --- |
| Focused validation | `main-queue-validation-20261104-r2/` | Receipt below |
| Validation receipt | `main-queue-validation-20261104-r2.inventory.json` | `1192c4f5faaa723a5fba4b888650f0cd56764caaa81d4d4cee335ec3f123e43f` |
| Validation source | `main-queue-validation-20261104-r2/source.tar` | `d2fcff19bdf9dd207eba82b3043c3ff31c6cad45485a281a632ad0315db0c71a` |
| Complete capture | `main-queue-probe-20261104-r1/` | Manifest below |
| Capture manifest | `main-queue-probe-20261104-r1/manifest.sha256` | `c21db12d217616828b6d979df992267cd237b99e7c9f7b14c31985749c8403ce` |
| Capture receipt | `main-queue-probe-20261104-r1.inventory.json` | `1e1a781bc774faa7dcdb5712a46b354668a6480661f6be21d330ef5df4c22bb0` |
| Capture source | `main-queue-probe-20261104-r1/source.tar` | `e8fe8ceb6594c89daf9218833516dc7a9a95691f077e9cb73147ca09e7240985` |
| Runtime | `main-queue-probe-20261104-r1/run-ios-gles` | `b38fad3694f8840ec76677be109eda783a520d89a32540b3d42d1cba247d2ec2` |
| Serial log | `main-queue-probe-20261104-r1/probe-no-ads-132916/serial.log` | `8ca1dc5a0199a07a41b6c1dceb2990c5cf664874cacab681e658f7cf47d0cf98` |

The focused source snapshot pins the implementation commit above. The game
capture pins `2709f6c7f716ad035da45124d7c81bc5634147dd`; its `compat/ios` and
`tests/ios` sources are identical to that implementation commit. Builds use the
frozen V `c6bb06f` toolchain and the previously qualified dictionary checkpoint's
kernel/media, whose parent manifest SHA-256 is
`c1163dfbb2bf9b0f096eba6123246028b00a43902ebd9963b115909b999e3dbb`.
Concurrent kernel/Linux/Android workspace changes are outside this validation.

Reproduce focused checks from the repository root using the frozen-toolchain V
drivers `tests/ios/notification-checks.v operation-queue-host FRESH_OUT` and
`tests/ios/notification-vm.v operation-queue FRESH_OUT`, plus StoreKit host
regressions. The maintained game coordinator is
`tests/ios/storekit-operation-probe.v` with `--queue-clone`. Preserve the complete
capture at its recorded path when invoking its saved `checkpoint` auditor.
Use `tests/ios/evidence-delta-archive.v check-inventory BUNDLE RECEIPT` to verify
each external integrity receipt; this does not itself certify game rendering.
