# Bounded notification attachment values — 2026-10-24

Source revision: `856d5f94b7c55a5ab2ad102a82673d57dfa579d7`.

`UNNotificationAttachment` now resolves through UserNotifications. The bounded
implementation supports the four-argument designated initializer with a live
built-in file or HTTP URL and nil options. Identifier and type are immutable
UTF-8 snapshots, including empty strings and embedded NULs. Nil identifiers
produce distinct UUID strings; nil types become `public.item`. The attachment
retains its URL, and immutable copies retain the same attachment.

Apple measurements establish the 64-byte NSObject layout, seven ivars and
method encodings. The implementation checks allocation provenance and native
body contents. Apple accepts a nil URL by constructing an empty URL; this
bounded implementation rejects nil URLs. Public factories, file import,
options, security scopes, coding, family classification and custom subclasses
remain explicit failures. Notification delivery is not implemented.

## Validation

The shared fixture passed against Apple UserNotifications and the V runtime on
the ARM64 Mac under ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Leak detection was disabled. Checks cover layout,
encodings, defaults, snapshots, URL ownership and immutable copies. Runtime
checks cover reentrant constructors, constructor failures, caller storage,
changed-isa cleanup, associated copies, native overrides, 39 rejection cases
and two drained lifetimes with zero objects and weak registrations. The
production harness now uses explicit failure checks because V production
builds omit assertions.

All ten ARM64 fixtures and runners built. The focused Vinix guest passed the
calendar, calendar-trigger, notification-request, notification-center,
notification-content, notification-sound and notification-attachment fixtures,
including their 41/21/28/31/28/33/39 rejection cases. QEMU 11.1.1 used HVF, four
CPUs and 4096 MiB RAM with the prepared socket-test kernel. The center fixture's
two shutdown warnings about one owned object are intentional: it releases its
retained delegate afterwards and checks that the runtime is drained. This run
did not execute the full native regression suite or establish Swift support.

The fresh Fortnite probe now stops at `_OBJC_CLASS_$_NSCache` in CoreFoundation.
It still exits 1 during linking, before application entry. Executable SHA-256:
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
The import audits did not execute app code:

| Runner / image | Resolved | Unresolved strong | Unresolved weak |
| --- | ---: | ---: | ---: |
| C++/GLES/Text/SQLite: Fortnite | 2,097 | 64 | 78 |
| C++/GLES/Text/SQLite: EOSSDK | 664 | 0 | 16 |
| C++/GLES/Text/SQLite: MarketplaceKitWrapper | 179 | 0 | 20 |
| C++/GLES/Text/SQLite: total | 2,940 | 64 | 114 |
| Static C++/SQLite: Fortnite | 2,086 | 75 | 78 |
| Static C++/SQLite: EOSSDK | 661 | 3 | 16 |
| Static C++/SQLite: MarketplaceKitWrapper | 179 | 0 | 20 |
| Static C++/SQLite: total | 2,926 | 78 | 114 |

These counts establish import resolution only. Fortnite initialization,
rendering, login and gameplay remain unverified.

## Evidence and reproduction

Bundle: `/Users/alex/Library/Caches/vinix-ios/un-attachment-20261024`.
Manifest SHA-256: `184009b421ad2ead547ad3536cbe7a2d761b95106b23e9298db2a028939a4a9d`.

Archive: `/Users/alex/Library/Caches/vinix-ios/un-attachment-20261024.tar.zst`.
Archive SHA-256: `d2f63cb51d356e1bedb0a98370cdfdcb2c8794306d71e60411fba42da9a442e7`.

Sealing, integrity self-tests, archive creation and an independent archive hash
check passed. The complete archive was extracted into a fresh external
directory, and its copied checker passed against every restored file.

