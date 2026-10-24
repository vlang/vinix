# Nonrecursive NSLock — 2026-10-25

Source revision: `c8a2ded7377ae0249a8881934575d2d08b478116`.

`NSLock` now resolves through Foundation with Apple's measured 88-byte layout,
`_priv` ivar and seven method encodings. It supports initialization, copied
names, blocking `lock`, nonrecursive `tryLock`, `lockBeforeDate:` and
owner-checked `unlock`. Timed and blocking waiters share a condition variable;
waits do not hold the Objective-C runtime lock. Expiration does not acquire a
held lock, and expired timed waiters do not strand blocking waiters.

Operations pin their receiver. Name-copy callbacks run outside the runtime
lock and lock gate, allowing other threads to use the receiver. Storage checks
validate allocation provenance, body size, isa and initialization. Caller-owned
construction, failed constructors and cleanup after an isa change are covered.
Pre-initialization names are retired during initialization. Custom subclasses,
copying, coding, uninitialized acquisition, foreign unlocks and destruction of
held or actively used locks fail explicitly.

## Validation

The shared fixture passed against Apple Foundation and the V runtime on the
ARM64 Mac under ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Assertions remained enabled; leak detection was
disabled. Checks cover the native layout and method encodings, copied mutable
Unicode names, replacement and nil names, nonrecursive acquisition, past/nil
and future deadlines, timed and blocking handoff, and independent runtime
progress while a thread waits.

Runtime checks exercise reentrant name-copy callbacks from other threads,
receiver pins, guarded caller storage, failed constructors, pre-initialization
names, 64 isa replacements and 28 rejection cases. Two drained runtimes finish
with zero owned Objective-C objects and weak registrations; those counters do
not establish absence of all heap leaks. The existing `NSRecursiveLock` fixture
also passed both host sanitizer modes, including its 23 rejection cases.

All sixteen ARM64 fixtures and runners built, and the full native regression
driver compiled. The focused QEMU guest passed all thirteen lock, recursive
lock, map-table, credential, telephony, cache, calendar and notification
fixtures. The full native regression suite was not run.

The first GLES runner artifact failed execution with child status 127. Its
invalid format, failed probe/audit logs and complete VM states remain in the
bundle. The VM tool now checks the ARM64 ELF header of its generated init,
fixtures and selected runner before creating guest state. A deliberately
corrupt runner was rejected before state creation. Rebuilding the GLES runner
produced a valid executable, and fresh probe and audit guests completed.

The fresh Fortnite probe resolves `NSLock` and stops at
`_OBJC_CLASS_$_NSNumberFormatter` during linking, before application entry, with
process exit status 1. The preserved executable has SHA-256
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
The C++/GLES/Text audit reports 2,945 resolved imports, 59 unresolved strong and
114 unresolved weak imports. The static C++ runner reports 2,931 resolved,
73 unresolved strong and 114 unresolved weak imports:

| Image | Static resolved / strong / weak | GLES resolved / strong / weak |
| --- | --- | --- |
| Fortnite executable | 2091 / 70 / 78 | 2102 / 59 / 78 |
| EOSSDK | 661 / 3 / 16 | 664 / 0 / 16 |
| MarketplaceKitWrapper | 179 / 0 / 20 | 179 / 0 / 20 |

Audits do not execute app code. No Fortnite initialization, rendering, login
or gameplay was verified. Swift support remains unverified.

## Evidence and reproduction

Archive: `/Users/alex/Library/Caches/vinix-ios/lock-20261025.tar.zst`.
Archive SHA-256:
`53cef226b3e097e98d913a05a79090c3fc98c03837f6e0c74e41518c3347c313`.
Contained manifest SHA-256:
`20d4d42ad8415cc40792895ac96e90ca7e2a23d2a01be1729d6af52a3e77bc7c`.

