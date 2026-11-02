# Broadcast permission fixture delivery, 2026-11-02

The additive runner selector `--broadcast-permission` requires the successor
framework, fresh coupled native library and signed fixture. Transfer selector
`serve --broadcast-permission-api` exposes exactly `/broadcast-permission-api-run`
and `/broadcast-permission.apk`. Historical profiles, routes and pins remain
unchanged, including their original native identities.

The exact success marker is:

```text
BROADCAST-PERMISSION-PASS actual-delivery signature-owned null-legacy denied-permissions fake-grants immutable-authority metadata-restored async-barriers
```

The seven-class fixture exercises actual delivery to process-local dynamic and
primary manifest receivers; dynamic callbacks use a dedicated HandlerThread.
A non-null receiver permission admits the immutable
primary APK's self-owned requested signature permission; unknown, unrequested,
unproven and non-signature permissions remain denied. Null permission retains
legacy delivery. Forged PackageManager/Context grants and mutable public package
metadata do not supply authority. Mutation/restoration, null Intent ordering,
queued barriers and thread shutdown are checked. Registered sender permissions,
category/data matching, export rules and cross-process delivery remain outside
this result. The fixture supplies no platform stub or blanket permission grant.

The generic runner retains six protected input identities, eleven receipt
checks, isolated identity/data/home/surface, explicit environment, closed inherited
descriptors, 180/20-second deadlines, 4 MiB log and 8,192-byte line limits, one
exact PASS/READY pair, drained EOF and clean child exit. Health diagnostics remain
unchanged. Host qualification does not establish ARM, GMS, Maps or authentication.

Paths below use `S=/Users/alex/.local/state/vinix/android`.

| Input | Path below S | SHA-256 |
| --- | --- | --- |
| Framework | `combined-account-webview-broadcast-permission-framework-2026-11-02-r1/api-impl.jar` | `9e998094f8e122c22195e0c9a8f79377dbf16cd04d321ab4d1a47650908082f9` |
| Fresh native | `current-native-build-2026-11-02-broadcast-permission-r1/native/libvinix-android-native.so` | `29b2631c36a4a8c802e904e936c23e090fb2de3b5019ac93548df1b15de2a8f1` |
| Fixture | `broadcast-permission-fixture-2026-11-02-r2/probe.apk` | `0219961f053e02b8d4435b87e86acec64e56d57eb2b68d2f175638016eda37b5` |
| ARM runner | `broadcast-permission-api-run-2026-11-02-r1/run` | `8de1014a44c56cf05d336643a24baeca31886139afab148b1fbf783911126881` |
| Transfer | `broadcast-permission-api-transfer-build-2026-11-02-r1/transfer` | `a954603462a1e38f28d8f763000f9f93908f36f0c941a0bd8c30f9a5f1fdb03d` |

The r2 fixture build receipt hashes to
`a2fa842f2df8bf23229140479c512952d24b268e7b4d2091841ee0d61fe2b09a`.
Its earlier r1 assembly failure remains preserved by the fixture qualification;
this transfer serves only the signed r2 APK. All five delivery qualification
phases passed on their first attempts. The runner selftest rejected 3,255
malformed/mixed/failure cases. Transfer tests retain historical binary snapshots,
GET-only requests, traversal and absolute deadlines, adding exact selector/port
refusal and route/path/hash uniqueness checks. ELF inspection confirms static
AArch64 EXEC without INTERP or DYNAMIC segments.

| Check | Guard seconds | Sampled aggregate RSS bytes | Time maximum bytes |
| --- | ---: | ---: | ---: |
| Host runner compile | 1.386 | 357,728,256 | 365,576,192 |
| Runner selftest | 1.051 | 21,659,648 | 17,907,712 |
| Static ARM runner compile | 1.717 | 372,080,640 | 370,884,608 |
| Host transfer compile | 1.634 | 387,612,672 | 417,546,240 |
| Transfer selftest | 1.018 | 12,484,608 | 11,255,808 |

