# Image initializer table checkpoint — 2026-10-26

Runtime, fixture and evidence tools revision:
`4e8481a01ec36d96f79766c9ec566ac856edb185`.
Baseline runtime revision: `a2f82e73dd844e52c5d5cc43eb21c950eb20c7cd`.
Advertising work remains skipped.

Fortnite 42.30.1 has 176,816 entries in `__init_offsets`, exceeding the previous
65,536 per-section limit. Collection now allows at most 262,144 entries across
the whole image, including LC_ROUTINES, initializer pointers/offsets and
terminators. A preflight checks counts, strides and file-backed section ranges
before reading entries. The function array reserves once and is freed on error
under `-gc none`; executable-address/alignment checks and collection order remain
enforced. Terminator registration is not transactional.

Assertion-enabled host tests pass ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`; leak detection was disabled. They cover the
Fortnite count, old/new limit boundaries, read-only offset/pointer tables,
aggregate routines/initializer/terminator bounds, malformed and zero-fill
ranges, executable/alignment rejection and mixed-section ordering. The ARM64
runner builds successfully.

The unchanged Fortnite executable was launched in separate baseline and updated
Vinix ARM64 QEMU guests. The baseline stops at `iOS: invalid initializer section`.
The updated runner passes collection and Swift image metadata registration,
reaches Objective-C `+load`, then stops at
`V panic: iOS: object has no live runtime metadata`. Both guests report process
exit status 1; harness status 0 only means the diagnostic completed as expected.
No application-initializer or application-entry marker appears. Rendering, login
and gameplay remain unverified. `--probe-no-ads` binds SKAdNetwork to nil and
changes application behavior; the ordinary launch still requires that import.
The executable SHA-256 remains
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.

Complete evidence bundle:
`/Users/alex/Library/Caches/vinix-ios/swift-image-probe-20261026`.
Manifest SHA-256:
`f683583427a37205ca0bac5bd35c5e9f682358b8e2b9c1ac0922d1e8ad5358ef`.

The manifest seals all 1193 other files: 1127 committed source snapshots,
74 selected build-input hashes, baseline lifecycle source, helpers, compiled
harnesses, host app/objects, ARM64 runners, generated C, command/status logs and
both guests' complete boot images, initramfs archives, firmware variables,
Limine configurations and serial logs. The initramfs contains the application;
the separately preserved executable is also in the preceding
`swift-class-image-20261026/inspection/` bundle. Selected hashes do not seal
compiler, header or host-library closures. The prebuilt kernel is inventoried;
concurrent kernel edits were not rebuilt. Historical checkers are unchanged.

Checksum verification and selftests pass: missing guest media, an altered host
log and an unmanifested file are rejected, restored and checked again. The
checker requires the baseline failure and the exact next panic, rejecting
additional panics. No separate archive/restore test was performed.

Reproduce with the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`, `V_RESOURCE_PATH` set there
and `V_MACOS_V3_NO_FALLBACK=1`. Compile notification-checks, notification-vm and
the image-initializers evidence/inventory tools with
`-nocache -prod -gc none -cc clang`. Run notification-checks modes
`image-initializers-host`, `build-init`, `build-run-ios-gles` and `probe-no-ads`
against an external directory; fixture generation omits `-prod` to retain
assertions. The probes used `VINIX_IOS_VM_GZIP_LEVEL=9`; preserve the baseline
runner and its separate guest media before the updated run. Exact invocations
are in command logs. Run the inventory with repository root, bundle directory
and tested revision, then evidence modes `seal DIR`, `check DIR`, `selftest DIR`
and `hash FILE`.
