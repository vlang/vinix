# UIScreen checkpoint — 2026-11-04

`bb407567e556566940cb2ee17bd28dc5a44f41e2` implements `nativeBounds`
and complete getter discovery/type metadata for the existing screen geometry.
`2c6a5036c4bb95ffc94bde534ce9749d6d235edc` adds
`maximumFramesPerSecond`, sharing the existing 60 Hz ceiling with CADisplayLink.
The virtual display remains portrait, 390 × 680 native pixels, scale 1.
Resizing a desktop/application window changes that window's geometry. Physical
monitor discovery, orientation changes and variable refresh rates are outside
this implementation. The maximum is a nominal capability; callback delivery
depends on the desktop main event loop.

The frame-rate getter returns signed NSInteger (`q16@0:8`) through x0;
the rectangle getters return a four-double CGRect HFA in vector registers.
Shared Catalyst/runtime tests verify direct IMP and objc_msgSend results,
instance-only discovery, encodings and positive native values. Runtime tests
cover inherited mainScreen lookup, stable cache identity, untouched indirect
result guards, integer/vector register separation, independent window resizing,
and two complete lifetimes drained to zero live objects. Display-link checks
cover its default, lower preferred rates, zero/default selection, requests above
the ceiling, frame intervals and duration. A lower preferred cadence leaves the
screen maximum unchanged. The native screen's maximum may differ from Vinix's.

Both fixes pass normal and deterministic ASan/UBSan host runs, native Catalyst
comparisons, standalone guest execution and both StoreKit regression runs.
Guest screen fixtures use 4096 MiB and four CPUs, record child wait status 0 and
`VINIX iOS VIEWTAG: PASS`. The final guest state is
`screen-guest/view-tag-75452053333/`. Aggregate NSMethodSignature/NSInvocation
support remains outside the existing scalar profile; CGRect is tested through
metadata and actual typed/raw ABI calls.

The first game probe gets past nativeBounds and stops at maximumFramesPerSecond.
The second passes both screen queries and stops at:

```text
V panic: iOS: background NSRunLoop is not implemented
```

The next work requires thread-specific current run-loop identity and lifetime;
the current runtime only caches the main loop and its desktop scheduler.
Returning that main loop from a background thread would lose thread affinity.

Both probes retain original cooked content, skip advertising and pass all 46
fixtures (45 reused plus freshly rebuilt StoreKit). Each uses 8192 MiB, one CPU,
a 2 GiB application budget and a 60-second desktop window. The final peer records
12 builds, 11 polls, handshake=true, closed=false, supervisor_kill=false and
wait=256. All six budget event counters are zero. The final charge of 702990
bytes is after exit, not peak footprint. Application exit is 1; capture exit is 0.

Progress remains **four of eight observed gates**: loading/binding, +load,
initializers and application entry. No rendered game frame, menu, login or
playable match is verified. This fraction is not an engineering completion
percentage or a time estimate.

Both unchanged saved auditors pass inspect, seal, independent check and all 339
corruption controls. Supplemental StoreKit media comparisons and guest-result
checks also pass. Complete bundles remain expanded on persistent storage with
external typed receipts covering every path, file's bytes, type and permissions.
Integrity checks do not establish game rendering.

Complete artifacts under `/Users/alex/Library/Caches/vinix-ios/`:

| Artifact | Location | SHA-256 |
| --- | --- | --- |
| Bounds focused bundle | `screen-bounds-validation-20261104-r1/` | External receipt below |
| Bounds validation receipt | `screen-bounds-validation-20261104-r1.inventory.json` | `b49a4d30de5d844b9d68a1485fc5e827c246792195cfb7c26d4ad7dc4f55ce68` |
| Bounds source | `screen-bounds-validation-20261104-r1/source.tar` | `afa1502cd2e280a480b411a8cf428c0e60328202c4469685a980b2dc73a7a2dd` |
| Bounds capture | `screen-bounds-probe-20261104-r1/` | External receipt below |
| Bounds manifest | `screen-bounds-probe-20261104-r1/manifest.sha256` | `c4b3e49412a88f23719cfc7040db6c69424f445d4c13e9437ec10bd02f39ca62` |
| Bounds capture receipt | `screen-bounds-probe-20261104-r1.inventory.json` | `9616f63f7cd9babacfda916d6e230a5572054b78f1d21f968ed7e82e65ad28ad` |
| Final focused bundle | `screen-fps-validation-20261104-r1/` | External receipt below |
| Final validation receipt | `screen-fps-validation-20261104-r1.inventory.json` | `84fdd2fbabb4dc7af440631b87bfeaa379ba612cc55fe2cfe5421e5a8b507a59` |
| Final source | `screen-fps-validation-20261104-r1/source.tar` | `4e9e1cae05a97714b3e53eec6ffd80d1d116aaab290f4234a65373105a81ad25` |
| Final capture | `screen-fps-probe-20261104-r1/` | External receipt below |
| Final manifest | `screen-fps-probe-20261104-r1/manifest.sha256` | `b25733a69c6f28a8b809bd7406a0ae62e1cc705c5b7729fc9ab13ca390136ec6` |
| Final capture receipt | `screen-fps-probe-20261104-r1.inventory.json` | `f477c0d0cebcd5858f52c2458bc70e20702067363a14020d9436276be55dcfdd` |
| Final runtime | `screen-fps-probe-20261104-r1/run-ios-gles` | `cfe2fa945f0c385fcfeaf1de4fc10220378f57d6f5d4f7547542fc597671a424` |
| Final serial | `screen-fps-probe-20261104-r1/probe-no-ads-132916/serial.log` | `7c112e8a7f4228835f54619c2a49a4a6872623cc583d1445236d60069cc36d1f` |

Each capture pins its corresponding implementation commit and source tar above.
The source archives are identical between each focused bundle and its capture.
Builds use frozen V `c6bb06f` and the qualified dictionary checkpoint's kernel
and media, with parent manifest
`c1163dfbb2bf9b0f096eba6123246028b00a43902ebd9963b115909b999e3dbb`.
The unchanged game executable SHA-256 is
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
Concurrent kernel/Linux/package workspace edits are outside this qualification.

Reproduce focused checks with `tests/ios/notification-checks.v` modes
`view-tag-host` and `storekit-purchase-host`, and `tests/ios/notification-vm.v`
mode `view-tag`, using fresh external output directories. VM mode requires
`VINIX_IOS_CHECK_NAME=notification-center-checks`; set `VINIX_IOS_KERNEL` to the
qualified dictionary kernel. The game driver is
`tests/ios/storekit-operation-probe.v --queue-clone`. Preserve complete captures
at their recorded paths for the saved auditors. Verify typed receipts with
`tests/ios/evidence-delta-archive.v check-inventory BUNDLE RECEIPT`.

Storage preparation also added read-only `check ARCHIVE RESTORED` and corruption
self-tests to `tests/ios/swift-staging-archive.v`, committed as `a6f605d96`.
The retained failed-staging archive from the
[Swift optional lookup checkpoint](swift-optional-lookup-checkpoint-20261028.md)
was verified against its recorded archive/inventory checksums, its existing
expanded tree, and a fresh independent complete extraction. Both trees matched
exact paths, bytes, types, modes and link targets before the redundant expanded
trees were removed. The original archive, inventory and checksum receipt remain
unchanged on persistent storage. This does not retire qualified launch evidence.
The bounds focused bundle's `archive-checks/` retains the proof logs, including
six rejected corruption cases. No historical auditor was weakened.
