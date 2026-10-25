# Fortnite rotation gesture checkpoint — 2026-10-25

Runtime and test revision: `0cb3f5fc55ac325603f0f943b9d2d6be907564df`.
Advertising work remains skipped.

UIKit now resolves scoped `UIRotationGestureRecognizer` class/metaclass imports.
Inheritance matches the local SDK (`UIGestureRecognizer`), including app
subclass metadata and inherited class reflection. These are shim descriptors;
Apple's private instance layout and continuous two-touch recognition are not
implemented. Construction fails explicitly, including direct/caller storage,
subclasses, saved NSObject allocation/initialization IMPs and isa changes.
Unsupported initialization, copy/coding and rotation property/recognition
selectors are absent from builtin method reflection. Existing base and swipe
recognizer construction still passes.

A fresh Vinix ARM64 QEMU Fortnite probe passes the rotation import and stops at:

```text
iOS: linking /opt/ios/FortniteClient-IOS-Shipping: iOS: framework symbol is not implemented: _OBJC_CLASS_$_UITapGestureRecognizer
```

The runner exits 1 during linking, before application entry. The probe wrapper
exits 0 because it captured that failure. Fortnite has not started successfully;
rendering, login and gameplay remain unverified.

Assertion-enabled host fixtures pass ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. The focused ARM64 QEMU fixture passes with child
status 0: scoped imports, SDK inheritance, subclass metadata, truthful method
reflection, base/swipe construction, two drained runtimes and 16 explicit fatal
rejection cases. Runtime object counters balance. ASan leak detection was
disabled; this does not establish absence of all heap leaks. The drivers,
ARM64 fixture, initializer and GLES runner build successfully. The broader
native regression suite and import audits were not rerun.

Archive: `/Users/alex/Library/Caches/vinix-ios/rotation-gesture-startup-20261025.tar.zst`.
Archive SHA-256: `ae878a4d8e816e1aee5f345464c15924418fc52bccca5ad43f90c5bd30e8b993`.
Contained manifest SHA-256: `477473ccfd99f3223f2c76d4568a18f33603a4347fed5f97238d54408e41b39d`.

The bundle preserves 12 committed source snapshots, both V audit helpers,
74 selected input hashes (including SDK gesture declarations), generated C,
host objects/app, compiled drivers and ARM64 binaries, commands/statuses, and
complete boot media, initramfs, firmware variables, Limine configurations and
serial logs for both VMs. All 72 files other than the manifest are checksummed.
Local Fortnite assets remain in external storage. Compiler, header and
host-library closures are not independently sealed; rebuilding requires the
prepared checkout dependencies. Historical checkers are unchanged.

Compression integrity and original-bundle selftest pass. A fresh extraction at
`/Users/alex/Library/Caches/vinix-ios/rotation-gesture-restored-20261025/rotation-gesture-20261025`
also passes full checksums, rejection of missing guest media, an altered host
log and an unmanifested file, restoration of each mutation, and final checking.

Reproduce using the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`, `V_RESOURCE_PATH` set to that toolchain and
`V_MACOS_V3_NO_FALLBACK=1`. Build `tests/ios/notification-checks.v`,
`notification-vm.v`, `native-checks.v`, `rotation-gesture-input-inventory.v` and
`rotation-gesture-evidence.v`. Invoke the notification-checks driver with a fresh
external directory and modes `driver-build`, `rotation-gesture-host`,
`build-rotation-gesture`, `build-init`, `build-run-ios-gles`, `rotation-gesture`,
`probe`. Run `driver-build` before the other modes to initialize its directories.
Fixture generation preserves assertions. Invoke the inventory helper with
repository root, bundle directory and tested revision; copy both audit helpers
into the bundle as `inventory-inputs.v` and `rotation-gesture-evidence.v`. Use
checker modes `seal DIR`, `selftest DIR` and `hash FILE` to seal, audit and hash it.
