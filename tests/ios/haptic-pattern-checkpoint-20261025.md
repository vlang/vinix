# Fortnite haptic pattern checkpoint — 2026-10-25

Runtime and test revision: `bbfcae2288f09f946232a9cbdc9400f56a63bbcf`.
Advertising work remains skipped.

CoreHaptics now resolves scoped `CHHapticPattern` class/metaclass imports.
Two event-array constructors, copied array storage, retained event objects,
immutable getter snapshots and dynamically computed duration match the local
ARM64 CoreHaptics inspection. Instances occupy 72 bytes with eight measured
ivars; reflection exposes nine selectors with native encodings, including the
float `version` and double `duration` getters. Reinitialization preserves the
inactive parameter/curve array and safely accepts existing backing storage or
snapshots. Only nil/empty parameter and curve arrays are supported. Nonempty
lists, dictionary/URL construction, export, copying, coding, subclass storage,
caller storage and incompatible isa changes fail explicitly. This implements
pattern storage; haptic/audio playback remains unimplemented.

A fresh Vinix ARM64 QEMU Fortnite probe passes the pattern import and stops at:

```text
iOS: linking /opt/ios/FortniteClient-IOS-Shipping: iOS: library is not implemented: /System/Library/Frameworks/CoreHaptics.framework/CoreHaptics (_OBJC_CLASS_$_CHHapticDynamicParameter)
```

The runner exits 1 during linking, before application entry. The probe wrapper
exits 0 because it captured that failure. Rendering, login and gameplay remain
unverified.

The native inspector and assertion-enabled host fixtures pass. Host fixtures
run with ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. The focused ARM64 QEMU fixture passes with child
status 0: scoped imports, metadata, both constructors, copied arrays, retained
events, ownership and reinitialization, changing/overlapping event durations,
seven IEEE timing patterns, nine time/duration combinations, two drained
runtimes and 22 explicit fatal rejection cases. Runtime object counters balance.
ASan leak detection was disabled; this does not establish absence of all heap
leaks. The drivers, ARM64 fixture, initializer and GLES runner build successfully.
The broader native regression suite and import audits were not rerun.

Archive: `/Users/alex/Library/Caches/vinix-ios/haptic-pattern-startup-20261025.tar.zst`.
Archive SHA-256: `45927d7f8f8866c25cb06dc0380cff807d156334093a2a7cb64fd61dd402686f`.
Contained manifest SHA-256: `c5ef6e132c877e9d9128810beea937a14c6239e92238725e0ec68ca60c792a04`.

The bundle preserves 15 committed source snapshots, both V audit helpers,
74 selected input hashes (including the SDK event and pattern declarations),
generated C, host objects/app, compiled drivers and ARM64 binaries,
commands/statuses, and complete boot media, initramfs, firmware variables,
Limine configurations and serial logs for both VMs. All 80 files other than the
manifest are checksummed. Local Fortnite assets remain in external storage.
Compiler, header and host-library closures are not independently sealed;
rebuilding requires the prepared checkout dependencies. Historical checkers
are unchanged.

Compression integrity and original-bundle selftest pass. A fresh extraction at
`/Users/alex/Library/Caches/vinix-ios/haptic-pattern-restored-20261025/haptic-pattern-20261025`
also passes full checksums, rejection of missing guest media, an altered host
log and an unmanifested file, restoration of each mutation, and final checking.
The original and restored manifest hashes match.

Reproduce using the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`, `V_RESOURCE_PATH` set to that toolchain and
`V_MACOS_V3_NO_FALLBACK=1`. Build `tests/ios/notification-checks.v`,
`notification-vm.v`, `native-checks.v`, `haptic-pattern-input-inventory.v` and
`haptic-pattern-evidence.v`. Invoke the notification-checks driver with a fresh
external directory and modes `driver-build`, `haptic-pattern-inspector-build`,
`haptic-pattern-inspect`, `haptic-pattern-host`, `build-haptic-pattern`,
`build-init`, `build-run-ios-gles`, `haptic-pattern`, `probe`. Run `driver-build`
first to initialize its directories. Inspector and fixture generation preserve
assertions. Invoke the inventory helper with repository root, bundle directory
and tested revision; copy both audit helpers into the bundle as
`inventory-inputs.v` and `haptic-pattern-evidence.v`. Use checker modes `seal DIR`,
`selftest DIR` and `hash FILE` to seal, audit and hash it.