The complete bundle retains committed source snapshots, generated C, host
objects and app, ARM64 fixtures and runners, command logs and statuses, and
selected build-input hashes. Each of four successful VM states retains its
boot image, firmware variables, initramfs, Limine configuration and serial log;
the two failed states are also retained. `lock-evidence.v` checks the complete
inventory, exact result markers and every manifested file's SHA-256, rejecting
extra files. Historical checkers remain unchanged. Compiler-header and host
dynamic-library closures are not independently sealed. Rebuilding requires
the prepared dependencies used by the V tools.

Sealing and all three rejection self-tests passed: missing guest media,
modified inspection output and an unmanifested file were rejected, with the
bundle restored afterwards. Archive compression integrity, independent
SHA-256 checks and a fresh extraction passed. The restored bundle passed the
complete checker without resealing. Temporary RAM storage was used for the
bundle and restoration; the archive and its checksum remain on the persistent
filesystem at the path above.

From the source revision above in the repository root, compile the tools with
the prepared frozen compiler into a fresh external directory. The inspector
and generated fixtures retain assertions; orchestration tools use explicit
failure checks in production builds:

```sh
export V_RESOURCE_PATH="$PWD/build/ios/fortnite/ns-calendar-checks/toolchain"
export V_MACOS_V3_NO_FALLBACK=1
export VINIX_LOCK_OUT=/external/fresh-lock
mkdir -p "$VINIX_LOCK_OUT"
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_LOCK_OUT/notification-checks" tests/ios/notification-checks.v
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_LOCK_OUT/notification-vm" tests/ios/notification-vm.v
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_LOCK_OUT/lock-evidence" tests/ios/lock-evidence.v
"$V_RESOURCE_PATH/v" -nocache -gc none -cc clang -o "$VINIX_LOCK_OUT/inspect-user-notifications" tests/ios/inspect-user-notifications.v
"$VINIX_LOCK_OUT/notification-checks" lock-metadata-inspect "$VINIX_LOCK_OUT"
"$VINIX_LOCK_OUT/notification-checks" lock-host "$VINIX_LOCK_OUT"
"$VINIX_LOCK_OUT/notification-checks" recursive-lock-host "$VINIX_LOCK_OUT/recursive-host"
"$VINIX_LOCK_OUT/notification-checks" driver-build "$VINIX_LOCK_OUT"
"$VINIX_LOCK_OUT/notification-checks" build "$VINIX_LOCK_OUT"
"$VINIX_LOCK_OUT/notification-checks" build-run-ios-gles "$VINIX_LOCK_OUT"
"$VINIX_LOCK_OUT/notification-checks" notifications "$VINIX_LOCK_OUT"
"$VINIX_LOCK_OUT/notification-checks" probe "$VINIX_LOCK_OUT"
"$VINIX_LOCK_OUT/notification-checks" audit "$VINIX_LOCK_OUT"
"$VINIX_LOCK_OUT/notification-checks" static-audit "$VINIX_LOCK_OUT"
"$VINIX_LOCK_OUT/lock-evidence" snapshot "$VINIX_LOCK_OUT"
"$VINIX_LOCK_OUT/lock-evidence" seal "$VINIX_LOCK_OUT"
"$VINIX_LOCK_OUT/lock-evidence" selftest "$VINIX_LOCK_OUT"
"$VINIX_LOCK_OUT/lock-evidence" archive-zstd "$VINIX_LOCK_OUT"
```

The wrapper's successful probe/audit status means the guest completed and its
evidence was captured; the child still exits 1. The checker requires that exit
status and the exact linker blocker or audit totals. For a sealed bundle, run
`lock-evidence check DIR` without resealing.

To restore the archive to a fresh external directory:

```sh
mkdir -p /external/restored-lock
/usr/bin/tar --use-compress-program='/opt/homebrew/bin/zstd --long=31 -d' -xf /Users/alex/Library/Caches/vinix-ios/lock-20261025.tar.zst --strip-components=1 -C /external/restored-lock
/external/restored-lock/lock-evidence check /external/restored-lock
```
