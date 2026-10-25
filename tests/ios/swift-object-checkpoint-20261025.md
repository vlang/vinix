# Fortnite SwiftObject metadata checkpoint — 2026-10-25

Runtime and test revision: `2635ce4ab1272d7c32c3d753fd9cd3a97b1241a2`.
Advertising work remains skipped.

The shim now resolves the SwiftObject class/metaclass pair, scoped to
`/usr/lib/swift/libswiftCore.dylib`. SwiftObject is an independent root with
16-byte instance metadata, an `isa` ivar and NSObject protocol conformance.
Class reflection and subclass metadata support `class`, `superclass`, `self`,
`isKindOfClass:`, `respondsToSelector:` and `conformsToProtocol:` with explicit
method types. Unsupported selectors are absent from method reflection.
Construction, Objective-C instance operations and storage isa changes fail
explicitly; this does not implement native Swift heap storage or its ABI.

An assertion-enabled ARM64 Mac Catalyst inspector confirms the native root,
metaclass relationships, size, isa ivar, protocol and six method types.
It inspects metadata only; native iOS instance behavior was not measured.

Assertion-enabled host fixtures pass ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Coverage includes scoped imports, independent
root and subclass metadata, reflection, two drained runtimes and 40 isolated
rejection cases covering dispatch, forwarding, direct/caller allocation,
metaclasses, subclasses, saved NSObject allocation IMPs and isa changes.
Object counters and runtime maps drain. ASan leak detection was disabled;
this does not establish absence of all heap leaks. The broader suite was not
rerun. Drivers, the ARM64 fixture, initializer and GLES runner build, and the
focused Vinix ARM64 QEMU fixture passes with child status 0.

A fresh full Fortnite import audit reports **3003 resolved, 1 unresolved
strong and 114 unresolved weak imports**, reducing the preceding strong count
from 3 to 1. Per image, the main executable reports 2160/1/78, EOSSDK 664/0/16
and MarketplaceKitWrapper 179/0/20 (resolved/strong/weak). The audit does not
execute application code. The remaining strong import is SKAdNetwork,
intentionally outside the requested scope. A separate launch probe stops at
that class during linking. Both Fortnite guest runs exit 1 before application
entry; their wrappers exit 0 after capturing that failure. Rendering, login
and gameplay remain unverified.

Complete evidence bundle:
`/Users/alex/Library/Caches/vinix-ios/swift-object-20261025`.
Manifest SHA-256:
`55e3f56b8d8f5fe453b1a6fb858d97ebcd8e9209addd6f666265ff51ecd22600`.

The manifest seals all 88 other files: 15 selected committed source snapshots,
both V audit helpers, 74 selected build input hashes, the native inspector,
generated C, host objects/app, compiled drivers and ARM64 binaries,
commands/statuses, and complete boot media, initramfs, firmware variables,
Limine configurations and serial logs for all three guest runs. The input list
does not seal compiler, header and host library closures; rebuilding requires
the prepared checkout dependencies. The prebuilt guest kernel is inventoried;
concurrent kernel edits were not rebuilt. Historical checkers are unchanged.

Full checksums and selftests pass, including rejection of missing guest media,
an altered host log and an unmanifested file, restoration of each mutation and
final checking. No separate archive or restore test was performed. Helper logs
are in the adjacent `swift-object-tools-20261025` directory.

Reproduce with the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`, `V_RESOURCE_PATH` set there
and `V_MACOS_V3_NO_FALLBACK=1`. Build the notification-checks, notification-vm,
native-checks, swift-object-input-inventory and swift-object-evidence V drivers
with `-nocache -prod -gc none -cc clang`. Invoke notification-checks with a
fresh external directory and modes `driver-build`,
`swift-object-inspector-build`, `swift-object-inspect`, `swift-object-host`,
`build-swift-object`, `build-init`, `build-run-ios-gles`, `swift-object`,
`probe`, `audit`. Fixture and inspector generation omit `-prod` to retain
assertions. The guest runs used `VINIX_IOS_VM_GZIP_LEVEL=9`. Run the input
inventory with repository root, bundle directory and tested revision, copy
the helpers into the bundle as `inventory-inputs.v` and
`swift-object-evidence.v`, then use checker modes `seal DIR`, `check DIR`,
`selftest DIR` and `hash FILE`.
