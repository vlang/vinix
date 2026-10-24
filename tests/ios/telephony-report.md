# No-service CoreTelephony network information — 2026-10-24

Source revision: `189a147883381ef2fd9174aa5eace92a37da6cc4`.

`CTTelephonyNetworkInfo` now resolves through CoreTelephony with Apple's measured
40-byte NSObject layout, four ivars and method encodings for twelve supported
selectors. It reports no cellular service: carrier, radio and data-service
values are nil, and the two service maps are immutable empty dictionaries.
The delegate is zeroing weak; both notifier properties copy blocks and emit no
service-change events. Coding, copying, custom subclasses and unsupported
private APIs fail explicitly.

Runtime checks validate allocation provenance and native body contents under
the runtime lock. Block copy/dispose callbacks run outside that lock, with an
operation pin preventing destruction during a setter. Cleanup follows the
original allocation class even after an object's isa changes.

## Validation

The shared fixture passed against Apple CoreTelephony and the V runtime on the
ARM64 Mac under ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Assertions remained enabled; leak detection was
disabled. Checks cover layout, encodings, defaults, weak delegate clearing,
copied stack blocks, self-assignment, clearing, autorelease-pool boundaries and
manual notifier invocation. Runtime checks cover four concurrent delegate
workers, reentrant block copy/dispose callbacks, caller-supplied storage,
changed-isa cleanup, framework boundaries and 19 rejection cases. Two drained
lifetimes finish with zero owned Objective-C objects, weak registrations and
tracked block references; these counters do not establish absence of all heap
leaks.

All twelve ARM64 fixtures and runners built. The focused Vinix guest passed
telephony, cache, calendar, calendar-trigger, notification-request,
notification-center, notification-content, notification-sound and
notification-attachment fixtures, including their
19/31/41/21/28/31/28/33/39 rejection cases. QEMU 11.1.1 used HVF, four CPUs and
4096 MiB RAM with the prepared socket-test kernel. The center fixture's two
shutdown warnings about one owned object are intentional: it releases its
retained delegate afterwards and checks that the runtime is drained. This run
did not execute the full native regression suite or establish Swift support.

The fresh Fortnite probe resolves the telephony class and stops at
`_OBJC_CLASS_$_NSURLCredential`. It still exits 1 during linking, before
application entry. Executable SHA-256:
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
The import audits did not execute app code:

| Runner / image | Resolved | Unresolved strong | Unresolved weak |
| --- | ---: | ---: | ---: |
| C++/GLES/Text/SQLite: Fortnite | 2,099 | 62 | 78 |
| C++/GLES/Text/SQLite: EOSSDK | 664 | 0 | 16 |
| C++/GLES/Text/SQLite: MarketplaceKitWrapper | 179 | 0 | 20 |
| C++/GLES/Text/SQLite: total | 2,942 | 62 | 114 |
| Static C++/SQLite: Fortnite | 2,088 | 73 | 78 |
| Static C++/SQLite: EOSSDK | 661 | 3 | 16 |
| Static C++/SQLite: MarketplaceKitWrapper | 179 | 0 | 20 |
| Static C++/SQLite: total | 2,928 | 76 | 114 |

These counts establish import resolution only, not a percentage of game
completion. Fortnite initialization, rendering, login and gameplay remain
unverified.

## Evidence and reproduction

Bundle: `/Users/alex/Library/Caches/vinix-ios/coretelephony-20261024`.
Manifest SHA-256: `d395683953acb11f271f1ea81189127c1e112f2f32f0cf7c2bd743511676c5b9`.

Archive: `/Users/alex/Library/Caches/vinix-ios/coretelephony-20261024.tar.zst`.
Archive SHA-256: `f6e3621197a86adcf6fd470a11e418183472242429a18ed493bdeba8d6f7edac`.

Sealing, integrity self-tests, archive creation and independent archive/manifest
hash checks passed. The complete archive was extracted into
`/Users/alex/Library/Caches/vinix-ios/coretelephony-restored-20261024`, and its
copied checker passed against every restored file without resealing.

The complete bundle retains committed source snapshots, generated C, host
objects and app, ARM64 fixtures and runners, command logs and statuses, and
selected build-input hashes. Each of four VM states retains its boot image,
firmware variables, initramfs, Limine configuration and serial log.
`telephony-evidence.v` requires the complete inventory and result markers,
verifies every manifested file's SHA-256 and rejects extra files. Its self-tests
reject missing guest media, a modified inspection log and an unmanifested file,
restoring the bundle afterwards. Historical checkers remain unchanged. Full
compiler-header and host dynamic-library closures are not independently sealed.
Rebuilding requires the prepared dependencies used by the V tools.

From the source revision above in the repository root, compile the tools with
the prepared frozen compiler into a fresh external directory. The inspector
and generated fixtures retain assertions; the orchestration tools use explicit
failure checks in production builds:

```sh
export V_RESOURCE_PATH="$PWD/build/ios/fortnite/ns-calendar-checks/toolchain"
export V_MACOS_V3_NO_FALLBACK=1
export VINIX_TELEPHONY_OUT=/external/fresh-telephony
mkdir -p "$VINIX_TELEPHONY_OUT"
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_TELEPHONY_OUT/notification-checks" tests/ios/notification-checks.v
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_TELEPHONY_OUT/notification-vm" tests/ios/notification-vm.v
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_TELEPHONY_OUT/telephony-evidence" tests/ios/telephony-evidence.v
"$V_RESOURCE_PATH/v" -nocache -gc none -cc clang -o "$VINIX_TELEPHONY_OUT/inspect-user-notifications" tests/ios/inspect-user-notifications.v
"$VINIX_TELEPHONY_OUT/notification-checks" telephony-metadata-inspect "$VINIX_TELEPHONY_OUT"
"$VINIX_TELEPHONY_OUT/notification-checks" telephony-host "$VINIX_TELEPHONY_OUT"
"$VINIX_TELEPHONY_OUT/notification-checks" build "$VINIX_TELEPHONY_OUT"
"$VINIX_TELEPHONY_OUT/notification-checks" notifications "$VINIX_TELEPHONY_OUT"
"$VINIX_TELEPHONY_OUT/notification-checks" probe "$VINIX_TELEPHONY_OUT"
"$VINIX_TELEPHONY_OUT/notification-checks" audit "$VINIX_TELEPHONY_OUT"
"$VINIX_TELEPHONY_OUT/notification-checks" static-audit "$VINIX_TELEPHONY_OUT"
"$VINIX_TELEPHONY_OUT/telephony-evidence" snapshot "$VINIX_TELEPHONY_OUT"
"$VINIX_TELEPHONY_OUT/telephony-evidence" seal "$VINIX_TELEPHONY_OUT"
"$VINIX_TELEPHONY_OUT/telephony-evidence" selftest "$VINIX_TELEPHONY_OUT"
"$VINIX_TELEPHONY_OUT/telephony-evidence" archive-zstd "$VINIX_TELEPHONY_OUT"
```

The wrapper's successful probe/audit status means the guest completed and its
evidence was captured; the child still exits 1. The checker requires that exit
status and exact linker blocker or audit totals. For a sealed bundle, run
`telephony-evidence check DIR` without resealing.

To restore the archive to a fresh external directory:

```sh
mkdir -p /external/restored-telephony
/usr/bin/tar --use-compress-program='/opt/homebrew/bin/zstd --long=31 -d' -xf /Users/alex/Library/Caches/vinix-ios/coretelephony-20261024.tar.zst --strip-components=1 -C /external/restored-telephony
/external/restored-telephony/telephony-evidence check /external/restored-telephony
```
