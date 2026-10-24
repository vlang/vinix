# Bounded user notification center — 2026-10-24

Source revision: `bdb9b81703656ca7885cb87ece2e967ed92d1795`.

`UNUserNotificationCenter` now resolves through the UserNotifications framework.
Its supported surface is a cached singleton, a zeroing weak delegate and a
false `supportsContentExtensions` capability. Apple SDK 26.5 inspection measured
a 40-byte NSObject layout with delegate, bundle identifier, queue and private
delegate ivars at offsets 8, 16, 24 and 32. Permission requests, settings,
categories, scheduling, delivery, badges, copying and coding remain explicit
failures. No notification service or completion callbacks are simulated.

## Validation

The shared fixture passed against native Apple UserNotifications and the V
runtime on the ARM64 Mac, under ASan+UBSan at `-O0 -g`, both normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Leak detection was disabled. Checks cover layout,
method encodings, singleton retention, delegate replacement, nil and weak
zeroing, and the getter's autorelease lifetime. Runtime-only checks cover
constructor lock handoff and failed construction followed by retry, cached
access from eight joined worker threads, caller-storage guards, changed-isa
cleanup, native override precedence, 31 rejected cases and two drained runtime
lifetimes. The worker checks are sequential; they do not establish simultaneous
first-construction behavior. The two shutdown warnings about one owned object
are intentional: the fixture holds a delegate across shutdown, then releases it
and asserts zero live objects, object registrations and weak registrations.

The focused Vinix ARM64 guest passed the calendar, calendar-trigger,
notification-request and notification-center fixtures, including their
41/21/28/31 rejection cases. QEMU used HVF, four CPUs and 4096 MiB RAM, with the
prepared socket-test kernel. This run did not execute the full native regression
suite or establish Swift support.

The fresh Fortnite launch probe still exits 1 during linking, before application
entry, at `_OBJC_CLASS_$_UNMutableNotificationContent` in UserNotifications.
The executable SHA-256 is
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
The import audits did not execute app code:

| Runner / image | Resolved | Unresolved strong | Unresolved weak |
| --- | ---: | ---: | ---: |
| C++/GLES/Text/SQLite: Fortnite | 2,094 | 67 | 78 |
| C++/GLES/Text/SQLite: EOSSDK | 664 | 0 | 16 |
| C++/GLES/Text/SQLite: MarketplaceKitWrapper | 179 | 0 | 20 |
| C++/GLES/Text/SQLite: total | 2,937 | 67 | 114 |
| Static C++/SQLite: Fortnite | 2,083 | 78 | 78 |
| Static C++/SQLite: EOSSDK | 661 | 3 | 16 |
| Static C++/SQLite: MarketplaceKitWrapper | 179 | 0 | 20 |
| Static C++/SQLite: total | 2,923 | 81 | 114 |

These counts establish import resolution only. They do not establish working
Fortnite initialization, rendering, login or gameplay.

## Evidence and reproduction

Bundle: `/Users/alex/Library/Caches/vinix-ios/un-center-20261024`.
Manifest: `manifest.sha256` inside the bundle.
Manifest SHA-256:
`6b7f147d627d18d5a3976b3097f122ff86a97aca2a74e181a2a78d4cd3af3bbb`.

Seal, complete-bundle verification and all three integrity self-tests passed.
Compressed archive creation failed with `tar: Write error` on the full host
filesystem (117 MiB free when checked). The failed partial archive was removed;
all source files, guest media and other manifested artifacts remain intact in
the directory above. Archive packaging can be retried when space is available.

The bundle retains source snapshots, generated C, host objects and apps, ARM64
fixtures and runners, command logs and statuses, and selected build-input hashes.
Each of the four VM states retains its boot image, firmware variables,
initramfs, Limine configuration and serial log. `notification-evidence.v`
requires this complete inventory and the exact result markers, and checks every
manifested file's SHA-256. Its self-test rejects missing guest media, a modified
inspection log and an extra unmanifested file, restoring the bundle afterwards.
The full compiler-header and host dynamic-library closures are not independently
sealed. Rebuilding requires the prepared dependencies referenced by the V tools;
this bundle is not a self-contained toolchain distribution.

From this revision in the repository root, use a fresh external output directory
and the prepared frozen compiler. The following commands use the recorded
directory; choose a new directory for a new run rather than replacing this bundle.

```sh
export V_RESOURCE_PATH="$PWD/build/ios/fortnite/ns-calendar-checks/toolchain"
export V_MACOS_V3_NO_FALLBACK=1
export VINIX_NOTIFICATION_OUT=/Users/alex/Library/Caches/vinix-ios/un-center-20261024
mkdir -p "$VINIX_NOTIFICATION_OUT"
"$V_RESOURCE_PATH/v" -nocache -gc none -cc clang -o "$VINIX_NOTIFICATION_OUT/notification-checks" tests/ios/notification-checks.v
"$V_RESOURCE_PATH/v" -nocache -gc none -cc clang -o "$VINIX_NOTIFICATION_OUT/notification-vm" tests/ios/notification-vm.v
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_NOTIFICATION_OUT/notification-evidence" tests/ios/notification-evidence.v
"$V_RESOURCE_PATH/v" -nocache -gc none -cc clang -o "$VINIX_NOTIFICATION_OUT/inspect-user-notifications" tests/ios/inspect-user-notifications.v
"$VINIX_NOTIFICATION_OUT/notification-checks" inspect "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-checks" host "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-checks" build "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-checks" notifications "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-checks" probe "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-checks" audit "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-checks" static-audit "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-evidence" snapshot "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-evidence" seal "$VINIX_NOTIFICATION_OUT"
"$VINIX_NOTIFICATION_OUT/notification-evidence" selftest "$VINIX_NOTIFICATION_OUT"
```

Optional packaging, once sufficient space is available:

```sh
"$VINIX_NOTIFICATION_OUT/notification-evidence" archive "$VINIX_NOTIFICATION_OUT"
```

The wrapper's successful probe/audit status means the guest completed and its
evidence was captured; the child process still exits 1. The evidence checker
requires that status and the exact linker blocker or audit totals. For an
already sealed bundle, run `notification-evidence check DIR` without resealing.
