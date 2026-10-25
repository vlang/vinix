# Fortnite local player checkpoint — 2026-10-25

Runtime and test revision: `a9f1ddbad7c4576421c91461c9e6264edad45fc3`.
Advertising work remains skipped.

The GameKit shim now resolves scoped `GKLocalPlayer` class/metaclass imports.
Its opaque object is 120 bytes with parent GKPlayer. `localPlayer` and `local`
return one runtime-owned, synchronized singleton; `new` and `alloc`/`init`
create independent objects. Unauthenticated defaults are nil playerID,
displayName, guestIdentifier and authenticateHandler, alias `Unknown`, false
isFriend, isInvitable, scopedIDsArePersistent, isAuthenticated and isUnderage,
and true isMultiplayerGamingRestricted and isPersonalizedCommunicationRestricted.
The alias is owned and survives reinitialization; copying retains self.
Subclasses, caller storage, isa changes, mutation, coding, account authentication,
friends, listeners, saved games and identity verification remain unsupported
and fail explicitly. There is no Game Center backend support.

The assertion-enabled native ARM64 Mac Catalyst inspector passes size,
inheritance, singleton identity, independent allocation, all 12 getter defaults
and signatures, both class-method signatures and retained-copy checks across
all four construction paths. Native guestIdentifier, isFriend and isUnderage
use forwarding; the shim supplies synthetic accessors with measured signatures
rather than native method-list parity. Native iOS was not measured.

Assertion-enabled host fixtures pass ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Coverage includes scoped imports, scalar and
block return ABI, NSMethodSignature results, saved IMPs, retained copies, alias
ownership, weak lifetimes, concurrent first singleton construction, four workers
performing 128 iterations each, two drained runtimes and 38 isolated rejection
cases. Object counters balance and runtime object/weak maps drain. ASan leak
detection was disabled; this does not establish absence of all heap leaks.
Related GKPlayer and Game Center host fixtures also pass both sanitizer runs,
including their 40 and 30 rejection cases respectively. The broader suite was
not rerun.

Drivers, the ARM64 fixture, initializer and GLES runner build successfully.
The focused Vinix ARM64 QEMU fixture passes with child status 0. A fresh full
Fortnite import audit reports **2988 resolved, 16 unresolved strong and 114
unresolved weak imports**, reducing the preceding strong-import count from
17 to 16. Per image, the main executable reports 2145/16/78, EOSSDK 664/0/16
and MarketplaceKitWrapper 179/0/20 (resolved/strong/weak). The audit does not
execute application code. A separate normal launch probe still stops at:

```text
iOS: linking /opt/ios/FortniteClient-IOS-Shipping: iOS: library is not implemented: /System/Library/Frameworks/StoreKit.framework/StoreKit (_OBJC_CLASS_$_SKAdNetwork)
```

Both Fortnite runs exit 1 during linking, before application entry; their
wrappers exit 0 after capturing that failure. Rendering, login and gameplay
remain unverified. SKAdNetwork work remains skipped as requested.

Archive: `/Users/alex/Library/Caches/vinix-ios/gk-local-player-20261025.tar.zst`.
Archive SHA-256: `d5c9a0ef849c4665f983c7e259125f4f0e04c71125e718be7edb37e4844e461e`.
Contained manifest SHA-256: `e32f2924a258ba192743487ed57dc3d54389d777105d77b07111c5dc80f864d3`.

The complete bundle preserves 20 committed source snapshots, both V audit
helpers, 74 selected build input hashes, generated C, host objects/apps,
compiled drivers and ARM64 binaries, commands/statuses, complete GKPlayer and
Game Center host regression directories, and complete boot media, initramfs,
firmware variables, Limine configurations and serial logs for all three VMs.
All 141 files other than the manifest are checksummed. Local Fortnite assets
remain in external storage. Compiler, header and host library closures are not
independently sealed; rebuilding requires the prepared checkout dependencies. The prebuilt guest
kernel is inventoried; concurrent kernel edits were not rebuilt. Historical
checkers are unchanged.

Compression integrity and original-bundle checks/selftest pass. A fresh
extraction at
`/Users/alex/Library/Caches/vinix-ios/gk-local-player-restored-20261025/gk-local-player-20261025`
also passes full checksums, rejection of missing guest media, an altered host
log and an unmanifested file, restoration of each mutation, and final checking.
The original and restored manifest hashes match.

Reproduce using the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`, `V_RESOURCE_PATH` set to that toolchain
and `V_MACOS_V3_NO_FALLBACK=1`. Build `tests/ios/notification-checks.v`,
`notification-vm.v`, `native-checks.v`, `gk-local-player-input-inventory.v`
and `gk-local-player-evidence.v`. Invoke the notification-checks driver
with a fresh external directory and modes `driver-build`,
`gk-local-player-inspector-build`, `gk-local-player-inspect`,
`gk-local-player-host`, `build-gk-local-player`, `build-init`,
`build-run-ios-gles`, `gk-local-player`, `probe`, `audit`. Run
`driver-build` first to initialize its directories. Run `gk-player-host` and
`game-center-host` in separate fresh external directories and copy their complete
outputs into `regression/gk-player-host` and `regression/game-center-host`.
Native inspector and fixture generation omit `-prod` to preserve assertions.
Invoke the inventory helper with repository root, bundle directory and tested
revision; copy both audit helpers into the bundle as `inventory-inputs.v` and
`gk-local-player-evidence.v`. Checker modes are `seal DIR`, `check DIR`,
`selftest DIR` and `hash FILE`.
