# Bounded NSCache storage — 2026-10-24

Source revision: `43153be27b5c03c8ed2561fdd1bf98bca8946c82`.

`NSCache` now resolves through Foundation and CoreFoundation. The bounded
implementation supports copied UTF-8 names, retained keys and values, equality
lookup, replacement, removal and thread-safe count/cost eviction. Keys are
retained without copying. Nil lookup/removal keys return nil or do nothing;
nil insertion keys or values fail explicitly. Names are limited to 64 KiB of
input, with embedded NUL truncation matching the measured Apple behavior.

Apple measurements establish the 48-byte NSObject layout, ten ivars and method
encodings for sixteen supported selectors. Runtime checks validate allocation
provenance and native body contents. Nonzero count/cost limits are enforced
strictly in FIFO order, with a hard ceiling of 4096 entries; Apple's limits are
advisory. A nil delegate is supported. Nonzero delegates, discardable-content
protocols, coding, custom subclasses and unsupported private APIs fail explicitly.
Apple measurements show that its delegate reference is neither retained nor
cleared on destruction;
the runtime does not expose that delegate behavior.

## Validation

The shared fixture passed against Apple Foundation and the V runtime on the
ARM64 Mac under ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Leak detection was disabled. Checks cover layout,
encodings, defaults, copied names, retained noncopyable keys and values,
equality, replacement and removal. Runtime checks cover four concurrent worker
threads, count/cost limits, cost overflow, the hard entry bound, reentrant
hash/equality/destruction callbacks, constructors and failure cleanup, supplied
storage, changed-isa cleanup, native overrides and 31 rejection cases. Two
drained lifetimes finish with zero owned Objective-C objects and weak
registrations; these counters do not establish absence of all heap leaks.

All eleven ARM64 fixtures and runners built. The focused Vinix guest passed
cache, calendar, calendar-trigger, notification-request, notification-center,
notification-content, notification-sound and notification-attachment fixtures,
including their 31/41/21/28/31/28/33/39 rejection cases. QEMU 11.1.1 used HVF,
four CPUs and 4096 MiB RAM with the prepared socket-test kernel. The center
fixture's two shutdown warnings about one owned object are intentional: it
releases its retained delegate afterwards and checks that the runtime is
drained. This run did not execute the full native regression suite or establish
Swift support.

The fresh Fortnite probe resolves `NSCache` and stops at
`_OBJC_CLASS_$_CTTelephonyNetworkInfo` in CoreTelephony. It still exits 1 during
linking, before application entry. Executable SHA-256:
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
The import audits did not execute app code:

| Runner / image | Resolved | Unresolved strong | Unresolved weak |
| --- | ---: | ---: | ---: |
| C++/GLES/Text/SQLite: Fortnite | 2,098 | 63 | 78 |
| C++/GLES/Text/SQLite: EOSSDK | 664 | 0 | 16 |
| C++/GLES/Text/SQLite: MarketplaceKitWrapper | 179 | 0 | 20 |
| C++/GLES/Text/SQLite: total | 2,941 | 63 | 114 |
| Static C++/SQLite: Fortnite | 2,087 | 74 | 78 |
| Static C++/SQLite: EOSSDK | 661 | 3 | 16 |
| Static C++/SQLite: MarketplaceKitWrapper | 179 | 0 | 20 |
| Static C++/SQLite: total | 2,927 | 77 | 114 |

These counts establish import resolution only. Fortnite initialization,
rendering, login and gameplay remain unverified.

## Evidence and reproduction

Bundle: `/Users/alex/Library/Caches/vinix-ios/ns-cache-20261024`.
Manifest SHA-256: `828489ed73d3fc07e9d6c2a622ec15da581cb9f5ca8c598c0a1ff481c1c658b9`.

Archive: `/Users/alex/Library/Caches/vinix-ios/ns-cache-20261024.tar.zst`.
Archive SHA-256: `a0c55ba1c26e914430270677ff83f99881f0eeb2d118f2b3d1c9f432f1cf8332`.

