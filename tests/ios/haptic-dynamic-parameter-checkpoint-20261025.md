# Fortnite haptic dynamic parameter checkpoint — 2026-10-25

Runtime and test revision: `aa40170881b63ed8e13e88f20c5bc4cb05ad162d`.
Advertising work remains skipped.

CoreHaptics now resolves scoped `CHHapticDynamicParameter` class/metaclass
imports. Its constructor retains the parameter identifier, including mutable
identifiers, and accepts nil. Reinitialization safely replaces or reuses that
identifier. Float values and double relative times preserve their exact bits
through independent ARM64 argument registers, storage, getters and setters.
Instances occupy 32 bytes with three measured ivars; reflection exposes six
selectors with native encodings. These behaviors match local ARM64 CoreHaptics
inspection. Unsupported initialization, copying, coding, subclass storage,
caller storage and incompatible isa changes fail explicitly. This implements
parameter storage; haptic/audio playback remains unimplemented.

A fresh Vinix ARM64 QEMU Fortnite probe passes the dynamic parameter import and
stops at:

```text
iOS: linking /opt/ios/FortniteClient-IOS-Shipping: iOS: framework symbol is not implemented: _OBJC_CLASS_$_UITextField
```

The runner exits 1 during linking, before application entry. The probe wrapper
exits 0 because it captured that failure. Rendering, login and gameplay remain
unverified.

The native inspector and assertion-enabled host fixtures pass. Host fixtures
run with ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. The focused ARM64 QEMU fixture passes with child
status 0: scoped imports, metadata, retained identifier identity and lifetime,
mutation, reinitialization, nil, seven float and seven double IEEE patterns
through constructors and setters, independent field preservation, two drained
runtimes and 16 explicit fatal rejection cases. Runtime object counters balance.
ASan leak detection was disabled; this does not establish absence of all heap
leaks. The drivers, ARM64 fixture, initializer and GLES runner build successfully.
The broader native regression suite and import audits were not rerun.

Archive: `/Users/alex/Library/Caches/vinix-ios/haptic-dynamic-parameter-startup-20261025.tar.zst`.
Archive SHA-256: `803547241154d5788f7b73c5b7054951758f2c9048c7a9b38e2cc241ea5e7dc8`.
Contained manifest SHA-256: `fee048cbce9ac0cc7cd85f7669fff216b0ec9da59781eed55ee21ff9ee4096ef`.

The bundle preserves 16 committed source snapshots, both V audit helpers,
73 selected input hashes (including the SDK parameter declaration), generated
C, host objects/app, compiled drivers and ARM64 binaries, commands/statuses,
and complete boot media, initramfs, firmware variables, Limine configurations
and serial logs for both VMs. All 81 files other than the manifest are
checksummed. Local Fortnite assets remain in external storage. Compiler,
header and host-library closures are not independently sealed; rebuilding
requires the prepared checkout dependencies. Historical checkers are unchanged.

Compression integrity and original-bundle selftest pass. A fresh extraction at
`/Users/alex/Library/Caches/vinix-ios/haptic-dynamic-parameter-restored-20261025/haptic-dynamic-parameter-20261025`
also passes full checksums, rejection of missing guest media, an altered host
log and an unmanifested file, restoration of each mutation, and final checking.
The original and restored manifest hashes match.

Reproduce using the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`, `V_RESOURCE_PATH` set to that toolchain and
`V_MACOS_V3_NO_FALLBACK=1`. Build `tests/ios/notification-checks.v`,
`notification-vm.v`, `native-checks.v`,
`haptic-dynamic-parameter-input-inventory.v` and
`haptic-dynamic-parameter-evidence.v`. Invoke the notification-checks driver
with a fresh external directory and modes `driver-build`,
`haptic-dynamic-parameter-inspector-build`, `haptic-dynamic-parameter-inspect`,
`haptic-dynamic-parameter-host`, `build-haptic-dynamic-parameter`, `build-init`,
`build-run-ios-gles`, `haptic-dynamic-parameter`, `probe`. Run `driver-build`
first to initialize its directories. Inspector and fixture generation preserve
assertions. Invoke the inventory helper with repository root, bundle directory
and tested revision; copy both audit helpers into the bundle as
`inventory-inputs.v` and `haptic-dynamic-parameter-evidence.v`. Use checker modes
`seal DIR`, `selftest DIR` and `hash FILE` to seal, audit and hash it.
