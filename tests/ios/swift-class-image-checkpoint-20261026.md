# Swift class image registration checkpoint — 2026-10-26

Runtime, fixtures and evidence tools revision:
`b14603d995e6efacae0a62ef513531c071954a85`.
Advertising work remains skipped.

Objective-C image registration now admits the bounded, nongeneric Swift root
class shape used by FirebaseCoreInternal.FileStorage. Preflight checks
file-backed ranges, final segment protections, descriptor/cache storage,
metadata extents, ivars and deleted/local vtable entries before registering
that class. Unsupported shapes remain guarded. This does not make the entire
Objective-C image registrar transactional.

The C-ABI metadata initializer is deferred until all modules are bound and
sealed and Objective-C metaclass/selector registration has finished. It runs
with the registry unlocked, completes once across duplicate class lists and
precedes +load without invoking +initialize. Recursive completion is rejected;
incomplete or relocated results poison the class instead of retrying. Runtime
teardown drains the completion arena without reading inaccessible image pages.

Assertion-enabled host fixtures pass ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Cases cover malformed metadata rejection without
writes to that class, final protections, both vtable forms, duplicate lists,
registry reentry, initializer ordering, poisoned results and two runtime
lifetimes. Existing native/shim class updater, initializer and singleton cases
and separate value singleton regressions pass. ASan leak detection was disabled.
Native fixtures use synthetic registered classes; image registration was not
compared with Apple's Mach-O registration path.

The focused Vinix ARM64 QEMU fixture passes with `IOS-CLASS-IMAGE`, child status
0 and `VINIX iOS CLASSUPDATE: PASS`. Offline inspection of the preserved Fortnite
binary finds 269 class entries and one Swift metadata initializer, on
`_TtC20FirebaseCoreInternal11FileStorage`. The full notifications suite and actual
Fortnite launch probe were not rerun. Application entry, rendering, login and
gameplay remain unverified.

Complete evidence bundle:
`/Users/alex/Library/Caches/vinix-ios/swift-class-image-20261026`.
Manifest SHA-256:
`aa2f85e065be2c986ddd3dbad756618f831a42fa55b9c3437d650332c74c50b1`.

The manifest seals all 1204 other files, including 1127 committed source
snapshots, 74 selected build input hashes, evidence helpers, generated C, host
objects/apps, compiled harnesses and ARM64 binaries, command/status logs,
the separate value regression, inspected application binary and complete guest
boot media, initramfs, firmware variables, Limine configuration and serial log.
Selected hashes do not seal compiler, header or host library closures; rebuilding
requires the prepared checkout dependencies. The prebuilt kernel is inventoried;
concurrent kernel edits were not rebuilt. Historical checkers are unchanged.

Checksum verification and selftests pass: missing guest media, an altered host
log and an unmanifested file are rejected, then each mutation is restored and
the complete bundle passes again. No separate archive/restore test was performed.

Reproduce with the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`, `V_RESOURCE_PATH` set there
and `V_MACOS_V3_NO_FALLBACK=1`. Compile notification-checks, notification-vm and
both swift-class-image evidence/inventory tools with
`-nocache -prod -gc none -cc clang`. Run notification-checks modes
`driver-build`, `class-update-host`, `build-class-update`, `build-init` and
`class-update` against a fresh external directory; run `singleton-metadata-host`
separately and preserve it as `value-regression/`. Fixture generation omits
`-prod` to retain assertions. The guest used `VINIX_IOS_VM_GZIP_LEVEL=9`.
Build inspect-swift-class-image with `-enable-globals` and the compat/ios module
path; preserve the inspected binary and its output in `inspection/`. Exact
build/test invocations are recorded in the bundle's command logs. Run the
inventory with repository root, bundle directory and tested revision; copy the
helpers as `inventory-inputs.v` and `swift-class-image-evidence.v`, then use
evidence modes `seal DIR`, `check DIR`, `selftest DIR` and `hash FILE`.
