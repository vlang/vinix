# Swift class updater header checkpoint — 2026-10-26

Runtime, fixtures and harness revision:
`85b7703ac8ac0704a95627e2aa0d2c5418890470`.
Advertising work remains skipped.

The bounded `swift_updateClassMetadata2` implementation now accepts metadata
address points of 16 or 24 bytes, unique class descriptors, the read-only
Swift initializer flag and static vtables. All 16 combinations pass against
native Swift and the shim. The updater preserves negative metadata words and
does not call the metadata initializer or Objective-C `+initialize`.
Descriptor extents and total metadata sizes must agree. Unnormalized Swift
class templates and unsupported descriptor flags remain rejected.

Assertion-enabled host fixtures pass ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. The tests also cover field layout, UInt64
offset vectors and exported cells, ivar publication, invalid input without
writes, unchanged read-only storage, concurrent repeats and owned-copy drain
with inaccessible image pages across two runtime lifetimes. Native ARM64
five-argument ABI checks cover the nil dependency return and preserved
registers. ASan leak detection was disabled; this does not establish absence
of all heap leaks.

The focused Vinix ARM64 QEMU fixture passes with child status 0 and
`VINIX iOS CLASSUPDATE: PASS`. The harness now supports focused host, build
and guest modes and includes the fixture in the full notifications mode.
The first guest attempt exposed a missing initializer dispatch branch and
fell through to the Fortnite probe path. Its failed status, logs and boot
artifacts remain in the bundle; the corrected initializer was rebuilt and
the focused guest run passed. The full notifications suite was not rerun.

This is an updater prerequisite. It does not implement Swift singleton or
class initialization. The existing Fortnite launch guard remains, and the
actual Fortnite probe was not rerun. Application entry, rendering, login
and gameplay remain unverified.

Complete evidence bundle:
`/Users/alex/Library/Caches/vinix-ios/swift-class-update-20261026`.
Manifest SHA-256:
`ff3813563f15fa33536879236d2e6002236286e0a085c4380483434e460285a8`.

The manifest seals all 1179 other files, including 1125 committed source
snapshots, both V evidence helpers, 74 selected build input hashes, generated
C, host objects/app, compiled drivers and ARM64 binaries, command/status
logs, and complete boot media, initramfs, firmware variables, Limine
configurations and serial logs for both guest attempts. Selected input hashes
do not seal compiler, header and host library closures; rebuilding requires
the prepared checkout dependencies. The prebuilt guest kernel is inventoried;
concurrent kernel edits were not rebuilt. Historical checkers are unchanged.

Checksum checking and selftests pass: missing guest media, a changed host log
and an unmanifested file are rejected, each mutation is restored and the full
bundle passes again. No separate archive or restore test was performed.

Reproduce with the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`, `V_RESOURCE_PATH` set there
and `V_MACOS_V3_NO_FALLBACK=1`. Build the notification-checks, notification-vm,
swift-class-update-input-inventory and swift-class-update-evidence V tools
with `-nocache -prod -gc none -cc clang`. Invoke notification-checks with a
fresh external directory and modes `driver-build`, `class-update-host`,
`build-class-update`, `build-init`, `class-update`. Fixture generation omits
`-prod` to retain assertions. The guest used `VINIX_IOS_VM_GZIP_LEVEL=9`.
Run the inventory with repository root, bundle directory and tested revision,
copy the helpers as `inventory-inputs.v` and `swift-class-update-evidence.v`,
then use checker modes `seal DIR`, `check DIR`, `selftest DIR`, `hash FILE`.
