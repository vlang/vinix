# Fortnite GCMouse checkpoint — 2026-10-25

Runtime and test source revision:
`59b05eb2a05acc4a35c89c06ecc9e233678b7d08`.

GameController now resolves scoped class and metaclass imports for `GCMouse`,
with immutable empty discovery, a nil current mouse, four notification values
and measured Objective-C metadata. Advertising work remains skipped.

A fresh Vinix ARM64 QEMU Fortnite probe passes the GCMouse import and stops
at the next missing class:

```text
iOS: library is not implemented: /System/Library/Frameworks/AVFAudio.framework/AVFAudio (_OBJC_CLASS_$_AVAudioApplication)
```

The runner exits 1 while linking, before application entry. A completed probe
means the failure was captured; Fortnite has not started successfully.

## Validation and limits

Native macOS inspection measures a 40-byte `NSObject` subclass. Its ivars are
`_creationSequence` (`I`, offset 8), `_vendorName` (`@"NSString"`, offset 16),
`_handlerQueue` (`@"NSObject<OS_dispatch_queue>"`, offset 24) and `_mouseInput`
(`@"GCMouseInput"`, offset 32). Class methods `mice` and `current` have encoding
`@16@0:8`. On the tested host, discovery is empty and the current mouse is nil.
All four notification NSString values equal their exported names. Native iOS
layout parity was not measured.

The runtime has no GameController mouse transport. It returns the immutable
empty array and nil current mouse, with notification values in read-only
storage. Physical devices and events are unsupported. Construction, including
caller-provided storage and subclasses, copying, coding and mouse input access
fail explicitly. Reflection does not advertise unsupported operations.

The assertion-enabled host fixture passes ASan+UBSan at `-O0 -g`, normally and
with `SWIFT_DETERMINISTIC_HASHING=1`. The focused ARM64 guest fixture passes
with child status 0. Mouse coverage includes scoped class/metaclass and global
imports, class/instance method distinctions, typed ivars and signatures,
immutable empty discovery, four constants, four concurrent readers, inherited
discovery, subclass overrides, saved IMP calls, two drained runtime cycles and
nine explicit rejection cases. Existing controller, gamepad and GCColor checks
also pass, including their ten, 36 and eight rejection cases. Object and
block-reference counters balance; ASan leak detection was disabled, so this
does not prove absence of all heap leaks. The ARM64 fixture, initializer and
GLES runner build successfully.

The broader native regression suite and import audits were not rerun. Swift
support, Fortnite initialization, rendering, login and gameplay remain
unverified. Historical evidence checkers and their requirements are unchanged.

## Preserved evidence

Archive: `/Users/alex/Library/Caches/vinix-ios/gc-mouse-startup-20261025.tar.zst`.
Archive SHA-256: `b8fad3f30ddb47a91f7d58afaa107c300318139c11ceac6ac6cf6465d1ec37ef`.
Contained manifest SHA-256: `224daa71fc4a7a788f031f81e29a35bc44e654af5a115503ecbc886c0420980d`.

The bundle contains 17 committed runtime and selected test source files,
native inspection logs and statuses, 72 selected build-input hashes and their
V inventory helper, generated C, host objects and app, compiled tools and
ARM64 binaries, and complete boot images, initramfs archives, firmware
variables, Limine configurations and serial logs for both VMs. Every file
except the manifest itself is checksummed. Local Fortnite assets stay in
external local storage. Compiler, header and host-library closures are not
independently sealed; rebuilding requires the prepared dependencies in this
checkout.

The archive passes its compression integrity check. A fresh extraction at
`/Users/alex/Library/Caches/vinix-ios/gc-mouse-restored-20261025/gc-mouse-20261025`
reproduces the manifest and passes `gc-mouse-evidence.v selftest`: full
checksum verification, rejection of missing guest media, a changed host log
and an unmanifested file, restoration of each mutation, and a final complete
check.

Compile `tests/ios/notification-checks.v`, `tests/ios/notification-vm.v` and
`tests/ios/native-checks.v` with the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`, using
`-nocache -prod -gc none -cc clang`. Compile
`tests/ios/inspect-game-controller.v`, `tests/ios/inspect-gc-mouse.v` and
`tests/ios/inspect-user-notifications.v` into the same fresh external output
directory with `-nocache -gc none -cc clang` to preserve their assertions;
compile `tests/ios/inspect-gc-color.v` with those options plus `-enable-globals`.
Set `V_RESOURCE_PATH` to that toolchain and `V_MACOS_V3_NO_FALLBACK=1`.
Run from the repository:

```sh
"$VINIX_MOUSE_OUT/notification-checks" gc-mouse-inspect "$VINIX_MOUSE_OUT"
"$VINIX_MOUSE_OUT/notification-checks" gc-color-inspect "$VINIX_MOUSE_OUT"
"$VINIX_MOUSE_OUT/notification-checks" gamepad-inspect "$VINIX_MOUSE_OUT"
"$VINIX_MOUSE_OUT/notification-checks" game-controller-inspect "$VINIX_MOUSE_OUT"
"$VINIX_MOUSE_OUT/notification-checks" game-controller-host "$VINIX_MOUSE_OUT"
"$VINIX_MOUSE_OUT/notification-checks" build-game-controller "$VINIX_MOUSE_OUT"
"$VINIX_MOUSE_OUT/notification-checks" build-init "$VINIX_MOUSE_OUT"
"$VINIX_MOUSE_OUT/notification-checks" build-run-ios-gles "$VINIX_MOUSE_OUT"
"$VINIX_MOUSE_OUT/notification-checks" game-controller "$VINIX_MOUSE_OUT"
"$VINIX_MOUSE_OUT/notification-checks" probe "$VINIX_MOUSE_OUT"
```

Host and guest fixture generation preserves assertions. Compile
`tests/ios/controller-input-inventory.v` with the frozen toolchain and
`-nocache -prod -gc none -cc clang`; invoke it with repository root, external
bundle directory and the tested source revision to capture selected inputs.
Copy that helper to `inventory-inputs.v` and `tests/ios/gc-mouse-evidence.v` to
`gc-mouse-evidence.v` inside the bundle. Compile the evidence checker with the
same options (it uses explicit error checks), then seal the bundle before
archiving and audit a fresh extraction:

```sh
"$VINIX_MOUSE_CHECKER" seal "$VINIX_MOUSE_OUT"
"$VINIX_MOUSE_CHECKER" selftest "$VINIX_MOUSE_RESTORED/gc-mouse-20261025"
```
