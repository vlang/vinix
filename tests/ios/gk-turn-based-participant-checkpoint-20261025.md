# Fortnite turn-based participant checkpoint — 2026-10-25

Runtime and test revision: `a687603d34c6f843fd8f128c9c19a83545e89c13`.
Advertising work remains skipped.

The GameKit shim now resolves scoped `GKTurnBasedParticipant` class/metaclass
imports. Its opaque object is 16 bytes with parent NSObject. Local initialization
provides nil `player`, `playerID`, `lastTurnDate` and `timeoutDate`, with zero
`status` and `matchOutcome`. The outcome setter stores an unsigned 32-bit value;
reinitialization resets it to zero. `copy` and `copyWithZone:` return distinct,
independently mutable objects with +1 ownership. Subclasses, caller storage, isa
changes, other mutation, mutable copying, coding, KVC and observation remain
unsupported and fail explicitly. There is no Game Center backend or remote
participant support.

The native ARM64 Mac Catalyst inspector passes size, inheritance, defaults,
signatures, outcome truncation, repeated initialization and independent copy
checks for both `new` and `alloc`/`init`. Its forwarding signatures use unsigned
32-bit `matchOutcome` despite the SDK's NSInteger declaration. Native
`timeoutDate`, outcome accessors and `copyWithZone:` use forwarding; the shim
provides synthetic accessors with the measured signatures rather than native
method-list parity. Native iOS was not measured.

Assertion-enabled host fixtures pass ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Coverage includes scoped imports, signatures,
scalar ABI, saved IMPs, reset initialization, copy independence, weak lifetimes,
four workers performing 128 iterations each, two drained runtimes and 31 isolated
rejection cases. Object counters balance and runtime object/block maps drain.
ASan leak detection was disabled; this does not establish absence of all heap
leaks. The broader regression suite was not rerun.

Drivers, the ARM64 fixture, initializer and GLES runner build successfully.
The focused Vinix ARM64 QEMU fixture passes with child status 0. A fresh full
Fortnite import audit reports **2985 resolved, 19 unresolved strong and 114
unresolved weak imports**, reducing the preceding strong-import count from
20 to 19. Per image, the main executable reports 2142/19/78, EOSSDK 664/0/16
and MarketplaceKitWrapper 179/0/20 (resolved/strong/weak). The audit does not
execute application code. A separate normal launch probe still stops at:

```text
iOS: linking /opt/ios/FortniteClient-IOS-Shipping: iOS: library is not implemented: /System/Library/Frameworks/StoreKit.framework/StoreKit (_OBJC_CLASS_$_SKAdNetwork)
```

Both Fortnite runs exit 1 during linking, before application entry; their
wrappers exit 0 after capturing that failure. Rendering, login and gameplay
remain unverified. SKAdNetwork work remains skipped as requested.

Archive: `/Users/alex/Library/Caches/vinix-ios/gk-turn-based-participant-20261025.tar.zst`.
Archive SHA-256: `4ebfcc7222e600e2c03668e6357c036027dcd9f06f5901426d0c533b2d37e29c`.
Contained manifest SHA-256: `522b69cb75f69c199f5fcf94f38a7d4bfcbb6088d446a060788dd8f9930ad4c6`.

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
`/Users/alex/Library/Caches/vinix-ios/gk-turn-based-participant-restored-20261025/gk-turn-based-participant-20261025`
also passes full checksums, rejection of missing guest media, an altered host
log and an unmanifested file, restoration of each mutation, and final checking.
The original and restored manifest hashes match.

Reproduce using the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`, `V_RESOURCE_PATH` set to that toolchain
and `V_MACOS_V3_NO_FALLBACK=1`. Build `tests/ios/notification-checks.v`,
`notification-vm.v`, `native-checks.v`, `gk-turn-based-participant-input-inventory.v`
and `gk-turn-based-participant-evidence.v`. Invoke the notification-checks driver
with a fresh external directory and modes `driver-build`,
`gk-turn-based-participant-inspector-build`, `gk-turn-based-participant-inspect`,
`gk-turn-based-participant-host`, `build-gk-turn-based-participant`, `build-init`,
`build-run-ios-gles`, `gk-turn-based-participant`, `probe`, `audit`. Run
`driver-build` first to initialize its directories. Fixture generation preserves
assertions. Invoke the inventory helper with repository root, bundle directory
and tested revision; copy both audit helpers into the bundle as
`inventory-inputs.v` and `gk-turn-based-participant-evidence.v`. Checker modes
are `seal DIR`, `check DIR`, `selftest DIR` and `hash FILE`.
