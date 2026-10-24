# Bounded ordinary notification sounds — 2026-10-24

Source revision: `a77d44104a7510c35b7718a37892fb6790228698`.

`UNNotificationSound` now resolves through UserNotifications. The bounded
implementation supports `defaultSound`, `soundNamed:`, immutable copies and
ordinary sound values retained by notification content and request snapshots.
Named sounds take immutable UTF-8 snapshots, including empty strings; nil names
produce valid sound objects without a filename. Default sound construction
produces a fresh value each time. Copies retain the same immutable object.

Native Apple measurements establish the 104-byte NSObject layout, 15 ivars,
method encodings, alert type 17, nil optional properties and zero scalar
defaults. The implementation validates owned storage and its native body.
Critical alerts, ringtones, playback, coding, custom subclasses and private
factories remain explicit failures. Notification delivery is not implemented.

## Validation

The shared fixture passed against Apple UserNotifications and the V runtime on
the ARM64 Mac under ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Leak detection was disabled. Checks cover native
layout, encodings, defaults, nil names, UTF-8 snapshots, immutable copies and
content/request ownership. Runtime checks cover constructor lock handoff and
failure cleanup, caller-storage guards, changed-isa cleanup, associated copies,
native override precedence, 33 rejection cases and two drained lifetimes with
zero remaining objects and weak registrations. The runners reject assertion
failure output even when a fixture exits zero.

All nine ARM64 fixtures and runners built. The focused Vinix ARM64 guest passed
the calendar, calendar-trigger, notification-request, notification-center,
notification-content and notification-sound fixtures, including their
41/21/28/31/28/33 rejection cases. QEMU 11.1.1 used HVF, four CPUs and 4096 MiB RAM
with the prepared socket-test kernel. The center fixture's two shutdown
warnings about one owned object are intentional: it releases its retained
delegate afterwards and checks that the runtime is drained. This run did not
execute the full native regression suite or establish Swift support.

The fresh Fortnite probe now stops at
`_OBJC_CLASS_$_UNNotificationAttachment` in UserNotifications. It still exits 1
during linking, before application entry. Executable SHA-256:
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
The import audits did not execute app code:

| Runner / image | Resolved | Unresolved strong | Unresolved weak |
| --- | ---: | ---: | ---: |
| C++/GLES/Text/SQLite: Fortnite | 2,096 | 65 | 78 |
| C++/GLES/Text/SQLite: EOSSDK | 664 | 0 | 16 |
| C++/GLES/Text/SQLite: MarketplaceKitWrapper | 179 | 0 | 20 |
| C++/GLES/Text/SQLite: total | 2,939 | 65 | 114 |
| Static C++/SQLite: Fortnite | 2,085 | 76 | 78 |
| Static C++/SQLite: EOSSDK | 661 | 3 | 16 |
| Static C++/SQLite: MarketplaceKitWrapper | 179 | 0 | 20 |
| Static C++/SQLite: total | 2,925 | 79 | 114 |

These counts establish import resolution only. Fortnite initialization,
rendering, login and gameplay remain unverified.

## Evidence and reproduction

Bundle: `/Users/alex/Library/Caches/vinix-ios/un-sound-20261024`.
Manifest: `manifest.sha256` inside the bundle. Manifest SHA-256:
`491fb42720611379bd69d1314dbaa02a271f1bd81fd61a0a0c05f3ca7ee1248f`.

Archive: `/Users/alex/Library/Caches/vinix-ios/un-sound-20261024.tar.zst`.
Archive SHA-256:
`be7d5b6e6ff1605d03cb3939846d5b28536ab78260163bd9e48bc6a5c66c8a16`.

Sealing, integrity self-tests and archive creation passed. An independent
SHA-256 check passed after copying the archive to persistent storage. The
complete archive was extracted there to the bundle path above, and its copied
checker passed against every restored file. The restored manifest's SHA-256
also matches the value above.

The complete bundle retains committed source snapshots, generated C, host
objects and app, ARM64 fixtures and runners, command logs and statuses, and
selected build-input hashes. Each of four VM states retains its boot image,
firmware variables, initramfs, Limine configuration and serial log.
`notification-sound-evidence.v` requires the complete inventory and exact
result markers, verifies every manifested file's SHA-256 and rejects extra
files. Its integrity self-tests reject missing guest media, a modified
inspection log and an unmanifested file, restoring the bundle afterwards.
Historical notification checkers remain unchanged. Full compiler-header and
host dynamic-library closures are not independently sealed. Rebuilding requires
the prepared dependencies referenced by the V tools.

From the source revision above in the repository root, use a fresh external
output directory and the prepared frozen compiler. The recorded run used
`/Volumes/vinix-un-sound-20261024`; do not overwrite a sealed bundle.

```sh
export V_RESOURCE_PATH="$PWD/build/ios/fortnite/ns-calendar-checks/toolchain"
export V_MACOS_V3_NO_FALLBACK=1
export VINIX_NOTIFICATION_OUT=/external/fresh-notification-sound
mkdir -p "$VINIX_NOTIFICATION_OUT"
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_NOTIFICATION_OUT/notification-checks" tests/ios/notification-checks.v
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_NOTIFICATION_OUT/notification-vm" tests/ios/notification-vm.v
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_NOTIFICATION_OUT/notification-sound-evidence" tests/ios/notification-sound-evidence.v
"$V_RESOURCE_PATH/v" -nocache -gc none -cc clang -o "$VINIX_NOTIFICATION_OUT/inspect-notification-sound" tests/ios/inspect-notification-sound.v
"$V_RESOURCE_PATH/v" -nocache -gc none -cc clang -o "$VINIX_NOTIFICATION_OUT/inspect-user-notifications" tests/ios/inspect-user-notifications.v
"$VINIX_NOTIFICATION_OUT/notification-checks" sound-inspect "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-checks" sound-metadata-inspect "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-checks" sound-host "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-checks" build "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-checks" notifications "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-checks" probe "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-checks" audit "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-checks" static-audit "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-sound-evidence" snapshot "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-sound-evidence" seal "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-sound-evidence" selftest "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-sound-evidence" archive-zstd "$VINIX_NOTIFICATION_OUT"
```

The wrapper's successful probe/audit status means the guest completed and its
evidence was captured; the child still exits 1. The checker requires that status
and exact linker blocker or audit totals. For a sealed bundle, run
`notification-sound-evidence check DIR` without resealing.

To restore the recorded archive to a fresh external directory, stripping its
`un-sound-20261024` top-level directory:

```sh
mkdir -p /external/restored-sound
/usr/bin/tar --use-compress-program='/opt/homebrew/bin/zstd --long=31 -d' -xf /Users/alex/Library/Caches/vinix-ios/un-sound-20261024.tar.zst --strip-components=1 -C /external/restored-sound
/external/restored-sound/notification-sound-evidence check /external/restored-sound
```
