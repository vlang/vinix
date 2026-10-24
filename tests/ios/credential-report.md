# Password NSURLCredential — 2026-10-24

Source revision: `1e963f5d3434f60355fa6a0a99e4ec8a9825d4fc`.

`NSURLCredential` now resolves through Foundation with Apple's measured
16-byte NSObject layout and `_internal` ivar at offset 8. Password credentials
support factory and designated initialization, immutable username/password
snapshots, `hasPassword`, persistence and retained self copies. Nil and empty
passwords remain distinct; UTF-8, embedded NUL bytes and persistence values
outside the documented enum are preserved. Each input is limited to 65,536
bytes. Password credentials return nil identity and certificates.

Runtime checks validate allocation provenance, initialization and the native
body under the runtime lock. Both strings are snapshotted before application
constructors run. Constructors execute outside the lock with a pinned receiver;
failed owned initialization releases its receiver and temporary strings.
Caller-owned storage is supported for successful construction and explicit
destruction. Cleanup follows the original allocation class after an isa change.
Custom subclasses, plain initialization, coding, mutable copies, nonzero copy
zones, equality/hash/description, trust/identity credentials and unsupported
private APIs fail explicitly. This is the password subset, not full Security
credential support.

## Validation

The shared fixture passed against Apple Foundation and the V runtime on the
ARM64 Mac under ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Assertions remained enabled; leak detection was
disabled. Checks cover layout, method encodings, nil/empty/UTF-8/NUL values,
persistence, mutable-input snapshots, pool boundaries and retained self copies.
Runtime checks cover four concurrent copy/getter workers, constructor failure
rollback, reentrant callbacks that release both input strings, guarded caller
storage, changed-isa cleanup, framework boundaries and 35 rejection cases.
Two drained lifetimes finish with zero owned Objective-C objects and weak
registrations; these counters do not establish absence of all heap leaks.

All thirteen ARM64 fixtures and runners built. The focused QEMU guest passed
all ten credential, telephony, cache, calendar and notification fixtures,
including the 35 credential rejection cases.

The fresh Fortnite probe resolves `NSURLCredential` and stops at
`_OBJC_CLASS_$_NSMapTable` during linking, before application entry, with process
exit status 1. The preserved Fortnite executable has SHA-256
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
The C++/GLES/Text audit reports 2,943 resolved imports, 61 unresolved strong and
114 unresolved weak imports across the executable and both bundled frameworks.
The static C++ runner reports 2,929 resolved, 75 unresolved strong and 114
unresolved weak imports:

| Image | Static resolved / strong / weak | GLES resolved / strong / weak |
| --- | --- | --- |
| Fortnite executable | 2089 / 72 / 78 | 2100 / 61 / 78 |
| EOSSDK | 661 / 3 / 16 | 664 / 0 / 16 |
| MarketplaceKitWrapper | 179 / 0 / 20 | 179 / 0 / 20 |

Audits do not execute app code. No Fortnite initialization, rendering, login or
gameplay was verified. Full native regression and Swift support remain
unverified.

## Evidence and reproduction

Bundle: `/Users/alex/Library/Caches/vinix-ios/url-credential-20261024`.
Manifest SHA-256:
`56dedcef5d7f7231856a02c5cee41ac1d6263e858623430a400d318aa22d85f6`.

Archive: `/Users/alex/Library/Caches/vinix-ios/url-credential-20261024.tar.zst`.
Archive SHA-256:
`92a1cda1ffef864a49a7d3ed4b343566492f44aaf7e77509783a849b8799bf2d`.

Sealing, all three rejection self-tests and archive creation passed. A fresh
extraction at
`/Users/alex/Library/Caches/vinix-ios/url-credential-restored-20261024`
passed the complete manifest and result checks without resealing. Independent
SHA-256 checks matched both hashes above.

The complete bundle retains committed source snapshots, generated C, host
objects and app, ARM64 fixtures and runners, command logs and statuses, and
selected build-input hashes. Each of four VM states retains its boot image,
firmware variables, initramfs, Limine configuration and serial log.
`credential-evidence.v` requires the complete inventory and result markers,
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
export VINIX_CREDENTIAL_OUT=/external/fresh-credential
mkdir -p "$VINIX_CREDENTIAL_OUT"
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_CREDENTIAL_OUT/notification-checks" tests/ios/notification-checks.v
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_CREDENTIAL_OUT/notification-vm" tests/ios/notification-vm.v
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_CREDENTIAL_OUT/credential-evidence" tests/ios/credential-evidence.v
"$V_RESOURCE_PATH/v" -nocache -gc none -cc clang -o "$VINIX_CREDENTIAL_OUT/inspect-user-notifications" tests/ios/inspect-user-notifications.v
"$V_RESOURCE_PATH/v" -nocache -gc none -cc clang -o "$VINIX_CREDENTIAL_OUT/inspect-credential" tests/ios/inspect-credential.v
"$VINIX_CREDENTIAL_OUT/notification-checks" credential-metadata-inspect "$VINIX_CREDENTIAL_OUT"
"$VINIX_CREDENTIAL_OUT/notification-checks" credential-inspect "$VINIX_CREDENTIAL_OUT"
"$VINIX_CREDENTIAL_OUT/notification-checks" credential-host "$VINIX_CREDENTIAL_OUT"
"$VINIX_CREDENTIAL_OUT/notification-checks" build "$VINIX_CREDENTIAL_OUT"
"$VINIX_CREDENTIAL_OUT/notification-checks" notifications "$VINIX_CREDENTIAL_OUT"
"$VINIX_CREDENTIAL_OUT/notification-checks" probe "$VINIX_CREDENTIAL_OUT"
"$VINIX_CREDENTIAL_OUT/notification-checks" audit "$VINIX_CREDENTIAL_OUT"
"$VINIX_CREDENTIAL_OUT/notification-checks" static-audit "$VINIX_CREDENTIAL_OUT"
"$VINIX_CREDENTIAL_OUT/credential-evidence" snapshot "$VINIX_CREDENTIAL_OUT"
"$VINIX_CREDENTIAL_OUT/credential-evidence" seal "$VINIX_CREDENTIAL_OUT"
"$VINIX_CREDENTIAL_OUT/credential-evidence" selftest "$VINIX_CREDENTIAL_OUT"
"$VINIX_CREDENTIAL_OUT/credential-evidence" archive-zstd "$VINIX_CREDENTIAL_OUT"
```

The wrapper's successful probe/audit status means the guest completed and its
evidence was captured; the child still exits 1. The checker requires that exit
status and exact linker blocker or audit totals. For a sealed bundle, run
`credential-evidence check DIR` without resealing.

To restore the archive to a fresh external directory:

```sh
mkdir -p /external/restored-credential
/usr/bin/tar --use-compress-program='/opt/homebrew/bin/zstd --long=31 -d' -xf /Users/alex/Library/Caches/vinix-ios/url-credential-20261024.tar.zst --strip-components=1 -C /external/restored-credential
/external/restored-credential/credential-evidence check /external/restored-credential
```
