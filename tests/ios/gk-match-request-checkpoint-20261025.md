# Fortnite GameKit match request checkpoint — 2026-10-25

Runtime and test revision: `2414a0ff7a8344bd0a5a2dc5295c3f7bf58f70d1`.
Advertising work remains skipped.

The GameKit shim now resolves scoped `GKMatchRequest` class/metaclass imports
and supports its six numeric configuration properties: `minPlayers`,
`maxPlayers`, `playerGroup`, `playerAttributes`, `defaultNumberOfPlayers` and
`restrictToAutomatch`. Defaults are respectively 2, 2, 1, 4294967295, 0 and 0.
The opaque 40-byte object inherits from NSObject; private shim state preserves
independent properties, native truncation and defaults on reinitialization.
There is no matchmaking backend. Unsupported construction, copying, coding,
recipients, rules, observation and storage fail explicitly.

The native ARM64 Mac Catalyst inspector passes size, inheritance, defaults,
truncation, property independence, reinitialization and forwarded ABI checks.
Native numeric accessors are absent from `class_getInstanceMethod`; synthetic
shim methods model their `NSMethodSignature` ABI, not native method-list parity.
Their return/argument types are C/C/Q/I/C/B, including unsigned-char player
counts and BOOL storage preserving 7 and 255. Native iOS was not measured.

Assertion-enabled shim fixtures pass ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Coverage includes scoped imports, signatures,
saved IMPs, independent objects/properties, truncation boundaries, four workers
performing 128 iterations each, two drained runtimes and 45 isolated rejection
cases. Object counters balance and runtime object/block maps drain. ASan leak
detection was disabled; these checks do not establish absence of all heap
leaks. The broader native regression suite was not rerun.

Drivers, the ARM64 fixture, initializer and GLES runner build successfully.
The focused Vinix ARM64 QEMU fixture passes with child status 0. A fresh full
Fortnite import audit reports **2981 resolved, 23 unresolved strong and 114
unresolved weak imports**, reducing the preceding strong-import count from
24 to 23. Per image, the main executable reports 2138/23/78, EOSSDK 664/0/16
and MarketplaceKitWrapper 179/0/20 (resolved/strong/weak). The audit does not
execute application code. A separate normal launch probe still stops at:

```text
iOS: linking /opt/ios/FortniteClient-IOS-Shipping: iOS: library is not implemented: /System/Library/Frameworks/StoreKit.framework/StoreKit (_OBJC_CLASS_$_SKAdNetwork)
```

Both Fortnite runs exit 1 during linking, before application entry; their
wrappers exit 0 after capturing that failure. Rendering, login and gameplay
remain unverified. SKAdNetwork work remains skipped as requested.

Archive: `/Users/alex/Library/Caches/vinix-ios/gk-match-request-20261025.tar.zst`.
Archive SHA-256: `fdd666127743bc08e8c330b1c752dc13d28008058c098541cc67a6c74f412365`.
Contained manifest SHA-256: `45d0d5a6e7449bd069f5f6ba61adfd77d29658ab0377d9b35814b8f65bfbf594`.

The complete bundle preserves 17 committed source snapshots, both V audit
helpers, 73 selected build input hashes, generated C, host objects/app,
compiled drivers and ARM64 binaries, commands/statuses, and complete boot
media, initramfs, firmware variables, Limine configurations and serial logs
for all three VMs. All 90 files other than the manifest are checksummed.
Local Fortnite assets remain in external storage. Compiler, header and host
library closures are not independently sealed; rebuilding requires the
prepared checkout dependencies. Historical checkers are unchanged.

Compression integrity and original-bundle checks/selftest pass. A fresh
extraction at
`/Users/alex/Library/Caches/vinix-ios/gk-match-request-restored-20261025/gk-match-request-20261025`
also passes full checksums, rejection of missing guest media, an altered host
log and an unmanifested file, restoration of each mutation, and final checking.
The original and restored manifest hashes match.

Reproduce using the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`, `V_RESOURCE_PATH` set to that toolchain
and `V_MACOS_V3_NO_FALLBACK=1`. Build `tests/ios/notification-checks.v`,
`notification-vm.v`, `native-checks.v`, `gk-match-request-input-inventory.v`
and `gk-match-request-evidence.v`. Invoke the notification-checks driver
with a fresh external directory and modes `driver-build`,
`gk-match-request-inspector-build`, `gk-match-request-inspect`,
`gk-match-request-host`, `build-gk-match-request`, `build-init`,
`build-run-ios-gles`, `gk-match-request`, `probe`, `audit`. Run `driver-build`
first to initialize its directories. Fixture generation preserves assertions.
Invoke the inventory helper with repository root, bundle directory and tested
revision; copy both audit helpers into the bundle as `inventory-inputs.v` and
`gk-match-request-evidence.v`. Use checker modes `seal DIR`, `check DIR`,
`selftest DIR` and `hash FILE` to seal, audit and hash it.
