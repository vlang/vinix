# Fortnite GameKit achievement checkpoint — 2026-10-25

Runtime and test revision: `b678b620dc7adaff52f28af3f4d46bf7e57b10e3`.
Advertising work remains skipped.

The GameKit shim now resolves scoped `GKAchievement` class/metaclass imports
and supports local identifier, progress, completion, creation-date and banner
state. The opaque 40-byte object inherits from NSObject. Progress defaults to
zero, completion is `percentComplete >= 100`, and the banner defaults to true.
Double values remain unbounded, including NaN and infinities. Identifier
assignment retains mutable string identity; nil is allowed. Changing progress
preserves the creation date. Reinitialization replaces the identifier/date and
resets progress/banner defaults. Reporting, loading, resetting, players,
hidden state, copying, coding and observation remain unsupported and fail
explicitly. There is no Game Center backend.

The native ARM64 Mac Catalyst inspector passes size, inheritance, defaults,
mutable identifier ownership, floating-point boundaries, BOOL truncation,
creation-date identity and reinitialization checks. Native identifier/progress/
date accessors are absent from `class_getInstanceMethod`; synthetic shim
methods model their `NSMethodSignature` ABI, not native method-list parity.
Identifier retention follows measured behavior despite the SDK's copy
annotation. Native iOS was not measured.

Assertion-enabled shim fixtures pass ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Coverage includes scoped imports, signatures,
floating ABI, saved IMPs, constructor rollback and unlocked callbacks, four
workers performing 128 iterations each, two drained runtimes and 41 isolated
rejection cases. Object counters balance and runtime object/block maps drain.
ASan leak detection was disabled; these checks do not establish absence of all
heap leaks. The broader native regression suite was not rerun.

Drivers, the ARM64 fixture, initializer and GLES runner build successfully.
The focused Vinix ARM64 QEMU fixture passes with child status 0. A fresh full
Fortnite import audit reports **2982 resolved, 22 unresolved strong and 114
unresolved weak imports**, reducing the preceding strong-import count from
23 to 22. Per image, the main executable reports 2139/22/78, EOSSDK 664/0/16
and MarketplaceKitWrapper 179/0/20 (resolved/strong/weak). The audit does not
execute application code. A separate normal launch probe still stops at:

```text
iOS: linking /opt/ios/FortniteClient-IOS-Shipping: iOS: library is not implemented: /System/Library/Frameworks/StoreKit.framework/StoreKit (_OBJC_CLASS_$_SKAdNetwork)
```

Both Fortnite runs exit 1 during linking, before application entry; their
wrappers exit 0 after capturing that failure. Rendering, login and gameplay
remain unverified. SKAdNetwork work remains skipped as requested.

Archive: `/Users/alex/Library/Caches/vinix-ios/gk-achievement-20261025.tar.zst`.
Archive SHA-256: `b246ac9913f2df0a7d56ae4de69a2317591bb79e24295e3e9367bfc0dd4d3da7`.
Contained manifest SHA-256: `13cfcf474a0815e4ad54ed403768bbcce7bf1894e50270a2e282ce7d571e5f45`.

The complete bundle preserves 17 committed source snapshots, both V audit
helpers, 73 selected build input hashes, generated C, host objects/app,
compiled drivers and ARM64 binaries, commands/statuses, and complete boot
media, initramfs, firmware variables, Limine configurations and serial logs
for all three VMs. All 90 files other than the manifest are checksummed.
Local Fortnite assets remain in external storage. Compiler, header and host
library closures are not independently sealed; rebuilding requires the
prepared checkout dependencies. The prebuilt guest kernel is inventoried;
concurrent kernel edits were not rebuilt. Historical checkers are unchanged.

Compression integrity and original-bundle checks/selftest pass. A fresh
extraction at
`/Users/alex/Library/Caches/vinix-ios/gk-achievement-restored-20261025/gk-achievement-20261025`
also passes full checksums, rejection of missing guest media, an altered host
log and an unmanifested file, restoration of each mutation, and final checking.
The original and restored manifest hashes match.

Reproduce using the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`, `V_RESOURCE_PATH` set to that toolchain
and `V_MACOS_V3_NO_FALLBACK=1`. Build `tests/ios/notification-checks.v`,
`notification-vm.v`, `native-checks.v`, `gk-achievement-input-inventory.v`
and `gk-achievement-evidence.v`. Invoke the notification-checks driver
with a fresh external directory and modes `driver-build`,
`gk-achievement-inspector-build`, `gk-achievement-inspect`,
`gk-achievement-host`, `build-gk-achievement`, `build-init`,
`build-run-ios-gles`, `gk-achievement`, `probe`, `audit`. Run `driver-build`
first to initialize its directories. Fixture generation preserves assertions.
Invoke the inventory helper with repository root, bundle directory and tested
revision; copy both audit helpers into the bundle as `inventory-inputs.v` and
`gk-achievement-evidence.v`. Use checker modes `seal DIR`, `check DIR`,
`selftest DIR` and `hash FILE` to seal, audit and hash it.