The complete bundle retains committed source snapshots, generated C, host
objects and app, ARM64 fixtures and runners, command logs and statuses, and
selected build-input hashes. Each of four VM states retains its boot image,
firmware variables, initramfs, Limine configuration and serial log.
`notification-attachment-evidence.v` requires the complete inventory and exact
result markers, verifies every manifested file's SHA-256 and rejects extra
files. Its self-tests reject missing guest media, a modified inspection log
and an unmanifested file, restoring the bundle afterwards. Historical checkers
remain unchanged. Full compiler-header and host dynamic-library closures are
not independently sealed. Rebuilding requires the prepared dependencies used
by the V tools.

From the source revision above in the repository root, compile the tools with
the prepared frozen compiler into a fresh external directory:

```sh
export V_RESOURCE_PATH="$PWD/build/ios/fortnite/ns-calendar-checks/toolchain"
export V_MACOS_V3_NO_FALLBACK=1
export VINIX_ATTACHMENT_OUT=/external/fresh-notification-attachment
mkdir -p "$VINIX_ATTACHMENT_OUT"
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_ATTACHMENT_OUT/notification-checks" tests/ios/notification-checks.v
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_ATTACHMENT_OUT/notification-vm" tests/ios/notification-vm.v
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_ATTACHMENT_OUT/notification-attachment-evidence" tests/ios/notification-attachment-evidence.v
"$V_RESOURCE_PATH/v" -nocache -gc none -cc clang -o "$VINIX_ATTACHMENT_OUT/inspect-notification-attachment" tests/ios/inspect-notification-attachment.v
"$V_RESOURCE_PATH/v" -nocache -gc none -cc clang -o "$VINIX_ATTACHMENT_OUT/inspect-user-notifications" tests/ios/inspect-user-notifications.v
"$VINIX_ATTACHMENT_OUT/notification-checks" attachment-inspect "$VINIX_ATTACHMENT_OUT"
"$VINIX_ATTACHMENT_OUT/notification-checks" attachment-metadata-inspect "$VINIX_ATTACHMENT_OUT"
"$VINIX_ATTACHMENT_OUT/notification-checks" attachment-host "$VINIX_ATTACHMENT_OUT"
"$VINIX_ATTACHMENT_OUT/notification-checks" build "$VINIX_ATTACHMENT_OUT"
"$VINIX_ATTACHMENT_OUT/notification-checks" notifications "$VINIX_ATTACHMENT_OUT"
"$VINIX_ATTACHMENT_OUT/notification-checks" probe "$VINIX_ATTACHMENT_OUT"
"$VINIX_ATTACHMENT_OUT/notification-checks" audit "$VINIX_ATTACHMENT_OUT"
"$VINIX_ATTACHMENT_OUT/notification-checks" static-audit "$VINIX_ATTACHMENT_OUT"
"$VINIX_ATTACHMENT_OUT/notification-attachment-evidence" snapshot "$VINIX_ATTACHMENT_OUT"
"$VINIX_ATTACHMENT_OUT/notification-attachment-evidence" seal "$VINIX_ATTACHMENT_OUT"
"$VINIX_ATTACHMENT_OUT/notification-attachment-evidence" selftest "$VINIX_ATTACHMENT_OUT"
"$VINIX_ATTACHMENT_OUT/notification-attachment-evidence" archive-zstd "$VINIX_ATTACHMENT_OUT"
```

The wrapper's successful probe/audit status means the guest completed and its
evidence was captured; the child still exits 1. The checker requires that exit
status and exact linker blocker or audit totals. For a sealed bundle, run
`notification-attachment-evidence check DIR` without resealing.

To restore the archive to a fresh external directory:

```sh
mkdir -p /external/restored-attachment
/usr/bin/tar --use-compress-program='/opt/homebrew/bin/zstd --long=31 -d' -xf /Users/alex/Library/Caches/vinix-ios/un-attachment-20261024.tar.zst --strip-components=1 -C /external/restored-attachment
/external/restored-attachment/notification-attachment-evidence check /external/restored-attachment
```