Every guard/child exit is zero, reason empty, cleanup complete and swaps zero
under the original 600 MiB RSS, 300-second, 512 MiB shared-growth, 1 GiB reserve,
4 MiB output and shell file-size cap 16777216 limits. Compilers were serialized.
SDK manifest/build/JAR/DEX, fixture receipt/APK, fresh native manifest/build/DSO,
tool and predecessor pins were independently rehashed before and after
qualification. Frozen sources equal the checkout. Both source bases are
`0b00959bc20d3dd9e6e6804b9a60393949d29a94`; runner/transfer source hashes are
respectively `6f5b6cf643ec9637a5adfa61d0654e38e37a5aed2218d242986eca1f6f23e183`
and `9676873da7a10f3ddcd443cdc0e2414f6e127a0ba6d58133403013e24df8807b`.

Four complete tool/control roots passed sealing and separate fresh-process
readback for 35 entries. The manifest at
`S/broadcast-permission-api-tools-sealed-2026-11-02-r1/manifest.json` hashes to
`4eeaa6acb3aeebc022d52b7c975eea389f2b20736aa3c98a7e0787d973dec722`.
Seal/readback guards took 56/217 ms, both guard/child exits zero and cleanup
complete under the same RSS/reserve/output/file caps and 64 MiB growth. Controls
remain in `S/broadcast-permission-api-tools-seal-controls-2026-11-02-r1`.
Independent source, final artifact and report reviews approved the exact pins,
marker, unchanged health policy, static ELF, guards, source copies and recipe.

## Guest recipe

Verify that `broadcast-permission-probe`, UID/GID 10146, the dedicated runtime
mount and output path are absent. Provision and confirm the exact account:

```sh
grep -nE '(^broadcast-permission-probe:|:10146:)' /etc/passwd /etc/group
/usr/sbin/addgroup -g 10146 broadcast-permission-probe
/usr/sbin/adduser -D -H -u 10146 -G broadcast-permission-probe -s /bin/false broadcast-permission-probe
grep -nE '^broadcast-permission-probe:' /etc/passwd /etc/group
grep ' /opt/broadcast-permission-runtime ' /proc/self/mounts
test ! -e /var/lib/broadcast-permission-r1
mkdir /opt/broadcast-permission-runtime
mount -o bind /opt/vinix-android-aarch64 /opt/broadcast-permission-runtime
mount -o remount,bind,ro,nosuid,nodev,strictatime,wxallowed none /opt/broadcast-permission-runtime
grep ' /opt/broadcast-permission-runtime ' /proc/self/mounts
mkdir -p /opt/input
```

Require read-only `nosuid,nodev,wxallowed` attachment without `noexec`. Start the
qualified host transfer with a fresh output only when the guest is ready to fetch:

```sh
S=/Users/alex/.local/state/vinix/android
"$S/broadcast-permission-api-transfer-build-2026-11-02-r1/transfer" serve --broadcast-permission-api "$S/broadcast-permission-api-transfer-live-2026-11-02-r1" 55538
```

Download and verify both hashes before launch:

```sh
wget -O /opt/input/broadcast-permission-run http://10.0.2.2:55538/broadcast-permission-api-run
wget -O /opt/input/broadcast-permission.apk http://10.0.2.2:55538/broadcast-permission.apk
chmod 755 /opt/input/broadcast-permission-run
chmod 644 /opt/input/broadcast-permission.apk
sha256sum /opt/input/broadcast-permission-run /opt/input/broadcast-permission.apk
/opt/input/broadcast-permission-run --broadcast-permission /opt/broadcast-permission-runtime /opt/input/broadcast-permission.apk 10146 10146 /var/lib/broadcast-permission-r1
```

Keep guest input idle through UART export END. Preserve the full UART and derive
one exact interval using [uart-snapshot.md](uart-snapshot.md). The unchanged
no-removal diagnostic import must retain all chunks and validate the exact six
identities, eleven checks, complete child log and clean exit; it does not extend
strict fixture-protocol qualification. Release with
`umount /opt/broadcast-permission-runtime` after validation before separate
GMS/Maps. Preserve failures without weakening diagnostics.
