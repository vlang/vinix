# Fortnite haptic event parameter checkpoint — 2026-10-25

Runtime and test revision: `a00cfe669fe9050dffc25bb8f748ac790e397ed8`.
Advertising work remains skipped.

CoreHaptics now resolves scoped `CHHapticEventParameter` class/metaclass imports.
Parameter construction, retained identifiers and mutable float values match
the local ARM64 CoreHaptics inspection: 24-byte instances, `_value` at offset 8,
`_param` at offset 16, identifier retention without copying, nil identifiers,
and exact float bits, including signed zero, infinities and a NaN payload.
Method reflection exposes the four supported parameter selectors with native
encodings. Subclass/metaclass construction, caller storage, unsupported
initialization/copy/coding methods, saved NSObject IMP calls and incompatible
isa changes fail explicitly. This implements parameter storage; haptic
playback remains unimplemented.

A fresh Vinix ARM64 QEMU Fortnite probe passes the parameter import and stops at:

```text
iOS: linking /opt/ios/FortniteClient-IOS-Shipping: iOS: library is not implemented: /System/Library/Frameworks/CoreHaptics.framework/CoreHaptics (_OBJC_CLASS_$_CHHapticEvent)
```

The runner exits 1 during linking, before application entry. The probe wrapper
exits 0 because it captured that failure. Fortnite has not started successfully;
rendering, login and gameplay remain unverified.

The native inspector and assertion-enabled host fixtures pass. Host fixtures
run with ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. The focused ARM64 QEMU fixture passes with child
status 0: scoped imports, native metadata, retained/mutable/replaced identifiers,
exact float values, two drained runtimes and 14 explicit fatal rejection cases.
Runtime object counters balance. ASan leak detection was disabled; this does
not establish absence of all heap leaks. The drivers, ARM64 fixture, initializer
and GLES runner build successfully. The broader native regression suite and
import audits were not rerun.

Archive: `/Users/alex/Library/Caches/vinix-ios/haptic-event-parameter-startup-20261025.tar.zst`.
Archive SHA-256: `94c6e0c5e89b9ffa229c49198e3773203375dbf5c366fc952148d85edb0dcb85`.
Contained manifest SHA-256: `b1e432a94ad7f60393b064d45d2da195d0349229aa38c07aa1c9cff3e76d8e5c`.

The bundle preserves 13 committed source snapshots, both V audit helpers,
73 selected input hashes (including the SDK parameter declarations), generated
C, host objects/app, compiled drivers and ARM64 binaries, commands/statuses,
and complete boot media, initramfs, firmware variables, Limine configurations
and serial logs for both VMs. All 78 files other than the manifest are
checksummed. Local Fortnite assets remain in external storage. Compiler,
header and host-library closures are not independently sealed; rebuilding
requires the prepared checkout dependencies. Historical checkers are unchanged.

Compression integrity and original-bundle selftest pass. A fresh extraction at
`/Users/alex/Library/Caches/vinix-ios/haptic-event-parameter-restored-20261025/haptic-event-parameter-20261025`
also passes full checksums, rejection of missing guest media, an altered host
log and an unmanifested file, restoration of each mutation, and final checking.
The original and restored manifest hashes match.

Reproduce using the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`, `V_RESOURCE_PATH` set to that toolchain and
`V_MACOS_V3_NO_FALLBACK=1`. Build `tests/ios/notification-checks.v`,
`notification-vm.v`, `native-checks.v`, `haptic-event-parameter-input-inventory.v`
and `haptic-event-parameter-evidence.v`. Invoke the notification-checks driver
with a fresh external directory and modes `driver-build`,
`haptic-event-parameter-inspector-build`, `haptic-event-parameter-inspect`,
`haptic-event-parameter-host`, `build-haptic-event-parameter`, `build-init`,
`build-run-ios-gles`, `haptic-event-parameter`, `probe`. Run `driver-build` first
to initialize its directories. Inspector and fixture generation preserve
assertions. Invoke the inventory helper with repository root, bundle directory
and tested revision; copy both audit helpers into the bundle as
`inventory-inputs.v` and `haptic-event-parameter-evidence.v`. Use checker modes
`seal DIR`, `selftest DIR` and `hash FILE` to seal, audit and hash it.
