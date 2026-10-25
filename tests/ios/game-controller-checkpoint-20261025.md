# Fortnite controller discovery checkpoint — 2026-10-25

Runtime and test source revision:
`c9cefedd783b38b9d5a5ff598443cdb79ac944eb`.

The shim now imports `GCController` through GameController. `controllers`
returns a shared immutable empty array, `current` returns nil, and the
background-event monitoring flag supports synchronized reads and writes.
The three controller notification constants have immutable storage and resolve
only through GameController. Advertising work remains skipped.

A fresh Vinix ARM64 QEMU Fortnite probe passes the controller class import and
stops at the next missing library/class:

```text
iOS: library is not implemented: /System/Library/Frameworks/GameController.framework/GameController (_OBJC_CLASS_$_GCDualShockGamepad)
```

The runner exits 1 during linking, before application entry. The completed
probe means the failure was captured; Fortnite has not started successfully.

## Validation and limits

Native macOS GameController inspections measure a 232-byte class with NSObject
as its parent, the four supported class-method encodings, empty discovery, a
nil current controller, background-flag round trips and three notification
values. Native iOS layout parity was not measured. The measured private
controller fields and physical input profiles are not implemented.

The assertion-enabled host fixture passes ASan+UBSan at `-O0 -g`, normally and
with `SWIFT_DETERMINISTIC_HASHING=1`. The focused ARM64 guest fixture passes
with child status 0. The ARM64 initializer and GLES runner also build.
Coverage includes scoped imports, typed methods, reflection and method
signatures, BOOL arguments, immutable array identity, notification constants,
four concurrent readers, inherited state, subclass overrides, a saved base IMP
and two drained runtime cycles. Ten rejection cases cover construction,
caller storage, subclass construction, copying, coding support, factories and
wireless discovery. Object and block-reference counters balance; ASan leak
detection was disabled, so this does not prove absence of all heap leaks.

Controller construction, physical profiles, copying, coding, factories and
wireless discovery remain unsupported and fail explicitly unless a supported
application override handles the operation. This checkpoint does not implement
controller input transport or hardware events.

The broader native regression suite and import audits were not rerun. Swift
support, Fortnite initialization, rendering, login and gameplay remain
unverified. Historical evidence checkers and their requirements are unchanged.

## Preserved evidence

Archive: `/Users/alex/Library/Caches/vinix-ios/game-controller-startup-20261025.tar.zst`.
Archive SHA-256: `88a926298a5ff0c64016eebf6092fbdb1945d10ce8cc8666dee826df2a5003db`.
Contained manifest SHA-256: `0f11329c347b927da362574a816222b69669fcb30fb7be36a3d6bedf9b3f3a16`.

The bundle contains the committed runtime and selected test source, native
inspection logs and statuses, selected build-input hashes and their V inventory
helper, generated C, host objects and app, compiled tools and ARM64 binaries,
and complete boot images, initramfs archives, firmware variables, Limine
configurations and serial logs for both VMs. Every file except the manifest
itself is checksummed. The archive contains local Fortnite assets and stays in
local storage. Compiler, header and host-library closures are not independently
sealed; rebuilding requires the prepared dependencies in this checkout.

The archive passed its compression integrity check. A fresh extraction
reproduced the manifest and passed `game-controller-evidence.v selftest`: full
checksum verification, rejection of missing guest media, a changed host log
and an unmanifested file, restoration of each mutation, and a final complete
check.

Compile `tests/ios/notification-checks.v`, `tests/ios/notification-vm.v` and
`tests/ios/native-checks.v` with the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`, using
`-nocache -prod -gc none -cc clang`. Compile
`tests/ios/inspect-game-controller.v` and `tests/ios/inspect-user-notifications.v`
into the same fresh external output directory with `-nocache -gc none -cc clang`
to preserve their assertions. Set `V_RESOURCE_PATH` to that toolchain and
`V_MACOS_V3_NO_FALLBACK=1`. Run from the repository:

```sh
"$VINIX_CONTROLLER_OUT/notification-checks" game-controller-inspect "$VINIX_CONTROLLER_OUT"
"$VINIX_CONTROLLER_OUT/notification-checks" game-controller-host "$VINIX_CONTROLLER_OUT"
"$VINIX_CONTROLLER_OUT/notification-checks" build-game-controller "$VINIX_CONTROLLER_OUT"
"$VINIX_CONTROLLER_OUT/notification-checks" build-init "$VINIX_CONTROLLER_OUT"
"$VINIX_CONTROLLER_OUT/notification-checks" build-run-ios-gles "$VINIX_CONTROLLER_OUT"
"$VINIX_CONTROLLER_OUT/notification-checks" game-controller "$VINIX_CONTROLLER_OUT"
"$VINIX_CONTROLLER_OUT/notification-checks" probe "$VINIX_CONTROLLER_OUT"
```

Host and guest fixture generation preserves assertions. To audit a fresh
extraction, compile `tests/ios/game-controller-evidence.v` with the frozen
toolchain using `-nocache -prod -gc none -cc clang`, then run (the checker uses
explicit error checks):

```sh
"$VINIX_CONTROLLER_CHECKER" check "$VINIX_CONTROLLER_RESTORED/game-controller-20261025"
"$VINIX_CONTROLLER_CHECKER" selftest "$VINIX_CONTROLLER_RESTORED/game-controller-20261025"
```
