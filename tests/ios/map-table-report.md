# Strong and weak NSMapTable — 2026-10-24

Source revision: `d7ba1cd35b5848cfda01380d29b4c7a79105bc8d`.

`NSMapTable` now resolves through Foundation with Apple's measured 8-byte
NSObject layout and twelve method encodings. Factories and designated
initialization support strong or zeroing weak object keys and values, with
object equality or pointer identity for keys. Equal replacement preserves the
original key. Nil keys and nil values are ignored, including nil values passed
for an existing key. Weak slots are zeroed when their object dies; dead entries
can remain in `count` until a mutation prunes them, matching native observations.

Stable entry cells hold weak registrations. Operations pin their receiver and
retain snapshots while hash/equality and deallocation callbacks execute outside
the runtime lock. Version checks retry after reentrant mutation. Storage checks
validate allocation provenance, initialization, native body and isa under the
lock; destruction follows the original allocation class after an isa change.
Caller-owned construction and explicit destruction are supported.

This implementation bounds storage to 4,096 entries and operations to 64
snapshot attempts, with linear searches. Supported pointer options are strong
memory (`0`), weak memory (`5`), object pointer personality (`512`) and their
combination (`517`). Custom subclasses, copy-in and other pointer functions,
coding, copying, enumeration and unsupported private APIs fail explicitly.

## Validation

The shared fixture passed against Apple Foundation and the V runtime on the
ARM64 Mac under ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Assertions remained enabled; leak detection was
disabled. Checks cover layout, method encodings, factories, nil handling, all
sixteen supported key/value option combinations, equality/identity, original
keys, weak cleanup and pool boundaries.

Runtime checks cover four concurrent workers, hash/equality/deallocation
callbacks that exercise the runtime from another thread, reentrant clearing,
native method overrides, guarded caller storage, changed-isa cleanup and 27
rejection cases. Two drained lifetimes finish with zero owned Objective-C
objects and weak registrations; these counters do not establish absence of all
heap leaks.

All fourteen ARM64 fixtures and runners built, and the full native regression
driver compiled. The focused QEMU guest passed all eleven map-table, credential,
telephony, cache, calendar and notification fixtures, including the 27 map-table
rejection cases. The full native regression suite was not run.

The fresh Fortnite probe resolves `NSMapTable` and stops at
`_OBJC_CLASS_$_NSLock` during linking, before application entry, with process
exit status 1. The preserved Fortnite executable has SHA-256
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
The C++/GLES/Text audit reports 2,944 resolved imports, 60 unresolved strong and
114 unresolved weak imports across the executable and both bundled frameworks.
The static C++ runner reports 2,930 resolved, 74 unresolved strong and 114
unresolved weak imports:

| Image | Static resolved / strong / weak | GLES resolved / strong / weak |
| --- | --- | --- |
| Fortnite executable | 2090 / 71 / 78 | 2101 / 60 / 78 |
| EOSSDK | 661 / 3 / 16 | 664 / 0 / 16 |
| MarketplaceKitWrapper | 179 / 0 / 20 | 179 / 0 / 20 |

Audits do not execute app code. No Fortnite initialization, rendering, login or
gameplay was verified. Swift support remains unverified.

## Evidence and reproduction

Bundle: `/Users/alex/Library/Caches/vinix-ios/map-table-20261024`.
Manifest SHA-256:
`48501890538eb6b6f6d86bd082912013a4215dd5c57f80a3bc70bcd37b2d5845`.

Archive: `/Users/alex/Library/Caches/vinix-ios/map-table-20261024.tar.zst`.
Archive SHA-256:
`35511076e71f204e00d23ad7c6fffa5fddb93509ee388e0bb0d3ac23c51f7a40`.

Sealing, all three rejection self-tests and archive creation passed. A fresh
extraction at
`/private/tmp/codex-top20-ram16g-3a729d0f9b1c4e68/vinix-map-table-20261024/restored-map-table`
passed the complete manifest and result checks without resealing. Independent
SHA-256 checks matched both hashes above. Temporary RAM storage was used for
archiving and extraction; the bundle and archive above are retained on the
persistent filesystem.

The complete bundle retains committed source snapshots, generated C, host
objects and app, ARM64 fixtures and runners, command logs and statuses, and
selected build-input hashes. Each of four VM states retains its boot image,
firmware variables, initramfs, Limine configuration and serial log.
`map-table-evidence.v` requires the complete inventory and result markers,
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
export VINIX_MAP_TABLE_OUT=/external/fresh-map-table
mkdir -p "$VINIX_MAP_TABLE_OUT"
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_MAP_TABLE_OUT/notification-checks" tests/ios/notification-checks.v
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_MAP_TABLE_OUT/notification-vm" tests/ios/notification-vm.v
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_MAP_TABLE_OUT/map-table-evidence" tests/ios/map-table-evidence.v
"$V_RESOURCE_PATH/v" -nocache -gc none -cc clang -o "$VINIX_MAP_TABLE_OUT/inspect-user-notifications" tests/ios/inspect-user-notifications.v
"$V_RESOURCE_PATH/v" -nocache -gc none -cc clang -o "$VINIX_MAP_TABLE_OUT/inspect-map-table" tests/ios/inspect-map-table.v
"$VINIX_MAP_TABLE_OUT/notification-checks" map-table-metadata-inspect "$VINIX_MAP_TABLE_OUT"
"$VINIX_MAP_TABLE_OUT/notification-checks" map-table-inspect "$VINIX_MAP_TABLE_OUT"
"$VINIX_MAP_TABLE_OUT/notification-checks" map-table-host "$VINIX_MAP_TABLE_OUT"
"$VINIX_MAP_TABLE_OUT/notification-checks" build "$VINIX_MAP_TABLE_OUT"
"$VINIX_MAP_TABLE_OUT/notification-checks" notifications "$VINIX_MAP_TABLE_OUT"
"$VINIX_MAP_TABLE_OUT/notification-checks" probe "$VINIX_MAP_TABLE_OUT"
"$VINIX_MAP_TABLE_OUT/notification-checks" audit "$VINIX_MAP_TABLE_OUT"
"$VINIX_MAP_TABLE_OUT/notification-checks" static-audit "$VINIX_MAP_TABLE_OUT"
"$VINIX_MAP_TABLE_OUT/map-table-evidence" snapshot "$VINIX_MAP_TABLE_OUT"
"$VINIX_MAP_TABLE_OUT/map-table-evidence" seal "$VINIX_MAP_TABLE_OUT"
"$VINIX_MAP_TABLE_OUT/map-table-evidence" selftest "$VINIX_MAP_TABLE_OUT"
"$VINIX_MAP_TABLE_OUT/map-table-evidence" archive-zstd "$VINIX_MAP_TABLE_OUT"
```

The wrapper's successful probe/audit status means the guest completed and its
evidence was captured; the child still exits 1. The checker requires that exit
status and exact linker blocker or audit totals. For a sealed bundle, run
`map-table-evidence check DIR` without resealing.

To restore the archive to a fresh external directory:

```sh
mkdir -p /external/restored-map-table
/usr/bin/tar --use-compress-program='/opt/homebrew/bin/zstd --long=31 -d' -xf /Users/alex/Library/Caches/vinix-ios/map-table-20261024.tar.zst --strip-components=1 -C /external/restored-map-table
/external/restored-map-table/map-table-evidence check /external/restored-map-table
```
