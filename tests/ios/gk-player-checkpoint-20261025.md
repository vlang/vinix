# Fortnite GameKit player checkpoint — 2026-10-25

Runtime and test revision: `e427e49fa48523c582e37bcaa6698710103f7c0f`.
Advertising work remains skipped.

The GameKit shim now resolves scoped `GKBasePlayer` and `GKPlayer`
class/metaclass imports. Their opaque objects are 8 and 32 bytes respectively,
with inheritance NSObject → GKBasePlayer → GKPlayer. Local initialization
provides nil `playerID` and `displayName`; GKPlayer additionally provides alias
`Unknown`, nil `guestIdentifier` and false `isFriend`, `isInvitable` and
`scopedIDsArePersistent`. Reinitialization preserves identity and alias ownership;
`copy` and `copyWithZone:` return retained self. Scoped game/team identities,
mutation, mutable copying, coding, KVC, observation, guest factories, player
loading, friends and photos remain unsupported and fail explicitly. There is
no Game Center backend.

The native ARM64 Mac Catalyst inspector passes size, inheritance, defaults,
method signatures, copy ownership and repeated initialization checks. Native
`guestIdentifier` and `isFriend` use forwarding; synthetic shim accessors
model their measured signatures rather than native method-list parity. Native
iOS was not measured. Game/team identifiers are excluded from this checkpoint.

Assertion-enabled host fixtures pass ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Coverage includes scoped imports, signatures,
scalar ABI, saved IMPs, retained copies, weak player/alias lifetimes, four
workers performing 128 iterations each, two drained runtimes and 40 isolated
rejection cases. Object counters balance and runtime object/block maps drain.
ASan leak detection was disabled; this does not establish absence of all heap
leaks. The broader regression suite was not rerun.

Drivers, the ARM64 fixture, initializer and GLES runner build successfully.
The focused Vinix ARM64 QEMU fixture passes with child status 0. A fresh full
Fortnite import audit reports **2984 resolved, 20 unresolved strong and 114
unresolved weak imports**, reducing the preceding strong-import count from
21 to 20. Per image, the main executable reports 2141/20/78, EOSSDK 664/0/16
and MarketplaceKitWrapper 179/0/20 (resolved/strong/weak). The audit does not
execute application code. A separate normal launch probe still stops at:

```text
iOS: linking /opt/ios/FortniteClient-IOS-Shipping: iOS: library is not implemented: /System/Library/Frameworks/StoreKit.framework/StoreKit (_OBJC_CLASS_$_SKAdNetwork)
```

Both Fortnite runs exit 1 during linking, before application entry; their
wrappers exit 0 after capturing that failure. Rendering, login and gameplay
remain unverified. SKAdNetwork work remains skipped as requested.

Archive: `/Users/alex/Library/Caches/vinix-ios/gk-player-20261025.tar.zst`.
Archive SHA-256: `0103d4f635692277d31858eaa39eaeafb840cb826e74300b35d147f11d678a54`.
Contained manifest SHA-256: `019406781edb984982d2df4e10db000b0ca99eb421b8df32d67fa353f8f691d2`.

The complete bundle preserves 17 committed source snapshots, both V audit
helpers, 74 selected build input hashes, generated C, host objects/app,
compiled drivers and ARM64 binaries, commands/statuses, and complete boot
media, initramfs, firmware variables, Limine configurations and serial logs
for all three VMs. All 90 files other than the manifest are checksummed.
Local Fortnite assets remain in external storage. Compiler, header and host
library closures are not independently sealed; rebuilding requires the
prepared checkout dependencies. The prebuilt guest kernel is inventoried;
concurrent kernel edits were not rebuilt. Historical checkers are unchanged.

Compression integrity and original-bundle checks/selftest pass. A fresh
extraction at
`/Users/alex/Library/Caches/vinix-ios/gk-player-restored-20261025/gk-player-20261025`
also passes full checksums, rejection of missing guest media, an altered host
log and an unmanifested file, restoration of each mutation, and final checking.
The original and restored manifest hashes match.

Reproduce using the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`, `V_RESOURCE_PATH` set to that toolchain
and `V_MACOS_V3_NO_FALLBACK=1`. Build `tests/ios/notification-checks.v`,
`notification-vm.v`, `native-checks.v`, `gk-player-input-inventory.v` and
`gk-player-evidence.v`. Invoke the notification-checks driver with a fresh
external directory and modes `driver-build`, `gk-player-inspector-build`,
`gk-player-inspect`, `gk-player-host`, `build-gk-player`, `build-init`,
`build-run-ios-gles`, `gk-player`, `probe`, `audit`. Run `driver-build` first
to initialize its directories. Fixture generation preserves assertions.
Invoke the inventory helper with repository root, bundle directory and tested
revision; copy both audit helpers into the bundle as `inventory-inputs.v` and
`gk-player-evidence.v`. Checker modes are `seal DIR`, `check DIR`,
`selftest DIR` and `hash FILE`.
