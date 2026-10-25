# Fortnite AVFoundation playback metadata checkpoint — 2026-10-25

Runtime and test revision: `fbb79fc0df04e6df73e991c199169d95083bbe98`.
Advertising work remains skipped.

The AVFoundation shim now resolves scoped class/metaclass imports for AVAsset,
AVURLAsset, AVPlayer, AVPlayerItem, AVPlayerItemOutput,
AVPlayerItemLegibleOutput and AVPlayerItemVideoOutput. AVURLAsset inherits from
AVAsset; the two concrete output classes inherit from AVPlayerItemOutput; the
remaining classes inherit from NSObject. Class reflection and subclass metadata
work. These are metadata descriptors: concrete instances, assets, output storage
and playback remain unsupported. Construction, factories, copying, direct/caller
allocation, saved NSObject allocation IMPs and isa changes fail explicitly;
unsupported selectors are absent from method reflection.

The assertion-enabled native ARM64 Mac Catalyst inspector verifies all seven
class and metaclass inheritance chains. It constructs no media objects and does
not exercise playback. Native iOS behavior was not measured.

Assertion-enabled host fixtures pass ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Coverage includes scoped class/metaclass imports,
inheritance, subclass metadata, truthful method reflection, two drained runtimes
and 140 isolated rejection cases covering dispatch, factories, direct/caller
allocation, subclasses, saved NSObject IMPs and isa changes. Object counters and
runtime object maps drain. ASan leak detection was disabled; this does not
establish absence of all heap leaks. The broader suite was not rerun.

Drivers, the ARM64 fixture, initializer and GLES runner build successfully.
The focused Vinix ARM64 QEMU fixture passes with child status 0. A fresh full
Fortnite import audit reports **2994 resolved, 10 unresolved strong and 114
unresolved weak imports**, reducing the preceding strong-import count from
15 to 10. The five newly resolved Fortnite imports are the AVURLAsset, AVPlayer,
AVPlayerItem, AVPlayerItemLegibleOutput and AVPlayerItemVideoOutput classes.
Per image, the main executable reports 2151/10/78, EOSSDK 664/0/16 and
MarketplaceKitWrapper 179/0/20 (resolved/strong/weak). The audit does not execute
application code. A separate normal launch probe still stops at:

```text
iOS: linking /opt/ios/FortniteClient-IOS-Shipping: iOS: library is not implemented: /System/Library/Frameworks/StoreKit.framework/StoreKit (_OBJC_CLASS_$_SKAdNetwork)
```

Both Fortnite runs exit 1 during linking, before application entry; their
wrappers exit 0 after capturing that failure. Rendering, login and gameplay
remain unverified. SKAdNetwork work remains skipped as requested. The other nine
strong imports are SKPaymentQueue, SKMutablePayment and SKReceiptRefreshRequest
classes, plus class/metaclass pairs for SKProductsRequest, NSProxy and
SwiftObject.

Archive: `/Users/alex/Library/Caches/vinix-ios/av-player-20261025.tar.zst`.
Archive SHA-256: `2f11e0b03b701ee57db8db165893a666df8438a08103430f034ebd22c0840aab`.
Contained manifest SHA-256: `d5c4456fddc6b6ab693b71cc91ae875ff9770264564be0fa90ba58faa323e404`.

The complete bundle preserves 15 selected committed source snapshots, both V
audit helpers, 76 selected build input hashes, the native inspector, generated C,
host objects/app, compiled drivers and ARM64 binaries, commands/statuses, and
complete boot media, initramfs, firmware variables, Limine configurations and
serial logs for all three VMs. All 88 files other than the manifest are
checksummed. Local Fortnite assets remain in external storage. Compiler, header
and host library closures are not independently sealed; rebuilding requires the
prepared checkout dependencies. The prebuilt guest kernel is inventoried;
concurrent kernel edits were not rebuilt. Historical checkers are unchanged.

Compression integrity and original-bundle checks/selftest pass. A fresh
extraction at
`/Users/alex/Library/Caches/vinix-ios/av-player-restored-20261025/av-player-20261025`
also passes full checksums, rejection of missing guest media, an altered host
log and an unmanifested file, restoration of each mutation, and final checking.
The original and restored manifest hashes match.

Reproduce using the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`, `V_RESOURCE_PATH` set to that toolchain
and `V_MACOS_V3_NO_FALLBACK=1`. Build `tests/ios/notification-checks.v`,
`notification-vm.v`, `native-checks.v`, `av-player-input-inventory.v` and
`av-player-evidence.v`. Invoke the notification-checks driver with a fresh
external directory and modes `driver-build`, `av-player-inspector-build`,
`av-player-inspect`, `av-player-host`, `build-av-player`, `build-init`,
`build-run-ios-gles`, `av-player`, `probe`, `audit`. Run `driver-build` first to
initialize its directories. Native inspector and fixture generation omit
`-prod` to preserve assertions. Invoke the inventory helper with repository
root, bundle directory and tested revision; copy both audit helpers into the
bundle as `inventory-inputs.v` and `av-player-evidence.v`. Checker modes are
`seal DIR`, `check DIR`, `selftest DIR` and `hash FILE`.
