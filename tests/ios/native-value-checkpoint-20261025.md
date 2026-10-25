# Fortnite native Swift object checkpoint — 2026-10-25

Runtime and test revision: `88fecc8953916e972318531f77cad76bca3e6963`.
Advertising work remains skipped.

The Swift shim now resolves `_$sBoWV`, the `Builtin.NativeObject` value
witness table. Its eight slots use native Swift ownership operations, with
assignment publishing the replacement before releasing the previous owner
so a destructor can inspect or copy it. The native, unknown and bridge object
tables share a read-only arena and measured enum encoding. Native object
metadata imports `_$sBoN` and `_$sBON` remain unresolved.

The assertion-enabled ARM64 host fixture passes against both the installed
Apple Swift implementation and the shim. ASan+UBSan runs at `-O0 -g` pass
normally and with `SWIFT_DETERMINISTIC_HASHING=1`. The unknown and bridge
object witness host regressions pass in both configurations. Coverage includes
all eight slots and table layout, native ownership, nil and immortal values,
self assignments, aliased ownership, unchanged moved bytes, guarded unaligned
eight/nine-byte enum boundaries, ARM64 return/register behavior, destructor
reentry, eight concurrent publishers/workers, and two drained runtimes with
sealed tables unmapped at shutdown. Runtime heap and object counters balance;
ASan leak detection was disabled, so these results do not establish absence
of all heap leaks. The broader native regression suite was not rerun.

Drivers, the ARM64 fixture, initializer and GLES runner build successfully.
The focused Vinix ARM64 QEMU fixture passes with child status 0. A fresh full
Fortnite import audit reports **2979 resolved, 25 unresolved strong and 114
unresolved weak imports**, reducing the preceding strong-import count from
26 to 25. Per image, the main executable reports 2136/25/78, EOSSDK 664/0/16
and MarketplaceKitWrapper 179/0/20 (resolved/strong/weak). The audit does not
execute application code. A separate normal launch probe still stops at:

```text
iOS: linking /opt/ios/FortniteClient-IOS-Shipping: iOS: library is not implemented: /System/Library/Frameworks/StoreKit.framework/StoreKit (_OBJC_CLASS_$_SKAdNetwork)
```

Both Fortnite runs exit 1 during linking, before application entry; their
wrappers exit 0 after capturing that failure. Rendering, login and gameplay
remain unverified. SKAdNetwork work remains skipped as requested.

Archive: `/Users/alex/Library/Caches/vinix-ios/native-value-20261025.tar.zst`.
Archive SHA-256: `84602953a4df998acafcab6bc41b476f0e123be1ea990bf95c5df442a06505b9`.
Contained manifest SHA-256: `a3ec21a3ed58fdc856c206de0c9a85902e445c8d8ed6f68ae86b14129cfd197c`.

The complete bundle preserves 17 committed source snapshots, both V audit
helpers, 72 selected build input hashes, generated C, host objects/apps,
compiled drivers and ARM64 binaries, commands/statuses, both host regression
bundles, and complete boot media, initramfs, firmware variables, Limine
configurations and serial logs for all three VMs. All 131 files other than
the manifest are checksummed. Local Fortnite assets remain in external
storage. Compiler, header and host library closures are not independently
sealed; rebuilding requires the prepared checkout dependencies. Historical
checkers are unchanged.

Compression integrity and original-bundle checks/selftest pass. A fresh
extraction at
`/Users/alex/Library/Caches/vinix-ios/native-value-restored-20261025/native-value-20261025`
also passes full checksums, rejection of missing guest media, an altered host
log and an unmanifested file, restoration of each mutation, and final checking.
The original and restored manifest hashes match.

Reproduce using the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`, `V_RESOURCE_PATH` set to that toolchain
and `V_MACOS_V3_NO_FALLBACK=1`. Build `tests/ios/notification-checks.v`,
`notification-vm.v`, `native-checks.v`, `native-value-input-inventory.v` and
`native-value-evidence.v`. Invoke the notification-checks driver with a fresh
external directory and modes `driver-build`, `native-value-host`,
`build-native-value`, `build-init`, `build-run-ios-gles`, `native-value`,
`probe`, `audit`. Run `driver-build` first to initialize its directories.
Run `unknown-value-host` and `bridge-value-host` with separate output
directories `regression-unknown` and `regression-bridge` beneath the bundle.
Fixture generation preserves assertions. Invoke the inventory helper with
repository root, bundle directory and tested revision; copy both audit
helpers into the bundle as `inventory-inputs.v` and `native-value-evidence.v`.
Use checker modes `seal DIR`, `check DIR`, `selftest DIR` and `hash FILE`
to seal, audit and hash it.
