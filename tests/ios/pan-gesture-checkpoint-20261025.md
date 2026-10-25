# Fortnite pan gesture checkpoint — 2026-10-25

Runtime and test revision: `5d497e0cd67cc7267a4251acf885af1b929f7251`.
Advertising work remains skipped.

UIKit now resolves scoped `UIPanGestureRecognizer` and
`UIScreenEdgePanGestureRecognizer` class/metaclass imports. Their inheritance
matches the local SDK: edge pan inherits from pan, which inherits from
`UIGestureRecognizer`. App subclass metadata and inherited class reflection
work. These are shim descriptors; Apple's private instance layout is not
implemented.

Pan construction requires an implemented continuous touch lifecycle and fails
explicitly. Guards cover direct and caller-storage allocation, subclass
allocation, saved NSObject allocation/initialization IMPs, and isa changes.
Unsupported initialization, copy/coding and pan property/recognition selectors
are absent from builtin method reflection. Existing base and swipe recognizer
construction still passes. Continuous pan input is not implemented.

A fresh Vinix ARM64 QEMU Fortnite probe passes the pan imports and stops at:

```text
iOS: linking /opt/ios/FortniteClient-IOS-Shipping: iOS: framework symbol is not implemented: _OBJC_CLASS_$_UIPinchGestureRecognizer
```

The runner exits 1 during linking, before application entry. The probe wrapper
exits 0 because it captured that failure. Rendering, login and gameplay remain
unverified; Fortnite has not started successfully.

Assertion-enabled host fixtures pass ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. The focused ARM64 QEMU fixture passes with
child status 0: scoped imports, class/metaclass inheritance, subclass metadata,
method reflection, base/swipe construction, two drained runtimes and 32 explicit
fatal rejection cases. Runtime object counters balance. ASan leak detection
was disabled; this does not establish absence of all heap leaks. The driver,
ARM64 fixture, initializer and GLES runner build successfully. The broader
native regression suite and import audits were not rerun.

Archive: `/Users/alex/Library/Caches/vinix-ios/pan-gesture-startup-20261025.tar.zst`.
Archive SHA-256: `2fb84802b1475f9f7b2e0490baec09d20abe89081649ce27a6a60de4fc698354`.
Contained manifest SHA-256: `41b10fc424e4cff63f92dc8192de21efcf4f7a2da1550aeb5c5d8fcd49753028`.

The bundle preserves 12 committed source snapshots, both V audit helpers,
75 selected input hashes (including SDK gesture declarations), generated C,
host objects/app, compiled drivers and ARM64 binaries, commands/statuses, and
complete boot media, initramfs, firmware variables, Limine configurations and
serial logs for both VMs. All 72 files other than the manifest are checksummed.
Local Fortnite assets remain in external storage. Compiler, header and
host-library closures are not independently sealed; rebuilding requires the
prepared checkout dependencies. Historical checkers are unchanged.

Compression integrity and original-bundle selftest pass. A fresh extraction at
`/Users/alex/Library/Caches/vinix-ios/pan-gesture-restored-20261025/pan-gesture-20261025`
also passes full checksums, rejection of missing guest media, an altered host
log and an unmanifested file, restoration of each mutation, and final checking.

Reproduce using the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`, `V_RESOURCE_PATH` set to that toolchain and
`V_MACOS_V3_NO_FALLBACK=1`. Build `tests/ios/notification-checks.v`,
`notification-vm.v`, `native-checks.v`, `pan-gesture-input-inventory.v` and
`pan-gesture-evidence.v`. Invoke the notification-checks driver with a fresh
external directory and modes `driver-build`, `pan-gesture-host`,
`build-pan-gesture`, `build-init`, `build-run-ios-gles`, `pan-gesture`, `probe`.
Fixture generation preserves assertions. Invoke the inventory helper with
repository root, bundle directory and tested revision; copy both audit helpers
into the bundle as `inventory-inputs.v` and `pan-gesture-evidence.v`. Use checker
modes `seal DIR`, `selftest DIR` and `hash FILE` to seal, audit and hash it.
