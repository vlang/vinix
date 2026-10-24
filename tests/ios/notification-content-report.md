# Bounded user notification content — 2026-10-24

Source revision: `f04e7f6f9635f743dca478ae4c4387f48469bcef`.

`UNNotificationContent` and `UNMutableNotificationContent` now resolve through
UserNotifications. The bounded implementation supports nine string properties,
empty attachments and user-info collections, summary counts, interruption
levels and relevance scores. `UNNotificationRequest` owns an immutable snapshot
of supplied content.

Apple SDK 26.5 inspection measured a 296-byte layout, method encodings, defaults,
nil normalization and copy behavior. In particular, `launchImageName` and
`subtitle` retain mutable inputs, their getters return immutable snapshots, and
copying the content freezes their current values. Other string setters snapshot
their inputs. Relevance scores clamp to [0, 1]; NaN is rejected. Non-nil badge
and sound objects, nonempty collections, custom subclasses, coding, providers
and private service operations remain explicit failures. Notification delivery
is not implemented.

## Validation

The shared fixture passed against native Apple UserNotifications and the V
runtime on the ARM64 Mac under ASan+UBSan at `-O0 -g`, both normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Leak detection was disabled. Checks cover layout,
method encodings, defaults, nil normalization, UTF-8 snapshots, scalar bounds,
copy classes and request ownership. Runtime-only checks cover reentrant
constructors and failed construction, caller-storage guards, changed-isa
cleanup, associated copies, native override precedence, 28 rejected cases and
two drained lifetimes with zero remaining objects and weak registrations.

All eight ARM64 fixtures and runners built. The focused Vinix ARM64 guest passed
the calendar, calendar-trigger, notification-request, notification-center and
notification-content fixtures, including their 41/21/28/31/28 rejection cases.
QEMU 11.1.1 used HVF, four CPUs and 4096 MiB RAM with the prepared socket-test
kernel. The center fixture's two shutdown warnings about one owned object are
intentional: it releases the retained delegate afterwards and checks that the
runtime is drained. This run did not execute the full native regression suite
or establish Swift support.

The fresh Fortnite launch probe now stops at
`_OBJC_CLASS_$_UNNotificationSound` in UserNotifications. It still exits 1 during
linking, before application entry. Executable SHA-256:
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
The import audits did not execute app code:

| Runner / image | Resolved | Unresolved strong | Unresolved weak |
| --- | ---: | ---: | ---: |
| C++/GLES/Text/SQLite: Fortnite | 2,095 | 66 | 78 |
| C++/GLES/Text/SQLite: EOSSDK | 664 | 0 | 16 |
| C++/GLES/Text/SQLite: MarketplaceKitWrapper | 179 | 0 | 20 |
| C++/GLES/Text/SQLite: total | 2,938 | 66 | 114 |
| Static C++/SQLite: Fortnite | 2,084 | 77 | 78 |
| Static C++/SQLite: EOSSDK | 661 | 3 | 16 |
| Static C++/SQLite: MarketplaceKitWrapper | 179 | 0 | 20 |
| Static C++/SQLite: total | 2,924 | 80 | 114 |

These counts establish import resolution only. Working Fortnite initialization,
rendering, login and gameplay remain unverified.

## Evidence and reproduction

Bundle: `/Users/alex/Library/Caches/vinix-ios/un-content-20261024`.
Manifest: `manifest.sha256` inside the bundle. Manifest SHA-256:
`a4d0b224fa9fdf8b88ca16579e5c334ead8c9624a70fed2083b41191fa74c60b`.

Archive: `/Users/alex/Library/Caches/vinix-ios/un-content-20261024.tar.zst`.
Archive SHA-256 (also recorded in its `.sha256` sidecar):
`122829e4682d00b8dd8fcbd24c63f8cf91adcce4346cac01107668930ebc0405`.
Seal, complete-bundle verification, all three integrity self-tests and archive
creation passed. The archive was extracted to temporary storage, and the full
manifest and result check passed on the restored bundle.

The complete bundle retains committed source snapshots, generated C, host
objects and apps, ARM64 fixtures and runners, command logs and statuses, and
selected build-input hashes. Each of the four VM states retains its boot image,
firmware variables, initramfs, Limine configuration and serial log.
`notification-content-evidence.v` requires this complete inventory and the exact
result markers, and checks every manifested file's SHA-256. Its integrity
self-tests reject missing guest media, a modified inspection log and an extra
unmanifested file, restoring the bundle afterwards. The historical center
checker is unchanged. The full compiler-header and host dynamic-library
closures are not independently sealed. Rebuilding requires the prepared
dependencies referenced by the V tools; this bundle is not a self-contained
toolchain distribution.

From the source revision above in the repository root, use a fresh external
output directory and the prepared frozen compiler. These commands use the
recorded directory; choose a new directory for a new run rather than replacing
the sealed bundle.

```sh
export V_RESOURCE_PATH="$PWD/build/ios/fortnite/ns-calendar-checks/toolchain"
export V_MACOS_V3_NO_FALLBACK=1
export VINIX_NOTIFICATION_OUT=/Users/alex/Library/Caches/vinix-ios/un-content-20261024
mkdir -p "$VINIX_NOTIFICATION_OUT"
"$V_RESOURCE_PATH/v" -nocache -gc none -cc clang -o "$VINIX_NOTIFICATION_OUT/notification-checks" tests/ios/notification-checks.v
"$V_RESOURCE_PATH/v" -nocache -gc none -cc clang -o "$VINIX_NOTIFICATION_OUT/notification-vm" tests/ios/notification-vm.v
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_NOTIFICATION_OUT/notification-content-evidence" tests/ios/notification-content-evidence.v
"$V_RESOURCE_PATH/v" -nocache -gc none -cc clang -o "$VINIX_NOTIFICATION_OUT/inspect-notification-content" tests/ios/inspect-notification-content.v
"$VINIX_NOTIFICATION_OUT/notification-checks" content-inspect "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-checks" content-host "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-checks" build "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-checks" notifications "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-checks" probe "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-checks" audit "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-checks" static-audit "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-content-evidence" snapshot "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-content-evidence" seal "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-content-evidence" selftest "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-content-evidence" archive-zstd "$VINIX_NOTIFICATION_OUT"
```

The wrapper's successful probe/audit status means the guest completed and its
evidence was captured; the child process still exits 1. The evidence checker
requires that status and the exact linker blocker or audit totals. For an
already sealed bundle, run `notification-content-evidence check DIR` without
resealing.

To restore the archive to an existing external directory:

```sh
/usr/bin/tar --use-compress-program='/opt/homebrew/bin/zstd --long=31 -d' -xf "$VINIX_NOTIFICATION_OUT.tar.zst" -C /external/restore
"$VINIX_NOTIFICATION_OUT/notification-content-evidence" check /external/restore/un-content-20261024
```
