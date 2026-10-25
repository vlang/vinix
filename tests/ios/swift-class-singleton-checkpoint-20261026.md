# Swift class singleton completion checkpoint — 2026-10-26

Runtime, fixtures and evidence tools revision:
`a020fbfb9fa3cba4c48d4a8f77d2a1a772962ea7`.
Advertising work remains skipped.

The bounded `swift_getSingletonMetadata` implementation now completes already
registered, nongeneric Swift root classes with a static vtable. It validates
the class, descriptor, cache and storage bounds before exposing partial metadata,
installs reference value witnesses and normalizes the Swift class bit before
calling the completion function. Completion receives a four-word zero context
and a null pattern. Successful completion is checked against the published
class layout before release publication to the singleton cache. Values continue
to use the same bounded 64-entry arena.

Native Swift and shim fixtures pass for FileStorage-shaped headers: a unique
descriptor, three negative metadata words, a 24-byte address point, a static
vtable, the read-only initializer flag and two pointer fields. Tests cover all
eight cold/warm request modes, LayoutComplete busy responses, one completion
across eight concurrent readers and preserved x20/x21. Shim cases also cover
nested completion with registry reentry, recursive rejection, preflight failure
without writes, cache alias rejection and malformed/dependency result poisoning
without cache publication. Two runtime lifetimes drain successfully after image
pages become inaccessible. Existing updater and initializer cases still pass.

Assertion-enabled host tests pass ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Separate native/shim value singleton regressions
pass in both modes, including their request/state ABI and concurrent completion
cases. Nil dependency metadata is checked; native dependency state is unspecified
when metadata is nil, while the shim returns zero. ASan leak detection was
disabled; these checks do not establish absence of all heap leaks. Native
fixtures use synthetic registered classes, not a registered Mach-O image.

The focused Vinix ARM64 QEMU fixture passes with the class singleton marker,
child status 0 and `VINIX iOS CLASSUPDATE: PASS`. The full notifications suite
and actual Fortnite probe were not rerun. Swift class image registration remains
guarded in `objc.c.v`; this change completes a prerequisite and does not connect
that image-registration path. Application entry, rendering, login and gameplay
remain unverified.

Complete evidence bundle:
`/Users/alex/Library/Caches/vinix-ios/swift-class-singleton-20261026`.
Manifest SHA-256:
`5386c17dc9cb7824bea63e7d5fe222003f28e22686ee25741b3fec2e2afd56e6`.

The manifest seals all 1199 other files, including 1125 committed source
snapshots, both V evidence helpers, 74 selected build input hashes, generated
C, host objects/apps, compiled harnesses and ARM64 binaries, command/status
logs, the separate value regression and complete guest boot media, initramfs,
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
swift-class-singleton-input-inventory and swift-class-singleton-evidence V tools
with `-nocache -prod -gc none -cc clang`. Invoke notification-checks with a fresh
external directory and modes `driver-build`, `class-update-host`,
`build-class-update`, `build-init`, `class-update`. Run `singleton-metadata-host`
with a separate output directory, then preserve it as `value-regression/` in
the bundle. Fixture generation omits `-prod` to retain assertions. The guest
used `VINIX_IOS_VM_GZIP_LEVEL=9`. Run the inventory with repository root, bundle
directory and tested revision, copy the helpers as `inventory-inputs.v` and
`swift-class-singleton-evidence.v`, then use checker modes `seal DIR`,
`check DIR`, `selftest DIR`, `hash FILE`.
