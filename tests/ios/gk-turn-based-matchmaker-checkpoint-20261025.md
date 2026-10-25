# Fortnite turn-based matchmaker checkpoint — 2026-10-25

Runtime and test revision: `9aff5984de0dd254e26f14b3d1860f3399a6f98a`.
Advertising work remains skipped.

The GameKit shim now resolves scoped `GKTurnBasedMatchmakerViewController`
class/metaclass imports with matching UINavigationController inheritance. Class
reflection and subclass metadata work. UI construction, allocation, copying,
coding, initialization with a match request, delegate properties and matchmaking
remain unsupported; the shim does not advertise their selectors or construct a
placeholder controller.
Construction and storage changes fail explicitly through the existing
navigation controller guards.

The assertion-enabled native ARM64 Mac Catalyst inspector verifies class and
metaclass inheritance for both Game Center controllers and UINavigationController.
It constructs no UI. Native iOS behavior was not measured.

Assertion-enabled host fixtures pass ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Coverage includes scoped class/metaclass imports,
inheritance, subclass metadata, truthful method reflection, two drained runtimes
and 48 isolated rejection cases across UINavigationController,
GKGameCenterViewController and GKTurnBasedMatchmakerViewController. These cover
dispatch, direct/caller allocation, subclasses, saved NSObject IMPs and isa
changes. Object counters and runtime object maps drain. ASan leak detection was
disabled; this does not establish absence of all heap leaks. The broader suite
was not rerun.

Drivers, the ARM64 fixture, initializer and GLES runner build successfully.
The focused Vinix ARM64 QEMU fixture passes with child status 0. A fresh full
Fortnite import audit reports **2989 resolved, 15 unresolved strong and 114
unresolved weak imports**, reducing the preceding strong-import count from
16 to 15. Per image, the main executable reports 2146/15/78, EOSSDK 664/0/16
and MarketplaceKitWrapper 179/0/20 (resolved/strong/weak). The audit does not
execute application code. A separate normal launch probe still stops at:

```text
iOS: linking /opt/ios/FortniteClient-IOS-Shipping: iOS: library is not implemented: /System/Library/Frameworks/StoreKit.framework/StoreKit (_OBJC_CLASS_$_SKAdNetwork)
```

Both Fortnite runs exit 1 during linking, before application entry; their
wrappers exit 0 after capturing that failure. Rendering, login and gameplay
remain unverified. SKAdNetwork work remains skipped as requested. The other
remaining strong imports concern StoreKit payments/products, AVPlayer and its
assets/outputs, NSProxy and SwiftObject.

Archive: `/Users/alex/Library/Caches/vinix-ios/gk-turn-based-matchmaker-20261025.tar.zst`.
Archive SHA-256: `ee4cc0827c987cda05c92252cf8bce6b00bd0e43fa6b473326907f9ff570f984`.
Contained manifest SHA-256: `c727c9d33981f9ac7cdd8b3a54bb8dd5ab5a048652948e0e630970cbb0b3ffef`.

The complete bundle preserves 15 selected committed source snapshots, both V
audit helpers, 75 selected build input hashes, the native inspector, generated C,
host objects/app, compiled drivers and ARM64 binaries, commands/statuses, and
complete boot media, initramfs, firmware variables, Limine configurations and
serial logs for all three VMs. All 88 files other than the manifest are
checksummed. Local Fortnite assets remain in external storage. Compiler, header
and host library closures are not independently sealed; rebuilding requires the
prepared checkout dependencies. The prebuilt guest kernel is inventoried;
concurrent kernel edits were not rebuilt. Historical checkers are unchanged.

Compression integrity and original-bundle checks/selftest pass. A fresh
extraction at
`/Users/alex/Library/Caches/vinix-ios/gk-turn-based-matchmaker-restored-20261025/gk-turn-based-matchmaker-20261025`
also passes full checksums, rejection of missing guest media, an altered host
log and an unmanifested file, restoration of each mutation, and final checking.
The original and restored manifest hashes match.

Reproduce using the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`, `V_RESOURCE_PATH` set to that toolchain
and `V_MACOS_V3_NO_FALLBACK=1`. Build `tests/ios/notification-checks.v`,
`notification-vm.v`, `native-checks.v`,
`gk-turn-based-matchmaker-input-inventory.v` and
`gk-turn-based-matchmaker-evidence.v`. Invoke the notification-checks driver
with a fresh external directory and modes `driver-build`,
`gk-turn-based-matchmaker-inspector-build`, `gk-turn-based-matchmaker-inspect`,
`game-center-host`, `build-game-center`, `build-init`, `build-run-ios-gles`,
`game-center`, `probe`, `audit`. Run `driver-build` first to initialize its
directories. Native inspector and fixture generation omit `-prod` to preserve
assertions. Invoke the inventory helper with repository root, bundle directory
and tested revision; copy both audit helpers into the bundle as
`inventory-inputs.v` and `gk-turn-based-matchmaker-evidence.v`. Checker modes
are `seal DIR`, `check DIR`, `selftest DIR` and `hash FILE`.
