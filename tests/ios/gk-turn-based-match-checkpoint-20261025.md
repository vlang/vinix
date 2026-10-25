# Fortnite turn-based match checkpoint — 2026-10-25

Runtime and test revision: `8c4b711aecfddfe939eb345b348115bce84cc681`.
Advertising work remains skipped.

The GameKit shim now resolves scoped `GKTurnBasedMatch` class/metaclass imports.
Its opaque object is 40 bytes with parent NSObject. Local initialization provides
nil match ID, creation date, participants, current participant, match data,
message and exchange collections, with zero status. The match data limit is
65536 bytes, the exchange data limit is 1024 bytes and the initiated exchange
limit is 30 per player. Setting a message retains its identity, including mutable
strings; nil clears it and reinitialization resets it. Subclasses, caller storage,
isa changes, copying, coding, KVC, observation, other mutation and remote match
operations remain unsupported and fail explicitly. There is no Game Center
backend support.

The native ARM64 Mac Catalyst inspector passes size, inheritance, defaults,
signatures, retained mutable message identity, nil clearing and reset checks for
both `new` and `alloc`/`init`. Native match ID, creation date and match data use
forwarding; the shim provides synthetic accessors with the measured signatures
rather than native method-list parity. Native copying produces a distinct
176-byte `GKTurnBasedMatchInternal` with parent GKInternalRepresentation and
shared message identity. That private representation is outside this checkpoint;
the shim rejects copying. Native iOS was not measured.

Assertion-enabled host fixtures pass ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Coverage includes scoped imports, signatures,
saved IMPs, message retention and replacement, self-assignment, reset initialization,
weak lifetimes, four workers performing 128 iterations each, two drained runtimes
and 59 isolated rejection cases. Object counters balance and runtime object/block
maps drain. ASan leak detection was disabled; this does not establish absence of
all heap leaks. The broader regression suite was not rerun.

Drivers, the ARM64 fixture, initializer and GLES runner build successfully.
The focused Vinix ARM64 QEMU fixture passes with child status 0. A fresh full
Fortnite import audit reports **2986 resolved, 18 unresolved strong and 114
unresolved weak imports**, reducing the preceding strong-import count from
19 to 18. Per image, the main executable reports 2143/18/78, EOSSDK 664/0/16
and MarketplaceKitWrapper 179/0/20 (resolved/strong/weak). The audit does not
execute application code. A separate normal launch probe still stops at:

```text
iOS: linking /opt/ios/FortniteClient-IOS-Shipping: iOS: library is not implemented: /System/Library/Frameworks/StoreKit.framework/StoreKit (_OBJC_CLASS_$_SKAdNetwork)
```

Both Fortnite runs exit 1 during linking, before application entry; their
wrappers exit 0 after capturing that failure. Rendering, login and gameplay
remain unverified. SKAdNetwork work remains skipped as requested.

Archive: `/Users/alex/Library/Caches/vinix-ios/gk-turn-based-match-20261025.tar.zst`.
Archive SHA-256: `587555a48876e9d15f222ecd535f9b721864a754649470713d2339846aa34e11`.
Contained manifest SHA-256: `e0efb550afb2dd75f2877a05ee56f521d47a8ea46f04e69feba7726d3d90a7e7`.

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
`/Users/alex/Library/Caches/vinix-ios/gk-turn-based-match-restored-20261025/gk-turn-based-match-20261025`
also passes full checksums, rejection of missing guest media, an altered host
log and an unmanifested file, restoration of each mutation, and final checking.
The original and restored manifest hashes match.

Reproduce using the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`, `V_RESOURCE_PATH` set to that toolchain
and `V_MACOS_V3_NO_FALLBACK=1`. Build `tests/ios/notification-checks.v`,
`notification-vm.v`, `native-checks.v`, `gk-turn-based-match-input-inventory.v`
and `gk-turn-based-match-evidence.v`. Invoke the notification-checks driver
with a fresh external directory and modes `driver-build`,
`gk-turn-based-match-inspector-build`, `gk-turn-based-match-inspect`,
`gk-turn-based-match-host`, `build-gk-turn-based-match`, `build-init`,
`build-run-ios-gles`, `gk-turn-based-match`, `probe`, `audit`. Run
`driver-build` first to initialize its directories. Fixture generation preserves
assertions. Invoke the inventory helper with repository root, bundle directory
and tested revision; copy both audit helpers into the bundle as
`inventory-inputs.v` and `gk-turn-based-match-evidence.v`. Checker modes
are `seal DIR`, `check DIR`, `selftest DIR` and `hash FILE`.
