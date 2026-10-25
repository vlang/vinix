# Fortnite StoreKit purchase metadata checkpoint — 2026-10-25

Runtime and test revision: `b29198b065a87e4e707aacdedb84933bd06509a6`.
Advertising work remains skipped.

The StoreKit shim now resolves class/metaclass imports for SKPaymentQueue,
SKPayment, SKMutablePayment, SKRequest, SKReceiptRefreshRequest and
SKProductsRequest, with their native superclass relationships. The imports are
scoped to StoreKit. Class reflection and subclass metadata support `class`,
`superclass`, `self`, `isKindOfClass:`, `respondsToSelector:` and
`conformsToProtocol:`. Payment, product and receipt operations and object
construction remain unsupported and fail explicitly. Unsupported selectors
are absent from method reflection.

An assertion-enabled ARM64 Mac Catalyst inspector confirms the six native
class/metaclass superclass relationships. It makes no purchases or requests;
native iOS behavior and native instance layouts were not measured.

Assertion-enabled host fixtures pass ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Coverage includes scoped imports, superclass
and subclass metadata, reflection, two drained runtimes and 276 isolated
rejection cases covering dispatch, factories, direct/caller allocation,
metaclasses, subclasses, saved NSObject allocation IMPs and isa changes.
Object counters and runtime maps drain. ASan leak detection was disabled;
this does not establish absence of all heap leaks. The broader suite was not
rerun. Drivers, the ARM64 fixture, initializer and GLES runner build, and the
focused Vinix ARM64 QEMU fixture passes with child status 0.

A fresh full Fortnite import audit reports **3001 resolved, 3 unresolved
strong and 114 unresolved weak imports**, reducing the preceding strong count
from 8 to 3. Per image, the main executable reports 2158/3/78, EOSSDK 664/0/16
and MarketplaceKitWrapper 179/0/20 (resolved/strong/weak). The audit does not
execute application code. The three remaining strong imports are SKAdNetwork
and the SwiftObject class/metaclass pair. A separate launch probe still stops
at the skipped SKAdNetwork class during linking. Both Fortnite guest runs exit
1 before application entry; their wrappers exit 0 after capturing that failure.
Rendering, login and gameplay remain unverified.

Complete evidence bundle:
`/Users/alex/Library/Caches/vinix-ios/storekit-purchase-20261025`.
Manifest SHA-256:
`4c78c123fbd75463c0588e95523c0e0a2fdd30ea21df7367332998e35b248d0c`.

The manifest seals all 88 other files: 15 selected committed source snapshots,
both V audit helpers, 79 selected build input hashes, the native inspector,
generated C, host objects/app, compiled drivers and ARM64 binaries,
commands/statuses, and complete boot media, initramfs, firmware variables,
Limine configurations and serial logs for all three guest runs. The input list
does not seal compiler, header and host library closures; rebuilding requires
the prepared checkout dependencies. The prebuilt guest kernel is inventoried;
concurrent kernel edits were not rebuilt. Historical checkers are unchanged.

Full checksums and selftests pass, including rejection of missing guest media,
an altered host log and an unmanifested file, restoration of each mutation and
final checking. No separate archive or restore test was performed. Helper logs
are in the adjacent `storekit-purchase-tools-20261025` directory.

Reproduce with the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`, `V_RESOURCE_PATH` set there
and `V_MACOS_V3_NO_FALLBACK=1`. Build the notification-checks, notification-vm,
native-checks, storekit-purchase-input-inventory and storekit-purchase-evidence
V drivers with `-nocache -prod -gc none -cc clang`. Invoke notification-checks
with a fresh external directory and modes `driver-build`,
`storekit-purchase-inspector-build`, `storekit-purchase-inspect`,
`storekit-purchase-host`, `build-storekit-purchase`, `build-init`,
`build-run-ios-gles`, `storekit-purchase`, `probe`, `audit`. Fixture and inspector
generation omit `-prod` to retain assertions. The audit used
`VINIX_IOS_VM_GZIP_LEVEL=9`; other runs used the default level 1. Run the input
inventory with repository root, bundle directory and tested revision, copy the
helpers into the bundle as `inventory-inputs.v` and
`storekit-purchase-evidence.v`, then use checker modes `seal DIR`, `check DIR`,
`selftest DIR` and `hash FILE`.
