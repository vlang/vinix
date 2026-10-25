# Fortnite leaderboard checkpoint — 2026-10-25

Runtime and test revision: `ef7d80687eded67c7dea96ebef056b9cdc43bece`.
Advertising work remains skipped.

The GameKit shim now resolves scoped `GKLeaderboard` class/metaclass imports.
Its opaque object is 88 bytes with parent NSObject. Local initialization provides
nil title, group/base identifiers, dates, scores and local-player score, zero
type, duration, maxRange and loading state, time scope 2, player scope 0 and
range `{1,25}`. Identifier and category share retained string identity, including
mutable strings; nil clears them and reinitialization resets all configuration.
Scope values preserve their raw 64-bit values. Range uses the ARM64 two-register
aggregate ABI and rejects location zero or length greater than 100. Duration uses
the floating-point return register. Subclasses, caller storage, isa changes,
copying, coding, KVC, observation, other mutation and remote leaderboard operations
remain unsupported and fail explicitly. There is no Game Center backend support.

The assertion-enabled native ARM64 Mac Catalyst inspector passes size,
inheritance, defaults, all 22 signatures, retained mutable identifier/category
identity, nil clearing, scope/range boundaries and reset checks for both `new`
and `alloc`/`init`. Three invalid ranges raise NSRangeException in isolated child
processes. Eleven native selectors use forwarding; the shim provides synthetic
accessors with the measured signatures rather than native method-list parity.
Native iOS was not measured.

Assertion-enabled host fixtures pass ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Coverage includes scoped imports, selector
encodings, 20 scalar/pointer NSMethodSignature results, saved IMPs, retained
identifier/category identity, replacement, reset initialization, weak lifetimes,
four workers performing 128 iterations each, two drained runtimes and 53 isolated
rejection cases. Direct and saved-IMP range access passes; aggregate
NSMethodSignature construction for `range` and `setRange:` is explicitly rejected.
Aggregate NSInvocation support is outside this checkpoint. Object counters balance
and runtime object/block maps drain. ASan leak detection was disabled; this does
not establish absence of all heap leaks. The broader regression suite was not rerun.

Drivers, the ARM64 fixture, initializer and GLES runner build successfully.
The focused Vinix ARM64 QEMU fixture passes with child status 0. A fresh full
Fortnite import audit reports **2987 resolved, 17 unresolved strong and 114
unresolved weak imports**, reducing the preceding strong-import count from
18 to 17. Per image, the main executable reports 2144/17/78, EOSSDK 664/0/16
and MarketplaceKitWrapper 179/0/20 (resolved/strong/weak). The audit does not
execute application code. A separate normal launch probe still stops at:

```text
iOS: linking /opt/ios/FortniteClient-IOS-Shipping: iOS: library is not implemented: /System/Library/Frameworks/StoreKit.framework/StoreKit (_OBJC_CLASS_$_SKAdNetwork)
```

Both Fortnite runs exit 1 during linking, before application entry; their
wrappers exit 0 after capturing that failure. Rendering, login and gameplay
remain unverified. SKAdNetwork work remains skipped as requested.

Archive: `/Users/alex/Library/Caches/vinix-ios/gk-leaderboard-20261025.tar.zst`.
Archive SHA-256: `caee8aae2d5fa793ccee6d24791589db18b109b830d86d4aef97b44851fac2e9`.
Contained manifest SHA-256: `126edab1126715b0d3b00e45b24f79291dc10f9453d446ecc4136b8cb7c29046`.

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
`/Users/alex/Library/Caches/vinix-ios/gk-leaderboard-restored-20261025/gk-leaderboard-20261025`
also passes full checksums, rejection of missing guest media, an altered host
log and an unmanifested file, restoration of each mutation, and final checking.
The original and restored manifest hashes match.

Reproduce using the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`, `V_RESOURCE_PATH` set to that toolchain
and `V_MACOS_V3_NO_FALLBACK=1`. Build `tests/ios/notification-checks.v`,
`notification-vm.v`, `native-checks.v`, `gk-leaderboard-input-inventory.v`
and `gk-leaderboard-evidence.v`. Invoke the notification-checks driver
with a fresh external directory and modes `driver-build`,
`gk-leaderboard-inspector-build`, `gk-leaderboard-inspect`,
`gk-leaderboard-host`, `build-gk-leaderboard`, `build-init`,
`build-run-ios-gles`, `gk-leaderboard`, `probe`, `audit`. Run
`driver-build` first to initialize its directories. Native inspector and fixture
generation omit `-prod` to preserve assertions. Invoke the inventory helper with
repository root, bundle directory and tested revision; copy both audit helpers
into the bundle as `inventory-inputs.v` and `gk-leaderboard-evidence.v`. Checker
modes are `seal DIR`, `check DIR`, `selftest DIR` and `hash FILE`.