Sealing, integrity self-tests, archive creation and independent archive/manifest
hash checks passed. The complete archive was extracted into
`/Users/alex/Library/Caches/vinix-ios/ns-cache-restored-20261024`, and its copied
checker passed against every restored file without resealing.

The complete bundle retains committed source snapshots, generated C, host
objects and app, ARM64 fixtures and runners, command logs and statuses, and
selected build-input hashes. Each of four VM states retains its boot image,
firmware variables, initramfs, Limine configuration and serial log.
`cache-evidence.v` requires the complete inventory and exact result markers,
verifies every manifested file's SHA-256 and rejects extra files. Its self-tests
reject missing guest media, a modified inspection log and an unmanifested file,
restoring the bundle afterwards. Historical checkers remain unchanged. Full
compiler-header and host dynamic-library closures are not independently sealed.
Rebuilding requires the prepared dependencies used by the V tools.

From the source revision above in the repository root, compile the tools with
the prepared frozen compiler into a fresh external directory. The inspectors
and generated fixtures retain assertions; the orchestration tools use explicit
failure checks in production builds:

```sh
export V_RESOURCE_PATH="$PWD/build/ios/fortnite/ns-calendar-checks/toolchain"
export V_MACOS_V3_NO_FALLBACK=1
export VINIX_CACHE_OUT=/external/fresh-cache
mkdir -p "$VINIX_CACHE_OUT"
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_CACHE_OUT/notification-checks" tests/ios/notification-checks.v
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_CACHE_OUT/notification-vm" tests/ios/notification-vm.v
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_CACHE_OUT/cache-evidence" tests/ios/cache-evidence.v
"$V_RESOURCE_PATH/v" -nocache -gc none -cc clang -o "$VINIX_CACHE_OUT/inspect-cache" tests/ios/inspect-cache.v
"$V_RESOURCE_PATH/v" -nocache -gc none -cc clang -o "$VINIX_CACHE_OUT/inspect-user-notifications" tests/ios/inspect-user-notifications.v
"$VINIX_CACHE_OUT/notification-checks" cache-inspect "$VINIX_CACHE_OUT"
"$VINIX_CACHE_OUT/notification-checks" cache-metadata-inspect "$VINIX_CACHE_OUT"
"$VINIX_CACHE_OUT/notification-checks" cache-host "$VINIX_CACHE_OUT"
"$VINIX_CACHE_OUT/notification-checks" build "$VINIX_CACHE_OUT"
"$VINIX_CACHE_OUT/notification-checks" notifications "$VINIX_CACHE_OUT"
"$VINIX_CACHE_OUT/notification-checks" probe "$VINIX_CACHE_OUT"
"$VINIX_CACHE_OUT/notification-checks" audit "$VINIX_CACHE_OUT"
"$VINIX_CACHE_OUT/notification-checks" static-audit "$VINIX_CACHE_OUT"
"$VINIX_CACHE_OUT/cache-evidence" snapshot "$VINIX_CACHE_OUT"
"$VINIX_CACHE_OUT/cache-evidence" seal "$VINIX_CACHE_OUT"
"$VINIX_CACHE_OUT/cache-evidence" selftest "$VINIX_CACHE_OUT"
"$VINIX_CACHE_OUT/cache-evidence" archive-zstd "$VINIX_CACHE_OUT"
```

The wrapper's successful probe/audit status means the guest completed and its
evidence was captured; the child still exits 1. The checker requires that exit
status and exact linker blocker or audit totals. For a sealed bundle, run
`cache-evidence check DIR` without resealing.

To restore the archive to a fresh external directory:

```sh
mkdir -p /external/restored-cache
/usr/bin/tar --use-compress-program='/opt/homebrew/bin/zstd --long=31 -d' -xf /Users/alex/Library/Caches/vinix-ios/ns-cache-20261024.tar.zst --strip-components=1 -C /external/restored-cache
/external/restored-cache/cache-evidence check /external/restored-cache
```
