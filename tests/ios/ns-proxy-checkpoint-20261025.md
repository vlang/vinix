# Fortnite NSProxy root metadata checkpoint — 2026-10-25

Runtime and test revision: `4ea62f457a35858d0bbddac8e153b41b3407fa00`.
Advertising work remains skipped.

The Foundation shim now resolves scoped NSProxy class/metaclass imports as an
independent Objective-C root. Its instance size is 8 bytes, with an `isa` ivar
at offset 0 and NSObject protocol conformance. Class reflection and subclass
metadata expose six typed methods: `class`, `superclass`, `self`,
`isKindOfClass:`, `respondsToSelector:` and `conformsToProtocol:`. Construction,
forwarding and concrete proxy storage remain unsupported. Unsupported dispatch,
direct/caller allocation, saved NSObject allocation IMPs and isa changes fail
explicitly; unsupported selectors are absent from method reflection.

The assertion-enabled native ARM64 Mac Catalyst inspector verifies the root
class/metaclass relationships, instance size, ivar, protocol and six method
encodings. It constructs no proxies. Native iOS behavior was not measured.

Assertion-enabled host fixtures pass ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Coverage includes scoped imports, independent
root metadata, subclass metadata, method reflection, two drained runtimes and
40 isolated rejection cases covering dispatch, forwarding, direct/caller
allocation, metaclasses, subclasses, saved NSObject IMPs and isa changes.
Object counters and runtime object maps drain. ASan leak detection was disabled;
this does not establish absence of all heap leaks. The broader suite was not
rerun.

Drivers, the ARM64 fixture, initializer and GLES runner build successfully.
The focused Vinix ARM64 QEMU fixture passes with child status 0. A fresh full
Fortnite import audit reports **2996 resolved, 8 unresolved strong and 114
unresolved weak imports**, reducing the preceding strong-import count from
10 to 8 by resolving the NSProxy class/metaclass pair. Per image, the main
executable reports 2153/8/78, EOSSDK 664/0/16 and MarketplaceKitWrapper 179/0/20
(resolved/strong/weak). The audit does not execute application code. A separate
normal launch probe still stops at:

```text
iOS: linking /opt/ios/FortniteClient-IOS-Shipping: iOS: library is not implemented: /System/Library/Frameworks/StoreKit.framework/StoreKit (_OBJC_CLASS_$_SKAdNetwork)
```

Both Fortnite runs exit 1 during linking, before application entry; their
wrappers exit 0 after capturing that failure. Rendering, login and gameplay
remain unverified. Of the eight strong imports, SKAdNetwork remains skipped as
requested. The other seven are the SKPaymentQueue, SKMutablePayment and
SKReceiptRefreshRequest classes, plus class/metaclass pairs for SKProductsRequest
and SwiftObject.

Archive: `/Users/alex/Library/Caches/vinix-ios/ns-proxy-20261025.tar.zst`.
Archive SHA-256: `0087a8b589ef984bfa67bd29d4721e7b42faa9c952e58697f7798eae6e242757`.
Contained manifest SHA-256: `931c0fb6a76336ececff1e4cf1cdcdebc88bf063f2c58f1f1ce95b0cd5be1b88`.

The complete bundle preserves 15 selected committed source snapshots, both V
audit helpers, 75 selected build input hashes, the native inspector, generated C,
host objects/app, compiled drivers and ARM64 binaries, commands/statuses, and
complete boot media, initramfs, firmware variables, Limine configurations and
serial logs for the focused fixture, launch probe and import audit. All 93 files
other than the manifest are checksummed, including the earlier focused VM run.
Local Fortnite assets remain in external storage. Compiler, header and host
library closures are not independently sealed; rebuilding requires the prepared
checkout dependencies. The prebuilt guest kernel is inventoried; concurrent
kernel edits were not rebuilt. Historical checkers are unchanged.

Compression integrity and original-bundle checks/selftest pass. A fresh
extraction at
`/Users/alex/Library/Caches/vinix-ios/ns-proxy-restored-20261025/ns-proxy-20261025`
also passes full checksums, rejection of missing guest media, an altered host
log and an unmanifested file, restoration of each mutation, and final checking.
The original and restored manifest hashes match.

Reproduce using the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`, `V_RESOURCE_PATH` set to that toolchain
and `V_MACOS_V3_NO_FALLBACK=1`. Build `tests/ios/notification-checks.v`,
`notification-vm.v`, `native-checks.v`, `ns-proxy-input-inventory.v` and
`ns-proxy-evidence.v`. Invoke the notification-checks driver with a fresh
external directory and modes `driver-build`, `ns-proxy-inspector-build`,
`ns-proxy-inspect`, `ns-proxy-host`, `build-ns-proxy`, `build-init`,
`build-run-ios-gles`, `ns-proxy`, `probe`, `audit`. Run `driver-build` first to
initialize its directories. Native inspector and fixture generation omit
`-prod` to preserve assertions. Invoke the inventory helper with repository
root, bundle directory and tested revision; copy both audit helpers into the
bundle as `inventory-inputs.v` and `ns-proxy-evidence.v`. Checker modes are
`seal DIR`, `check DIR`, `selftest DIR` and `hash FILE`.
