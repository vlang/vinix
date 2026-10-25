# Fortnite haptic event checkpoint — 2026-10-25

Runtime and test revision: `f8d42cbb0a6bfd16c69c26b26108d58df982c8af`.
Advertising work remains skipped.

CoreHaptics now resolves scoped `CHHapticEvent` class/metaclass imports.
The four event/audio-resource constructors, retained event types, copied
parameter arrays and mutable timing values match the local ARM64 CoreHaptics
inspection. Instances occupy 48 bytes: `_type` at offset 8, `_audioResID` at 16,
`_eventParams` at 24, `_time` at 32 and `_duration` at 40. Parameter snapshots
retain their elements; reinitialization safely accepts the event's existing
type and snapshot. Timing preserves exact double bits, including signed zero,
infinities and a NaN payload. Reflection exposes 11 supported selectors with
native encodings. Unsupported construction, copying, coding, caller storage,
saved NSObject IMP calls and incompatible isa changes fail explicitly.
This implements event storage; haptic/audio playback remains unimplemented.

A fresh Vinix ARM64 QEMU Fortnite probe passes the event import and stops at:

```text
iOS: linking /opt/ios/FortniteClient-IOS-Shipping: iOS: library is not implemented: /System/Library/Frameworks/CoreHaptics.framework/CoreHaptics (_OBJC_CLASS_$_CHHapticPattern)
```

The runner exits 1 during linking, before application entry. The probe wrapper
exits 0 because it captured that failure. Fortnite has not started successfully;
rendering, login and gameplay remain unverified.

The native inspector and assertion-enabled host fixtures pass. Host fixtures
run with ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. The focused ARM64 QEMU fixture passes with child
status 0: scoped imports, native metadata, all four constructors, ownership and
reinitialization, seven double bit patterns, two drained runtimes and 14 explicit
fatal rejection cases. Runtime object counters balance. ASan leak detection
was disabled; this does not establish absence of all heap leaks. The drivers,
ARM64 fixture, initializer and GLES runner build successfully. The broader
native regression suite and import audits were not rerun.

Archive: `/Users/alex/Library/Caches/vinix-ios/haptic-event-startup-20261025.tar.zst`.
Archive SHA-256: `214ce89af2757b8ececd68d221dfc1941d7bcd53b7d1bb47151ffc1679f69714`.
Contained manifest SHA-256: `03207762617aa816247a92718c6b7b5c98fbe4e3d857cdae1cfc6376f0255d0d`.

The bundle preserves 14 committed source snapshots, both V audit helpers,
73 selected input hashes (including the SDK event declarations), generated C,
host objects/app, compiled drivers and ARM64 binaries, commands/statuses, and
complete boot media, initramfs, firmware variables, Limine configurations and
serial logs for both VMs. All 79 files other than the manifest are checksummed.
Local Fortnite assets remain in external storage. Compiler, header and
host-library closures are not independently sealed; rebuilding requires the
prepared checkout dependencies. Historical checkers are unchanged.

Compression integrity and original-bundle selftest pass. A fresh extraction at
`/Users/alex/Library/Caches/vinix-ios/haptic-event-restored-20261025/haptic-event-20261025`
also passes full checksums, rejection of missing guest media, an altered host
log and an unmanifested file, restoration of each mutation, and final checking.
The original and restored manifest hashes match.

Reproduce using the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`, `V_RESOURCE_PATH` set to that toolchain and
`V_MACOS_V3_NO_FALLBACK=1`. Build `tests/ios/notification-checks.v`,
`notification-vm.v`, `native-checks.v`, `haptic-event-input-inventory.v` and
`haptic-event-evidence.v`. Invoke the notification-checks driver with a fresh
external directory and modes `driver-build`, `haptic-event-inspector-build`,
`haptic-event-inspect`, `haptic-event-host`, `build-haptic-event`, `build-init`,
`build-run-ios-gles`, `haptic-event`, `probe`. Run `driver-build` first to
initialize its directories. Inspector and fixture generation preserve
assertions. Invoke the inventory helper with repository root, bundle directory
and tested revision; copy both audit helpers into the bundle as
`inventory-inputs.v` and `haptic-event-evidence.v`. Use checker modes `seal DIR`,
`selftest DIR` and `hash FILE` to seal, audit and hash it.
