# Fortnite GCEventViewController checkpoint — 2026-10-25

Runtime and test revision: `75b73c969203ae16b452cdd4f94be1161e20e482`.
Advertising work remains skipped.

GameController now resolves scoped `GCEventViewController` class and metaclass
imports. The profile implements initialization, nil-nib/nil-bundle
initialization and `controllerUserInteractionEnabled`. The flag defaults to NO;
setters use the low BOOL byte, and repeated initialization preserves its value.
Subclasses, saved implementations and UIKit's existing lazy/replacement view
ownership are covered. Controller event delivery remains unimplemented.

The parent follows the public iOS declaration, `UIViewController`. Local ARM64
Catalyst inspection instead exposes an NSObject facade with a 1112-byte
instance. The compatibility object reserves that size without exposing the
Catalyst private ivars; state lives in the runtime header. Method encodings,
default state and repeated initialization match the native inspection. This
does not establish device iOS instance layout. Caller storage, incompatible or
forged isa, uninitialized property access, nonnil nib/bundle arguments, copying
and coding fail explicitly.

The native inspector and assertion-enabled host fixture pass. Host fixtures
run with ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. The focused Vinix ARM64 QEMU fixture passes
with child status 0, including scoped imports, hierarchy/metadata, BOOL state,
subclass storage canaries, saved implementations, UIKit view ownership, two
drained runtimes and 16 fatal rejection cases. Runtime object counters balance.
ASan leak detection was disabled; this does not establish absence of all heap
leaks. Drivers, the ARM64 fixture, initializer and GLES runner build
successfully. The broader native regression suite was not rerun.

A fresh full Fortnite import audit reports 2976 resolved imports, 28 unresolved
strong imports and 114 unresolved weak imports. Both GCEventViewController
imports now resolve, reducing the previous measured strong-import count from
30 to 28. The audit does not execute application code. A separate normal
launch probe still stops at:

```text
iOS: linking /opt/ios/FortniteClient-IOS-Shipping: iOS: library is not implemented: /System/Library/Frameworks/StoreKit.framework/StoreKit (_OBJC_CLASS_$_SKAdNetwork)
```

Both Fortnite runs exit 1 during linking, before application entry; their
wrappers exit 0 after capturing that failure. Rendering, login and gameplay
remain unverified. SKAdNetwork work remains skipped as requested.

Archive: `/Users/alex/Library/Caches/vinix-ios/gc-event-view-controller-20261025.tar.zst`.
Archive SHA-256: `6c8cea9a1fafc25b41a68c201a84adcc870472b47732cb8ca51bba9c36bab1e1`.
Contained manifest SHA-256: `c2c81658f272321a2b38b9a15dcb498bc9eb2605874c2078ab39514cc2237910`.

The complete bundle preserves 16 committed source snapshots, both V audit
helpers, 73 selected build input hashes, generated C, host objects/app,
compiled drivers and ARM64 binaries, commands/statuses, and complete boot
media, initramfs, firmware variables, Limine configurations and serial logs
for all three VMs. All 89 files other than the manifest are checksummed.
Local Fortnite assets remain in external storage. Compiler, header and host
library closures are not independently sealed; rebuilding requires the
prepared checkout dependencies. Historical checkers are unchanged.

Compression integrity and original-bundle selftest pass. A fresh extraction at
`/Users/alex/Library/Caches/vinix-ios/gc-event-view-controller-restored-20261025/gc-event-view-controller-20261025`
also passes full checksums, rejection of missing guest media, an altered host
log and an unmanifested file, restoration of each mutation, and final checking.
The original and restored manifest hashes match.

Reproduce using the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`, `V_RESOURCE_PATH` set to that toolchain and
`V_MACOS_V3_NO_FALLBACK=1`. Build `tests/ios/notification-checks.v`,
`notification-vm.v`, `native-checks.v`,
`gc-event-view-controller-input-inventory.v` and
`gc-event-view-controller-evidence.v`. Invoke the notification-checks driver
with a fresh external directory and modes `driver-build`,
`gc-event-view-controller-inspector-build`, `gc-event-view-controller-inspect`,
`gc-event-view-controller-host`, `build-gc-event-view-controller`, `build-init`,
`build-run-ios-gles`, `gc-event-view-controller`, `probe`, `audit`. Run
`driver-build` first to initialize its directories. Inspector and fixture
generation preserve assertions. Invoke the inventory helper with repository
root, bundle directory and tested revision; copy both audit helpers into the
bundle as `inventory-inputs.v` and `gc-event-view-controller-evidence.v`. Use
checker modes `seal DIR`, `selftest DIR` and `hash FILE` to seal, audit and hash
it.
