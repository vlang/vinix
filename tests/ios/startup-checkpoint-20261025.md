# Fortnite startup checkpoint — 2026-10-25

Source revision: `c557e77562a7c1baa021ab6c0a80f9dc8c7d581d`.

The evidence snapshot records `57ac6c771ad86202231a4e32971c139250fb85cd`,
which adds an unrelated Android change. Its iOS sources and selected test tools
are identical to the source revision above.

Advertising functionality is skipped. The required `ASIdentifierManager` import
has a minimal compatibility implementation: tracking is disabled and the
advertising identifier is the all-zero UUID. This does not implement an
advertising service.

A fresh Vinix ARM64 QEMU probe passes the previous AdSupport import blocker and
stops during linking at `_OBJC_CLASS_$_UINotificationFeedbackGenerator`. The
runner exits 1, before application entry. `probe: PASS` and
`FORTNITE PROBE COMPLETE` mean the harness captured the result; they do not mean
Fortnite started successfully.

## Validation

The assertion-enabled host fixture passes under ASan+UBSan at `-O0 -g`, both
normally and with `SWIFT_DETERMINISTIC_HASHING=1`. Checks cover disabled tracking,
zero identifiers, the shared cache, 400 concurrent queries, constructor reentry,
receiver pinning, guarded storage, 26 rejection cases and two balanced runtime
lifetimes. Apple metadata inspection measured an 8-byte layout, no ivars and
the three supported method encodings. Leak detection was disabled; object
balance counters do not prove absence of all heap leaks.

The ARM64 GLES runner and guest initializer build successfully. The fresh
Fortnite probe uses those binaries and the preserved socket kernel. A broader
fixture build was interrupted; the full native regression, focused guest
fixture suite and import audits were not rerun. No Fortnite initialization,
rendering, login or gameplay was verified. The previous milestone's audited
results remain in [the resource-request report](bundle-resource-report.md).

## Preserved evidence

Archive: `/Users/alex/Library/Caches/vinix-ios/startup-checkpoint-20261025.tar.zst`.
Archive SHA-256: `c8b18ed22cc310f4edefadd1a587f4b7d052e8c154c0448dd604c06e1769f603`.
Contained manifest SHA-256: `40c96312294107fa5b1c0cf5723bb780c36f8a2c4247ad38ecf9b579494aa75a`.

The complete working evidence directory retains source snapshots, selected
build-input hashes, generated C, host objects and app, compiled tools and ARM64
binaries, command logs/statuses, and the probe's boot image, initramfs, firmware
variables, Limine configuration and serial log. Intermediate outputs from the
interrupted build are retained without claiming they passed. The unfinished
dedicated AdSupport auditor is retained as an intermediate artifact and was
not used to qualify this checkpoint. Historical evidence checkers are unchanged.

The manifest inventories every retained file except itself. The persistent
archive passed its compression integrity check; a fresh extraction reproduced
the manifest byte for byte. This is a startup checkpoint, not a complete native
regression qualification. Host library/compiler-header closures are not
independently sealed; rebuilding requires the prepared dependencies in this
checkout. The archive contains local Fortnite assets and stays in local storage.

From the source revision above, compile `tests/ios/notification-checks.v` and
`tests/ios/notification-vm.v` with the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`, using `-nocache -prod -gc none
-cc clang`. Compile `tests/ios/inspect-user-notifications.v` without `-prod` to
retain assertions. Set `V_RESOURCE_PATH` to that toolchain and
`V_MACOS_V3_NO_FALLBACK=1`, then use a fresh external directory:

```sh
"$VINIX_STARTUP_OUT/notification-checks" adsupport-metadata-inspect "$VINIX_STARTUP_OUT"
"$VINIX_STARTUP_OUT/notification-checks" adsupport-host "$VINIX_STARTUP_OUT"
"$VINIX_STARTUP_OUT/notification-checks" build-init "$VINIX_STARTUP_OUT"
"$VINIX_STARTUP_OUT/notification-checks" build-run-ios-gles "$VINIX_STARTUP_OUT"
"$VINIX_STARTUP_OUT/notification-checks" probe "$VINIX_STARTUP_OUT"
```

The serial log records the actual child process status and linker blocker.
