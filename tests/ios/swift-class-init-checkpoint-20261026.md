# Swift class initializer checkpoint — 2026-10-26

Runtime, fixtures and evidence tools revision:
`653cf126fa0dd13ffcfed114a700a0e107d879f1`.
Advertising work remains skipped.

The bounded `swift_initClassMetadata2` implementation now initializes already
registered, nongeneric Swift root classes with a static vtable. It fills an
implicit SwiftObject superclass, normalizes the Swift class bit and uses the
checked field layout implementation shared with `swift_updateClassMetadata2`.
Unsupported inputs fail before header writes. The entry point does not invoke
the metadata completion callback or Objective-C `+initialize`.

Native Swift and shim fixtures pass for FileStorage-shaped headers: a unique
descriptor, three negative metadata words, a 24-byte address point, a static
vtable, the read-only initializer flag and two pointer fields. Both explicit
and implicit superclasses and initial Swift bits 1 and 2 are covered. Existing
updater layout and header cases still pass. Shim tests also cover rejection
without writes, rejection of changed published layouts, 512 concurrent calls
on read-only image storage and teardown with inaccessible image pages across
two runtime lifetimes.

Assertion-enabled host tests pass ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. The ARM64 ABI probe checks five arguments,
nil dependency metadata and preserved x20/x21; the shim additionally returns
zero dependency state. Native dependency state is unspecified when metadata
is nil. ASan leak detection was disabled; these tests do not establish absence
of all heap leaks.

The first host attempt faulted while querying the instance size of a synthetic
native class without a registered Mach-O image. The fixture now explicitly
realizes native classes after checking initializer layout and Swift-bit
normalization, before querying their allocation size. This fixture step does
not validate image registration. The failed attempt's generated code, objects,
app, diagnostics and command/status logs remain in `failed-host-attempt/`.

The focused Vinix ARM64 QEMU fixture passes with child status 0 and
`VINIX iOS CLASSUPDATE: PASS`. The full notifications suite and actual Fortnite
probe were not rerun. The class singleton completion and image-registration
path remains unimplemented, and Fortnite's existing launch guard remains.
Application entry, rendering, login and gameplay remain unverified.

Complete evidence bundle:
`/Users/alex/Library/Caches/vinix-ios/swift-class-init-20261026`.
Manifest SHA-256:
`a69bd4762a628c66173c82f7fd4127b1f4c88985d71c6e12f63dae2bf4575b79`.

The manifest seals all 1197 other files, including 1125 committed source
snapshots, both V evidence helpers, 74 selected build input hashes, generated
C, host objects/app, compiled harnesses and ARM64 binaries, command/status
logs, the failed host attempt and complete guest boot media, initramfs,
firmware variables, Limine configuration and serial log. Selected input hashes
do not seal compiler, header and host library closures; rebuilding requires
the prepared checkout dependencies. The prebuilt kernel is inventoried;
concurrent kernel edits were not rebuilt. Historical checkers are unchanged.

Checksum checking and selftests pass: missing guest media, a changed host log
and an unmanifested file are rejected, each mutation is restored and the full
bundle passes again. No separate archive or restore test was performed.

Reproduce with the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`, `V_RESOURCE_PATH` set there
and `V_MACOS_V3_NO_FALLBACK=1`. Build notification-checks, notification-vm,
swift-class-init-input-inventory and swift-class-init-evidence V tools with
`-nocache -prod -gc none -cc clang`. Invoke notification-checks with a fresh
external directory and modes `driver-build`, `class-update-host`,
`build-class-update`, `build-init`, `class-update`. Fixture generation omits
`-prod` to retain assertions. The guest used `VINIX_IOS_VM_GZIP_LEVEL=9`.
Run the inventory with repository root, bundle directory and tested revision,
copy the helpers as `inventory-inputs.v` and `swift-class-init-evidence.v`,
then use checker modes `seal DIR`, `check DIR`, `selftest DIR`, `hash FILE`.
