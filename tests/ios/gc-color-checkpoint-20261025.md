# Fortnite GCColor checkpoint — 2026-10-25

Runtime and test source revision:
`ea3a7d1b11bbc5d4c8752d36db65c227da9e9c64`.

GameController now resolves scoped class and metaclass imports for `GCColor`,
with RGB float initialization and getters, independent copies, descriptions
and measured Objective-C metadata. Advertising work remains skipped.

A fresh Vinix ARM64 QEMU Fortnite probe passes the GCColor import and stops
at the next missing class:

```text
iOS: library is not implemented: /System/Library/Frameworks/GameController.framework/GameController (_OBJC_CLASS_$_GCMouse)
```

The runner exits 1 while linking, before application entry. A completed probe
means the failure was captured; Fortnite has not started successfully.

## Validation and limits

Native macOS inspection measures a 24-byte `NSObject` subclass, with float
ivars `_red`, `_green` and `_blue` at offsets 8, 12 and 16. Initialization and
getters preserve float bits, including negative zero, NaN payloads and
infinities; the runtime fixture also covers subnormal values. Default RGB
values are zero. Copies retain the dynamic class, own independent storage,
copy the stored RGB values without invoking application initializer or getter
overrides, and leave additional subclass storage zeroed. The native inspector
checks this subclass behavior. Native iOS layout parity was not measured.

Mutable copying, coding, private preset initialization and incompatible
storage fail explicitly. Reflection does not advertise these unsupported
operations. Native macOS reports secure coding support; the runtime does not
claim that support. Physical input transport and hardware events remain
unsupported.

The assertion-enabled host fixture passes ASan+UBSan at `-O0 -g`, normally and
with `SWIFT_DETERMINISTIC_HASHING=1`. The focused ARM64 guest fixture passes
with child status 0. GCColor coverage includes scoped class/metaclass imports,
float argument and return ABI, ivars and method signatures, exact float bits,
copy ownership, caller-provided storage, subclass overrides, saved IMP calls,
two drained runtime cycles and eight explicit rejection cases. Existing
controller and gamepad checks also pass, including their ten and 36 rejection
cases. Object and block-reference counters balance; ASan leak detection was
disabled, so this does not prove absence of all heap leaks. The ARM64 fixture,
initializer and GLES runner build successfully.

The broader native regression suite and import audits were not rerun. Swift
support, Fortnite initialization, rendering, login and gameplay remain
unverified. Historical evidence checkers and their requirements are unchanged.

## Preserved evidence

Archive: `/Users/alex/Library/Caches/vinix-ios/gc-color-startup-20261025.tar.zst`.
Archive SHA-256: `5fe909f447bd09c61447a6c012ccacde45eecb58cd28faaf7d94915c93ed0499`.
Contained manifest SHA-256: `a17b20651702a3121a79dd5119ca3cc387a9070a812e6bee6b481c66d34f4566`.

The bundle contains 16 committed runtime and selected test source files,
native inspection logs and statuses, 72 selected build-input hashes and their
V inventory helper, generated C, host objects and app, compiled tools and
ARM64 binaries, and complete boot images, initramfs archives, firmware
variables, Limine configurations and serial logs for both VMs. Every file
except the manifest itself is checksummed. Local Fortnite assets stay in
external local storage. Compiler, header and host-library closures are not
independently sealed; rebuilding requires the prepared dependencies in this
checkout.

The archive passes its compression integrity check. A fresh extraction at
`/Users/alex/Library/Caches/vinix-ios/gc-color-restored-20261025/gc-color-20261025`
reproduces the manifest and passes `gc-color-evidence.v selftest`: full
checksum verification, rejection of missing guest media, a changed host log
and an unmanifested file, restoration of each mutation, and a final complete
check.

Compile `tests/ios/notification-checks.v`, `tests/ios/notification-vm.v` and
`tests/ios/native-checks.v` with the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`, using
`-nocache -prod -gc none -cc clang`. Compile
`tests/ios/inspect-game-controller.v` and `tests/ios/inspect-user-notifications.v`
into the same fresh external output directory with `-nocache -gc none -cc clang`
to preserve their assertions; compile `tests/ios/inspect-gc-color.v` with those
options plus `-enable-globals`. Set `V_RESOURCE_PATH` to that toolchain and
`V_MACOS_V3_NO_FALLBACK=1`. Run from the repository:

```sh
"$VINIX_COLOR_OUT/notification-checks" gc-color-inspect "$VINIX_COLOR_OUT"
"$VINIX_COLOR_OUT/notification-checks" gamepad-inspect "$VINIX_COLOR_OUT"
"$VINIX_COLOR_OUT/notification-checks" game-controller-inspect "$VINIX_COLOR_OUT"
"$VINIX_COLOR_OUT/notification-checks" game-controller-host "$VINIX_COLOR_OUT"
"$VINIX_COLOR_OUT/notification-checks" build-game-controller "$VINIX_COLOR_OUT"
"$VINIX_COLOR_OUT/notification-checks" build-init "$VINIX_COLOR_OUT"
"$VINIX_COLOR_OUT/notification-checks" build-run-ios-gles "$VINIX_COLOR_OUT"
"$VINIX_COLOR_OUT/notification-checks" game-controller "$VINIX_COLOR_OUT"
"$VINIX_COLOR_OUT/notification-checks" probe "$VINIX_COLOR_OUT"
```

Host and guest fixture generation preserves assertions. Compile
`tests/ios/controller-input-inventory.v` with the frozen toolchain and
`-nocache -prod -gc none -cc clang`; invoke it with repository root, external
bundle directory and the tested source revision to capture selected inputs.
Copy that helper to `inventory-inputs.v` and `tests/ios/gc-color-evidence.v` to
`gc-color-evidence.v` inside the bundle. Compile the evidence checker with the
same options (it uses explicit error checks), then seal the bundle before
archiving and audit a fresh extraction:

```sh
"$VINIX_COLOR_CHECKER" seal "$VINIX_COLOR_OUT"
"$VINIX_COLOR_CHECKER" selftest "$VINIX_COLOR_RESTORED/gc-color-20261025"
```
