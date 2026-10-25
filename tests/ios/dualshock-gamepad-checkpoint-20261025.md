# Fortnite DualShock gamepad checkpoint — 2026-10-25

Runtime and test source revision:
`cf08445429444642c09a1152b8ca49b26b3e82ae`.

GameController now resolves class and metaclass imports for
`GCPhysicalInputProfile`, `GCExtendedGamepad` and `GCDualShockGamepad`.
Superclass links, inherited metadata and method lookup preserve application
subclass overrides. Advertising work remains skipped.

A fresh Vinix ARM64 QEMU Fortnite probe passes the DualShock import and stops
at the next missing class:

```text
iOS: library is not implemented: /System/Library/Frameworks/GameController.framework/GameController (_OBJC_CLASS_$_GCDualSenseGamepad)
```

The runner exits 1 while linking, before application entry. A completed probe
means the failure was captured; Fortnite has not started successfully.

## Validation and limits

Native macOS inspections and the assertion-enabled host fixture confirm the
exported class/metaclass identities and this hierarchy:

| Class | Parent | Measured instance bytes |
| --- | --- | ---: |
| GCPhysicalInputProfile | NSObject | 680 |
| GCExtendedGamepad | GCPhysicalInputProfile | 872 |
| GCDualShockGamepad | GCExtendedGamepad | 896 |

These are macOS measurements; native iOS layout parity was not measured.
The private physical profile fields, input transport and hardware events are
not implemented. Construction, copying, coding and touchpad access fail
explicitly unless a supported application override handles the operation.

The host fixture passes ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. The focused ARM64 guest fixture passes with
child status 0. Coverage includes scoped class/metaclass imports, superclass
links, inherited sizes, honest reflection and method signatures, subclass
overrides, two drained runtime cycles and 27 explicit rejection cases across
the three classes. The existing controller discovery checks and their ten
rejection cases also pass. Object and block-reference counters balance;
ASan leak detection was disabled, so this does not prove absence of all heap
leaks. The ARM64 fixture, initializer and GLES runner build successfully.

The broader native regression suite and import audits were not rerun. Swift
support, Fortnite initialization, rendering, login and gameplay remain
unverified. Historical evidence checkers and their requirements are unchanged.

## Preserved evidence

Archive: `/Users/alex/Library/Caches/vinix-ios/dualshock-gamepad-startup-20261025.tar.zst`.
Archive SHA-256: `ea897756c4ecea3c0047999c690dd774fb75d96429fc1c09a2bb31c2de88b627`.
Contained manifest SHA-256: `cfd394bb7fbe3a05a920c64b1eabc70032867de69690b7d6529ddec6df5055e7`.

The bundle contains committed runtime and selected test source, native
inspection logs and statuses, 72 selected build-input hashes and their V
inventory helper, generated C, host objects and app, compiled tools and ARM64
binaries, and complete boot images, initramfs archives, firmware variables,
Limine configurations and serial logs for both VMs. Every file except the
manifest itself is checksummed. Local Fortnite assets stay in external local
storage. Compiler, header and host-library closures are not independently
sealed; rebuilding requires the prepared dependencies in this checkout.

The archive passes its compression integrity check. A fresh extraction
reproduces the manifest and passes `dualshock-gamepad-evidence.v selftest`:
full checksum verification, rejection of missing guest media, a changed host
log and an unmanifested file, restoration of each mutation, and a final
complete check.

Compile `tests/ios/notification-checks.v`, `tests/ios/notification-vm.v` and
`tests/ios/native-checks.v` with the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`, using
`-nocache -prod -gc none -cc clang`. Compile
`tests/ios/inspect-game-controller.v` and `tests/ios/inspect-user-notifications.v`
into the same fresh external output directory with `-nocache -gc none -cc clang`
to preserve their assertions. Set `V_RESOURCE_PATH` to that toolchain and
`V_MACOS_V3_NO_FALLBACK=1`. Run from the repository:

```sh
"$VINIX_GAMEPAD_OUT/notification-checks" gamepad-inspect "$VINIX_GAMEPAD_OUT"
"$VINIX_GAMEPAD_OUT/notification-checks" game-controller-inspect "$VINIX_GAMEPAD_OUT"
"$VINIX_GAMEPAD_OUT/notification-checks" game-controller-host "$VINIX_GAMEPAD_OUT"
"$VINIX_GAMEPAD_OUT/notification-checks" build-game-controller "$VINIX_GAMEPAD_OUT"
"$VINIX_GAMEPAD_OUT/notification-checks" build-init "$VINIX_GAMEPAD_OUT"
"$VINIX_GAMEPAD_OUT/notification-checks" build-run-ios-gles "$VINIX_GAMEPAD_OUT"
"$VINIX_GAMEPAD_OUT/notification-checks" game-controller "$VINIX_GAMEPAD_OUT"
"$VINIX_GAMEPAD_OUT/notification-checks" probe "$VINIX_GAMEPAD_OUT"
```

Host and guest fixture generation preserves assertions. Compile
`tests/ios/controller-input-inventory.v` with the frozen toolchain and
`-nocache -prod -gc none -cc clang`; invoke it with repository root, external
bundle directory and the tested source revision to capture selected inputs.
Compile `tests/ios/dualshock-gamepad-evidence.v` with the same options (it uses
explicit error checks), then audit a fresh extraction:

```sh
"$VINIX_GAMEPAD_CHECKER" check "$VINIX_GAMEPAD_RESTORED/dualshock-gamepad-20261025"
"$VINIX_GAMEPAD_CHECKER" selftest "$VINIX_GAMEPAD_RESTORED/dualshock-gamepad-20261025"
```
