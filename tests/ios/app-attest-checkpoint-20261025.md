# Fortnite App Attest checkpoint — 2026-10-25

Runtime and test revision: `3bd7e122458422db25edec4af4319b3e0c8dfa25`.
Advertising work remains skipped.

DeviceCheck now resolves scoped `DCAppAttestService` class and metaclass
imports. `sharedService` returns a factory-owned singleton and `isSupported`
returns NO. There is no attestation provider: key generation, attestation and
assertions remain unimplemented and fail explicitly. Reflection advertises
only the implemented availability methods with their native encodings.

Local ARM64 Catalyst inspection confirms the NSObject parent, 16-byte instance,
singleton identity, unavailable state and method encodings. This does not
establish device iOS instance layout. Factory-only storage is a shim restriction,
not a native allocation contract. Construction, copying, coding, caller storage,
subclasses, isa changes, cached-object destruction and access after retirement
fail explicitly. Runtime teardown releases its factory-owned reference.

The native inspector and assertion-enabled host fixture pass. Host fixtures
run with ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. The focused Vinix ARM64 QEMU fixture passes
with child status 0, covering scoped imports, concurrent singleton creation,
typed reflection, saved implementations, four concurrent readers, two drained
runtimes and 26 fatal rejection cases. Runtime object counters balance. ASan
leak detection was disabled; this does not establish absence of all heap leaks.
Drivers, the ARM64 fixture, initializer and GLES runner build successfully.
The broader native regression suite was not rerun.

A fresh full Fortnite import audit reports 2977 resolved imports, 27 unresolved
strong imports and 114 unresolved weak imports. The App Attest class import
now resolves, reducing the previous measured strong-import count from 28 to 27.
The audit does not execute application code. A separate normal launch probe
still stops at:

```text
iOS: linking /opt/ios/FortniteClient-IOS-Shipping: iOS: library is not implemented: /System/Library/Frameworks/StoreKit.framework/StoreKit (_OBJC_CLASS_$_SKAdNetwork)
```

Both Fortnite runs exit 1 during linking, before application entry; their
wrappers exit 0 after capturing that failure. Rendering, login and gameplay
remain unverified. SKAdNetwork work remains skipped as requested.

Archive: `/Users/alex/Library/Caches/vinix-ios/app-attest-20261025.tar.zst`.
Archive SHA-256: `81d744e8c4708ff38ad8392345db3587fe3d2f1cfa723df55c9035f616d4a4d6`.
Contained manifest SHA-256: `10185dd6013f0280062751bcd6310532938b58a7cd5c8d20e62ac2a5927cc7c2`.

The complete bundle preserves 16 committed source snapshots, both V audit
helpers, 73 selected build input hashes, generated C, host objects/app,
compiled drivers and ARM64 binaries, commands/statuses, and complete boot
media, initramfs, firmware variables, Limine configurations and serial logs
for all three VMs. All 92 files other than the manifest are checksummed.
The first audit attempt exhausted disk space during staging, before boot;
its log, status and state pointer are preserved as `audit-first-no-space.*`.
After freeing a verified unpacked duplicate of the previous checkpoint, the
audit retry passed. Local Fortnite assets remain in external storage.
Compiler, header and host library closures are not independently sealed;
rebuilding requires the prepared checkout dependencies. Historical checkers
are unchanged.

Compression integrity and original-bundle selftest pass. The verified archive
replaces the original unpacked copy to conserve disk space. A fresh extraction at
`/Users/alex/Library/Caches/vinix-ios/app-attest-restored-20261025/app-attest-20261025`
also passes full checksums, rejection of missing guest media, an altered host
log and an unmanifested file, restoration of each mutation, and final checking.
The original and restored manifest hashes match.

Reproduce using the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`, `V_RESOURCE_PATH` set to that toolchain and
`V_MACOS_V3_NO_FALLBACK=1`. Build `tests/ios/notification-checks.v`,
`notification-vm.v`, `native-checks.v`, `app-attest-input-inventory.v` and
`app-attest-evidence.v`. Invoke the notification-checks driver with a fresh
external directory and modes `driver-build`, `app-attest-inspector-build`,
`app-attest-inspect`, `app-attest-host`, `build-app-attest`, `build-init`,
`build-run-ios-gles`, `app-attest`, `probe`, `audit`. Run `driver-build` first
to initialize its directories. Inspector and fixture generation preserve
assertions. Invoke the inventory helper with repository root, bundle directory
and tested revision; copy both audit helpers into the bundle as
`inventory-inputs.v` and `app-attest-evidence.v`. Use checker modes `seal DIR`,
`selftest DIR` and `hash FILE` to seal, audit and hash it.
