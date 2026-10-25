# Fortnite GameKit achievement-description checkpoint — 2026-10-25

Runtime and test revision: `40d53f1e081264ef4dbb232dcbb4ea6e1d0f43a4`.
Advertising work remains skipped.

The GameKit shim now resolves scoped `GKAchievementDescription` class/metaclass
imports and supports local empty achievement metadata. The opaque 24-byte
object inherits from NSObject. All 13 measured getters return nil or zero;
reinitialization preserves identity. Mutation, copying, coding, observation,
KVC, backend loading and image factories remain unsupported and fail explicitly.
There is no Game Center backend.

The native ARM64 Mac Catalyst inspector passes size, inheritance, getter
defaults, signatures and repeated-initialization checks. The measured
`maximumPoints` signature returns unsigned short (`S@:`), despite the SDK's
NSInteger declaration; the shim follows the measured ABI. `isHidden` and
`isReplayable` return BOOL, and `releaseState` returns unsigned 64-bit integer.
Among measured getters, only `image` has a concrete native instance method;
the others use forwarding. Synthetic shim accessors model their
`NSMethodSignature` ABI, not native method-list parity. Native iOS was not
measured.

Assertion-enabled shim fixtures pass ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Coverage includes scoped imports, all getter
defaults/signatures, scalar ABI, saved IMPs, repeated initialization, weak
ownership, four workers performing 128 iterations each, two drained runtimes
and 36 isolated rejection cases. Object counters balance and runtime
object/block maps drain. ASan leak detection was disabled; these checks do not
establish absence of all heap leaks. The broader native regression suite was
not rerun.

Drivers, the ARM64 fixture, initializer and GLES runner build successfully.
The focused Vinix ARM64 QEMU fixture passes with child status 0. A fresh full
Fortnite import audit reports **2983 resolved, 21 unresolved strong and 114
unresolved weak imports**, reducing the preceding strong-import count from
22 to 21. Per image, the main executable reports 2140/21/78, EOSSDK 664/0/16
and MarketplaceKitWrapper 179/0/20 (resolved/strong/weak). The audit does not
execute application code. A separate normal launch probe still stops at:

```text
iOS: linking /opt/ios/FortniteClient-IOS-Shipping: iOS: library is not implemented: /System/Library/Frameworks/StoreKit.framework/StoreKit (_OBJC_CLASS_$_SKAdNetwork)
```

Both Fortnite runs exit 1 during linking, before application entry; their
wrappers exit 0 after capturing that failure. Rendering, login and gameplay
remain unverified. SKAdNetwork work remains skipped as requested.

Archive: `/Users/alex/Library/Caches/vinix-ios/gk-achievement-description-20261025.tar.zst`.
Archive SHA-256: `83f0455095f6d5fac54de8a027db453ab703c3d8ef8a6959eb14d6e412e28956`.
Contained manifest SHA-256: `668a4972f35696c4ef22b7fd980082724bbc411a7d17778161d037a0413024ae`.

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
`/Users/alex/Library/Caches/vinix-ios/gk-achievement-description-restored-20261025/gk-achievement-description-20261025`
also passes full checksums, rejection of missing guest media, an altered host
log and an unmanifested file, restoration of each mutation, and final checking.
The original and restored manifest hashes match.

Reproduce using the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`, `V_RESOURCE_PATH` set to that toolchain
and `V_MACOS_V3_NO_FALLBACK=1`. Build `tests/ios/notification-checks.v`,
`notification-vm.v`, `native-checks.v`,
`gk-achievement-description-input-inventory.v` and
`gk-achievement-description-evidence.v`. Invoke the notification-checks driver
with a fresh external directory and modes `driver-build`,
`gk-achievement-description-inspector-build`,
`gk-achievement-description-inspect`, `gk-achievement-description-host`,
`build-gk-achievement-description`, `build-init`, `build-run-ios-gles`,
`gk-achievement-description`, `probe`, `audit`. Run `driver-build` first to
initialize its directories. Fixture generation preserves assertions. Invoke
the inventory helper with repository root, bundle directory and tested
revision; copy both audit helpers into the bundle as `inventory-inputs.v` and
`gk-achievement-description-evidence.v`. Use checker modes `seal DIR`,
`check DIR`, `selftest DIR` and `hash FILE` to seal, audit and hash it.
