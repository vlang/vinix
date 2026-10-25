# Fortnite Game Center checkpoint — 2026-10-25

Runtime and test revision: `38910a81724a87cd1709fa26aeb2fe2cb7ae45f8`.
Advertising work remains skipped.

GameKit now resolves scoped `GKGameCenterViewController` class/metaclass
imports. Its UIKit parent chain is
`GKGameCenterViewController -> UINavigationController -> UIViewController`,
following the installed iOS SDK declarations. The new classes provide metadata
and subclass reflection only. Construction, caller-provided storage, saved
NSObject allocation IMPs and storage isa changes fail explicitly. Navigation,
Game Center UI, authentication and services remain unsupported. Shim storage
inherits the existing UIViewController size; native private layout parity was
not measured or claimed.

A fresh Vinix ARM64 QEMU Fortnite probe passes the GameKit import and stops at:

```text
iOS: linking /opt/ios/FortniteClient-IOS-Shipping: iOS: framework symbol is not implemented: _OBJC_CLASS_$_UITextRange
```

The runner exits 1 during linking, before application entry. The probe wrapper
exits 0 because it captured that failure. Rendering, login and gameplay remain
unverified; Fortnite has not started successfully.

Assertion-enabled host fixtures pass ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. The focused ARM64 QEMU fixture passes with
child status 0: scoped imports, SDK inheritance, subclass metadata, truthful
reflection, two drained runtimes and 30 explicit fatal rejection cases.
Runtime object counters balance. ASan leak detection was disabled; this does
not establish absence of all heap leaks. The driver, ARM64 fixture,
initializer and GLES runner build successfully. The broader native regression
suite and import audits were not rerun.

Archive: `/Users/alex/Library/Caches/vinix-ios/game-center-startup-20261025.tar.zst`.
Archive SHA-256: `3a89f764927896246791c106fbd04d348f3745a5f3419ad8bb425848680ef3eb`.
Contained manifest SHA-256: `fa44498598c28b3b36d50e5d7900ef811f0748c195cd0ab686dcde05bf9b3ef0`.

The bundle preserves 12 committed source snapshots, both V audit helpers,
74 selected input hashes (including both SDK parent declarations), generated
C, host objects/app, compiled drivers and ARM64 binaries, commands/statuses,
and complete boot media, initramfs, firmware variables, Limine configurations
and serial logs for both VMs. All 72 files other than the manifest are
checksummed. Local Fortnite assets remain in external storage. Compiler,
header and host-library closures are not independently sealed; rebuilding
requires the prepared checkout dependencies. Historical checkers are unchanged.

Compression integrity and original-bundle selftest pass. A fresh extraction at
`/Users/alex/Library/Caches/vinix-ios/game-center-restored-20261025/game-center-20261025`
also passes full checksums, rejection of missing guest media, an altered host
log and an unmanifested file, restoration of each mutation, and final checking.

Reproduce using the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`, `V_RESOURCE_PATH` set to that toolchain and
`V_MACOS_V3_NO_FALLBACK=1`. Build `tests/ios/notification-checks.v`,
`notification-vm.v`, `native-checks.v`, `game-center-input-inventory.v` and
`game-center-evidence.v`. Invoke the notification-checks driver with a fresh
external directory and modes `driver-build`, `game-center-host`,
`build-game-center`, `build-init`, `build-run-ios-gles`, `game-center`, `probe`.
Fixture generation preserves assertions. Invoke the inventory helper with
repository root, bundle directory and tested revision; copy both audit helpers
into the bundle as `inventory-inputs.v` and `game-center-evidence.v`. Use checker
modes `seal DIR`, `selftest DIR` and `hash FILE` to seal, audit and hash it.
