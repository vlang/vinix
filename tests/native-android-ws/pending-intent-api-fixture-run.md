# PendingIntent registry and service recovery fixture

Host qualification passed on 2026-11-02. ARM execution is pending. The six-class
fixture exercises the `FLAG_NO_CREATE` recovery query followed by real queued
`Service.onStartCommand` delivery through `send(Context,int,Intent)`. It never
opens Google applications or accesses accounts or the network.

The build started at source revision `50bd1227e18d88af0027e314d0f05fbc2f59a947`.
Its exact generator sources are preserved in the external bundle and match:

| Source | SHA-256 |
| --- | --- |
| `pendingintentfixture/main.v` | `f76ea7261012308d434dfcb735420f5e57562ec1211ae16f99c9d7cff18c61b0` |
| `pendingintentfixture/sources.v` | `b161809c2b7187b8870780674108eb16d73804231eed60497388bbd1624441c5` |

Complete evidence is retained outside Git:

- `/Users/alex/.local/state/vinix/android/pending-intent-fixture-2026-11-02-r1/`
- `/Users/alex/.local/state/vinix/android/pending-intent-fixture-controls-2026-11-02-r1/`

`build.json` preserves all regular-file input hashes, exact tool-directory
membership, command receipts, generator copies, and the output inventory. The
signed `probe.apk` SHA-256 is
`24ee07ce193fbde0ee448aeceee70a6013095301cbb6b487c9e61aaf175a9456`.
The `build.json` SHA-256 is
`9548b5945191d95697f39f30e4ac5b56cc9ee678b0639030e03e6b7b81437545`.
Its extracted `classes.dex` SHA-256 is
`a75c5c6a09496cd366e4daf1a37bf8c349918a3653f61eba16708805d2aaf08a`.

The builder compiled successfully with V `-new-compiler -gc boehm -nocache -cc cc`.
The APK passed error-free Smali assembly, two canonical DEX/Smali roundtrips for
all six classes, package/activity badging, v3 signature verification, duplicate
ZIP-member rejection, exact single-DEX membership, and byte equality between
the signed APK's extracted DEX and the checked production DEX. Original source,
executable, Java, framework resource, signing, archive and Smali inputs were
re-read before sealing the receipt.

Both phases retained the original 600 MiB aggregate RSS, 300-second wall,
512 MiB shared-volume growth, 1 GiB reserve and 4 MiB output guards, with
`ulimit -f 16777216`. Both exited zero with complete process cleanup and zero
process swaps. Compilation took 1.626 seconds with a 363,069,440-byte reported
peak RSS; signed production took 5.977 seconds with a 97,550,336-byte reported
peak RSS. Their guard receipts retain observed disk growth and sampled memory.

The Activity yields between stages instead of waiting on the main thread.
Seven real Service callbacks validate original extras precedence, factory and
sender snapshot isolation, source-bounds copying, creator updates, immutable
fill-in rejection, replacement/cancellation and the winning one-shot payload.
Two worker threads announce readiness before a shared gate releases their
one-shot sends; one must succeed, one must receive `CanceledException`, and only
one service callback may occur. A sender Context that rejects `startService`
proves delivery uses creator authority. A real registered BroadcastReceiver
checks shared broadcast delivery semantics. Worker joins, token cancellation,
receiver unregistration and one service creation/destruction precede the sole
success marker:

```text
PENDING-INTENT-PASS no-create identity send fill-in update cancel one-shot immutable parcel service recovery broadcast cleanup
```

The failure marker is `PENDING-INTENT-FAIL`. Runtime launch uses package
`org.vinix.bootstrap` and Activity `org.vinix.bootstrap.Main`. The old
`pending-intent-fixture.v` and its historical evidence remain unchanged.

Identity checks cover extras exclusion, request code, all supported Intent
filter fields, persistent one-shot/immutable flags, creator package/UID,
Activity/application context equivalence, service/foreground/activity/broadcast
factory separation and the final Intent key for activity stacks. Parcel aliases
must observe cancellation, including aliases created after cancellation.
Foreground services and activity stacks receive identity checks only. There is
no deterministic weak-reference GC-expiry test, cross-process Binder transport
check, or independent broadcast sender-authority trap. The fixture does not
establish Google authentication or map rendering success.
