# Fortnite capture discovery checkpoint — 2026-10-25

Runtime and test revision: `4e53d1ea0945cc91de1a1a29a0f6ae1b269eb7e1`.
Advertising work remains skipped.

AVFoundation now resolves scoped `AVCaptureDeviceDiscoverySession` class and
metaclass imports. Its discovery factory validates an NSArray of NSString
device types, an optional NSString media type and positions 0 through 2.
There is no capture hardware backend: `devices` and
`supportedMultiCamDeviceSets` return immutable empty arrays. Criteria are
inspected synchronously and are never retained or borrowed afterward.
Reflection and saved implementations use the native method encodings.

Local ARM64 Catalyst inspection confirms the NSObject parent, 48-byte instance,
factory and getter encodings, and empty results for empty criteria. This does
not establish device iOS instance layout. Factory-only storage is a shim
restriction. Construction, copying, coding, caller storage, subclasses, isa
changes, invalid criteria, damaged or retired storage, result mutation and
observation fail explicitly.

The native inspector and assertion-enabled host fixture pass. Host fixtures
run with ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. The focused Vinix ARM64 QEMU fixture passes
with child status 0, covering scoped imports, criteria validation, immutable
results, typed reflection, saved implementations, four concurrent workers,
two drained runtimes and 33 fatal rejection cases. Runtime object counters
balance. ASan leak detection was disabled; this does not establish absence of
all heap leaks. Drivers, the ARM64 fixture, initializer and GLES runner build
successfully. The broader native regression suite was not rerun.

A fresh full Fortnite import audit reports 2978 resolved imports, 26 unresolved
strong imports and 114 unresolved weak imports. Capture discovery now resolves,
reducing the previous measured strong-import count from 27 to 26. Per image,
the main executable reports 2135/26/78, EOSSDK 664/0/16 and
MarketplaceKitWrapper 179/0/20 (resolved/strong/weak). The audit does not
execute application code. A separate normal launch probe still stops at:

```text
iOS: linking /opt/ios/FortniteClient-IOS-Shipping: iOS: library is not implemented: /System/Library/Frameworks/StoreKit.framework/StoreKit (_OBJC_CLASS_$_SKAdNetwork)
```

Both Fortnite runs exit 1 during linking, before application entry; their
wrappers exit 0 after capturing that failure. Rendering, login and gameplay
remain unverified. SKAdNetwork work remains skipped as requested.

Archive: `/Users/alex/Library/Caches/vinix-ios/capture-discovery-20261025.tar.zst`.
Archive SHA-256: `20739c26e5bfc34947cbdc8821bb335d0c9020d757b3820bdcec7df1b2b4f086`.
Contained manifest SHA-256: `08cd3fb0ac7c8110406ad92def9f5759e09f26cc24d71771df2b1259cf5ccf58`.

The complete bundle preserves 16 committed source snapshots, both V audit
helpers, 73 selected build input hashes, generated C, host objects/app,
compiled drivers and ARM64 binaries, commands/statuses, and complete boot
media, initramfs, firmware variables, Limine configurations and serial logs
for all three VMs. All 89 files other than the manifest are checksummed.
Local Fortnite assets remain in external storage. Compiler, header and host
library closures are not independently sealed; rebuilding requires the
prepared checkout dependencies. Historical checkers are unchanged.

Compression integrity and original-bundle selftest pass. A fresh extraction at
`/Users/alex/Library/Caches/vinix-ios/capture-discovery-restored-20261025/capture-discovery-20261025`
also passes full checksums, rejection of missing guest media, an altered host
log and an unmanifested file, restoration of each mutation, and final checking.
The original and restored manifest hashes match.

Reproduce using the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`, `V_RESOURCE_PATH` set to that toolchain and
`V_MACOS_V3_NO_FALLBACK=1`. Build `tests/ios/notification-checks.v`,
`notification-vm.v`, `native-checks.v`, `capture-discovery-input-inventory.v`
and `capture-discovery-evidence.v`. Invoke the notification-checks driver with
a fresh external directory and modes `driver-build`,
`capture-discovery-inspector-build`, `capture-discovery-inspect`,
`capture-discovery-host`, `build-capture-discovery`, `build-init`,
`build-run-ios-gles`, `capture-discovery`, `probe`, `audit`. Run `driver-build`
first to initialize its directories. Inspector and fixture generation preserve
assertions. Invoke the inventory helper with repository root, bundle directory
and tested revision; copy both audit helpers into the bundle as
`inventory-inputs.v` and `capture-discovery-evidence.v`. Use checker modes
`seal DIR`, `selftest DIR` and `hash FILE` to seal, audit and hash it.
