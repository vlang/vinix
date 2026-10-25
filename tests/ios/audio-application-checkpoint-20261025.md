# Fortnite AVAudioApplication checkpoint — 2026-10-25

Runtime and test source revision:
`0a495eb9d81ed5f7d0e8fd7d439a969f91ad88bf`.

AVFAudio now resolves scoped class and metaclass imports for
`AVAudioApplication`, with a shared singleton, denied record permission,
synchronous false permission completions and an unmuted input query.
Advertising work remains skipped.

A fresh Vinix ARM64 QEMU Fortnite probe passes this import and stops at the
next missing class:

```text
iOS: framework symbol is not implemented: _OBJC_CLASS_$_UIStoryboard
```

The runner exits 1 while linking, before application entry. The probe wrapper
exits 0 because it successfully captured that failure. Fortnite has not started
successfully.

## Validation and limits

Native macOS inspection measures a 24-byte `NSObject` subclass. The observed
private `_impl` ivar starts at offset 8 and `_inputMuted` (`B`) at offset 16.
The runtime does not register those private implementation ivars or reproduce
their native state. Native iOS layout parity was not measured. The supported
method encodings are `@16@0:8` for class `sharedInstance`, `q16@0:8` for instance
`recordPermission`, `B16@0:8` for instance `isInputMuted`, and `v24@0:8@?16`
for class and instance `requestRecordPermissionWithCompletionHandler:`.

Read-only native queries return undetermined permission (`0x756e6474`, `undt`)
and false input mute state on this host. Vinix has no microphone authorization
or capture provider, so its policy returns denied (`0x64656e79`, `deny`) and
invokes permission completion blocks once, synchronously with false and outside
the runtime lock. It reports false input mute state. Microphone injection,
capture, mute setters and permission UI are unsupported. Public construction,
caller storage, custom subclass factories, copying, coding, changing storage
isa and destroying the cached singleton fail explicitly.

The assertion-enabled host fixture passes ASan+UBSan at `-O0 -g`, normally and
with `SWIFT_DETERMINISTIC_HASHING=1`. The focused ARM64 guest fixture passes
with child status 0. Coverage includes scoped imports, singleton ownership,
typed reflection, four concurrent readers with 128 queries each, permission
callback reentry from another thread, two drained runtime cycles and 19
explicit rejection cases. Object and block-reference counters balance; ASan
leak detection was disabled, so this does not establish absence of all heap
leaks. The driver, ARM64 fixture, initializer and GLES runner build successfully.

The broader native regression suite and import audits were not rerun. Swift
support, Fortnite initialization, rendering, login and gameplay remain
unverified. Historical evidence checkers and their requirements are unchanged.

## Preserved evidence

Archive: `/Users/alex/Library/Caches/vinix-ios/audio-application-startup-20261025.tar.zst`.
Archive SHA-256: `88c290f5d4933b92a119f97a859ac78efe5d98aa4b1c38c197610ba7a7a56667`.
Contained manifest SHA-256: `752f33c62a24b08d6e47e606d92b73eae3fa3341f7d73bd5b6d10bb199329c00`.

The bundle contains 14 committed runtime and selected test source files,
native inspection logs and statuses, 72 selected build-input hashes and their
V inventory helper, generated C, host objects and app, compiled tools and
ARM64 binaries, and complete boot images, initramfs archives, firmware
variables, Limine configurations and serial logs for both VMs. Every file
except the manifest itself is checksummed. Local Fortnite assets stay in
external local storage. Compiler, header and host-library closures are not
independently sealed; rebuilding requires the prepared dependencies in this
checkout.

The archive passes its compression integrity check. A fresh extraction at
`/Users/alex/Library/Caches/vinix-ios/audio-application-restored-20261025/audio-application-20261025`
passed `audio-application-evidence.v selftest`: full checksum verification,
rejection of missing guest media, a changed host log and an unmanifested file,
restoration of each mutation, and a final complete check.
The temporary extraction was then removed to recover disk space after
rechecking the archive and manifest hashes; the original bundle and archive
remain preserved.

Compile `tests/ios/notification-checks.v`, `tests/ios/notification-vm.v` and
`tests/ios/native-checks.v` with the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`, using
`-nocache -prod -gc none -cc clang`. Compile
`tests/ios/inspect-audio-application.v` and
`tests/ios/inspect-user-notifications.v` into the same fresh external output
directory with `-nocache -gc none -cc clang` to preserve their assertions.
Set `V_RESOURCE_PATH` to that toolchain and `V_MACOS_V3_NO_FALLBACK=1`.
Run from the repository:

```sh
"$VINIX_AUDIO_OUT/notification-checks" audio-application-inspect "$VINIX_AUDIO_OUT"
"$VINIX_AUDIO_OUT/notification-checks" driver-build "$VINIX_AUDIO_OUT"
"$VINIX_AUDIO_OUT/notification-checks" audio-application-host "$VINIX_AUDIO_OUT"
"$VINIX_AUDIO_OUT/notification-checks" build-audio-application "$VINIX_AUDIO_OUT"
"$VINIX_AUDIO_OUT/notification-checks" build-init "$VINIX_AUDIO_OUT"
"$VINIX_AUDIO_OUT/notification-checks" build-run-ios-gles "$VINIX_AUDIO_OUT"
"$VINIX_AUDIO_OUT/notification-checks" audio-application "$VINIX_AUDIO_OUT"
"$VINIX_AUDIO_OUT/notification-checks" probe "$VINIX_AUDIO_OUT"
```

Host and guest fixture generation preserves assertions. Compile
`tests/ios/audio-input-inventory.v` with the frozen toolchain and
`-nocache -prod -gc none -cc clang`; invoke it with repository root, external
bundle directory and the tested source revision to capture selected inputs.
Copy that helper to `inventory-inputs.v` and
`tests/ios/audio-application-evidence.v` to `audio-application-evidence.v`
inside the bundle. Compile the evidence checker with the same options (it
uses explicit error checks), then seal before archiving and audit a fresh
extraction:

```sh
"$VINIX_AUDIO_CHECKER" seal "$VINIX_AUDIO_OUT"
"$VINIX_AUDIO_CHECKER" selftest "$VINIX_AUDIO_RESTORED/audio-application-20261025"
```
