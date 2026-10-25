# Fortnite WKSnapshotConfiguration checkpoint — 2026-10-25

Runtime and test revision: `452487964021348238ab5ec3692389d6f8e7803d`.
Advertising work remains skipped.

WebKit now resolves scoped `WKSnapshotConfiguration` class/metaclass imports
with `NSObject` as the parent. The profile implements initialization, CGRect
storage, copied NSNumber snapshot widths, `afterScreenUpdates`, `copy` and
`copyWithZone:`. Defaults are CGRectNull, nil width and afterScreenUpdates=YES.
Reinitialization resets the rectangle and flag while preserving the width,
matching local ARM64 Catalyst inspection. Rectangle values preserve their raw
bits, including signed zero, infinities and NaN payloads, across ARM64 HFA
argument/return dispatch. Copies have independent configuration state.

Metadata and the measured 56-byte instance size match Catalyst; this does not
establish device iOS WebKit layout. Only validated, initialized, exact-class
objects and supported live NSNumber widths are accepted. Subclasses,
metaclasses, caller storage, incompatible/forged isa, uninitialized access,
mutable copying, coding and unsupported private APIs fail explicitly.
WKWebView snapshot rendering remains unimplemented.

The native inspector and assertion-enabled host fixtures pass. Host fixtures
run with ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. The focused Vinix ARM64 QEMU fixture passes
with child status 0: scoped imports, metadata/defaults, CGRect HFA bits, copied
widths, saved implementations, independent copies, two drained runtimes and
15 fatal rejection cases. Runtime object counters balance. ASan leak detection
was disabled; this does not establish absence of all heap leaks. Drivers,
the ARM64 fixture, initializer and GLES runner build successfully. The broader
native regression suite was not rerun.

A fresh full Fortnite import audit reports 2974 resolved imports, 30 unresolved
strong imports and 114 unresolved weak imports. This is one fewer missing
strong import than the previous measured baseline of 31. The audit does not
execute application code. A separate normal launch probe still stops at:

```text
iOS: linking /opt/ios/FortniteClient-IOS-Shipping: iOS: library is not implemented: /System/Library/Frameworks/StoreKit.framework/StoreKit (_OBJC_CLASS_$_SKAdNetwork)
```

Both Fortnite runs exit 1 during linking, before application entry; their
wrappers exit 0 after capturing that failure. Rendering, login and gameplay
remain unverified. SKAdNetwork work remains skipped as requested.

Archive: `/Users/alex/Library/Caches/vinix-ios/wk-snapshot-configuration-20261025.tar.zst`.
Archive SHA-256: `e4507664b95c546059d3d320c167c8e947c7665fd6af8e2e95fc9e8eea6f0d9f`.
Contained manifest SHA-256: `ed3433487414886b2919a384273536f2d222fd0a6b9c139ce3bbf71bd91ee48c`.

The complete bundle preserves 15 committed source snapshots, both V audit
helpers, 73 selected build input hashes, generated C, host objects/app,
compiled drivers and ARM64 binaries, commands/statuses, and complete boot
media, initramfs, firmware variables, Limine configurations and serial logs
for all three VMs. All 93 files other than the manifest are checksummed.
Local Fortnite assets remain in external storage. Compiler, header and host
library closures are not independently sealed; rebuilding requires the
prepared checkout dependencies. Historical checkers are unchanged.

Compression integrity and original-bundle selftest pass. A fresh extraction at
`/Users/alex/Library/Caches/vinix-ios/wk-snapshot-configuration-restored-20261025/wk-snapshot-configuration-20261025`
also passes full checksums, rejection of missing guest media, an altered host
log and an unmanifested file, restoration of each mutation, and final checking.
The original and restored manifest hashes match.

Reproduce using the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`, `V_RESOURCE_PATH` set to that toolchain and
`V_MACOS_V3_NO_FALLBACK=1`. Build `tests/ios/notification-checks.v`,
`notification-vm.v`, `native-checks.v`,
`snapshot-configuration-input-inventory.v` and `snapshot-configuration-evidence.v`.
Invoke the notification-checks driver with a fresh external directory and
modes `driver-build`, `snapshot-configuration-inspector-build`,
`snapshot-configuration-inspect`, `snapshot-configuration-host`,
`build-snapshot-configuration`, `build-init`, `build-run-ios-gles`,
`snapshot-configuration`, `probe`, `audit`. Run `driver-build` first to
initialize its directories. Inspector and fixture generation preserve
assertions. Invoke the inventory helper with repository root, bundle directory
and tested revision; copy both audit helpers into the bundle as
`inventory-inputs.v` and `snapshot-configuration-evidence.v`. Use checker modes
`seal DIR`, `selftest DIR` and `hash FILE` to seal, audit and hash it.
