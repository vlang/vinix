# Fortnite UITextField checkpoint — 2026-10-25

Runtime and test revision: `374cf46953b93ec4cba012c319e79d9fe10a6af5`.
Advertising work remains skipped.

UIKit now resolves scoped `UITextField` class/metaclass imports with `UIControl`
as the parent. The profile implements `init`, `initWithFrame:`, copied text and
placeholder strings, a zeroing weak delegate, eight integer configuration
properties, three Boolean flags and an always-false editing state. Mutable
strings are snapshotted; nil text becomes an empty string and nil placeholder
stays nil. Metadata, defaults, CGRect argument dispatch and BOOL encodings match
local ARM64 Catalyst UIKit inspection. The measured 1064-byte instance size is
an opaque reserve; this does not establish the layout of device iOS UIKit.
Private shim state supports subclasses, super calls and saved implementations.
Frames must be finite, within the profile's 8192-unit bounds and have nonnegative
sizes; strings must be validated live UTF-8 strings of at most 65536 bytes.
Uninitialized/reinitialized objects, caller storage, incompatible or forged isa,
copying, coding and unsupported editing APIs fail explicitly. Text editing,
input, drawing and delegate callbacks remain unimplemented.

A fresh Vinix ARM64 QEMU Fortnite probe passes the UITextField import and stops
at the advertising import:

```text
iOS: linking /opt/ios/FortniteClient-IOS-Shipping: iOS: library is not implemented: /System/Library/Frameworks/StoreKit.framework/StoreKit (_OBJC_CLASS_$_SKAdNetwork)
```

The runner exits 1 during linking, before application entry. The probe wrapper
exits 0 because it captured that failure. SKAdNetwork implementation remains
skipped as requested. Rendering, login and gameplay remain unverified.

The native inspector and assertion-enabled host fixtures pass. Host fixtures
run with ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. The focused ARM64 QEMU fixture passes with child
status 0: scoped imports, metadata/defaults, CGRect and BOOL dispatch, copied
UTF-8 strings, nil handling, weak delegate lifetime, subclasses/saved
implementations, two drained runtimes and 19 explicit fatal rejection cases.
Runtime object counters balance. ASan leak detection was disabled; this does
not establish absence of all heap leaks. The drivers, ARM64 fixture,
initializer and GLES runner build successfully. The broader native regression
suite and import audits were not rerun.

Archive: `/Users/alex/Library/Caches/vinix-ios/ui-text-field-startup-20261025.tar.zst`.
Archive SHA-256: `f3f821707d3a90d8b5a06083fb73e224cc034d86258dff7f6eab4741ec2f067a`.
Contained manifest SHA-256: `02404507077f2c4d66fe1aa2a0a29cabe021706341043ebb2d56c9fc5231292d`.

The bundle preserves 15 committed source snapshots, both V audit helpers,
74 selected input hashes (including the SDK UITextField and UITextInputTraits
declarations), generated C, host objects/app, compiled drivers and ARM64
binaries, commands/statuses, and complete boot media, initramfs, firmware
variables, Limine configurations and serial logs for both VMs. All 80 files
other than the manifest are checksummed. Local Fortnite assets remain in
external storage. Compiler, header and host-library closures are not
independently sealed; rebuilding requires the prepared checkout dependencies.
Historical checkers are unchanged.

Compression integrity and original-bundle selftest pass. A fresh extraction at
`/Users/alex/Library/Caches/vinix-ios/ui-text-field-restored-20261025/ui-text-field-20261025`
also passes full checksums, rejection of missing guest media, an altered host
log and an unmanifested file, restoration of each mutation, and final checking.
The original and restored manifest hashes match.

Reproduce using the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`, `V_RESOURCE_PATH` set to that toolchain and
`V_MACOS_V3_NO_FALLBACK=1`. Build `tests/ios/notification-checks.v`,
`notification-vm.v`, `native-checks.v`, `text-field-input-inventory.v` and
`text-field-evidence.v`. Invoke the notification-checks driver with a fresh
external directory and modes `driver-build`, `text-field-inspector-build`,
`text-field-inspect`, `text-field-host`, `build-text-field`, `build-init`,
`build-run-ios-gles`, `text-field`, `probe`. Run `driver-build` first to
initialize its directories. Inspector and fixture generation preserve
assertions. Invoke the inventory helper with repository root, bundle directory
and tested revision; copy both audit helpers into the bundle as
`inventory-inputs.v` and `text-field-evidence.v`. Use checker modes `seal DIR`,
`selftest DIR` and `hash FILE` to seal, audit and hash it.
