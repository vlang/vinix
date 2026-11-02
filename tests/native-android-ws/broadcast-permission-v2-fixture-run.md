# Broadcast permission V2 fixture delivery, 2026-11-02

The additive runner selector `--broadcast-permission-v2` uses the same framework
and coupled native library as V1, with the separately signed r3 fixture. Transfer
selector `serve --broadcast-permission-v2-api` exposes exactly
`/broadcast-permission-v2-api-run` and `/broadcast-permission-v2.apk`. Original V1
selectors, r2 APK pin, routes and all historical identities remain unchanged.

The exact success marker is:

```text
BROADCAST-PERMISSION-V2-PASS actual-delivery signature-owned null-legacy denied-permissions fake-grants immutable-authority metadata-restored async-barriers bounded-startup
```

The [first ARM run](maps-broadcast-permission-runtime-2026-11-02.md) rejected r2
before Main.onCreate because the cleanup receiver register had Conflict type.
The [eight-class V2 fixture](broadcast-permission-v2-fixture-host.md) separates
construction scratch and cleanup register lifetimes and uses ReadyHandlerThread
for bounded startup with a captured Looper. All original actual dynamic/primary
manifest delivery, permission denial, forgery, immutable authority and metadata
restoration assertions remain. Dynamic callbacks use a dedicated HandlerThread;
manifest dispatch is synchronous. Registered sender permissions, category/data
matching, export rules and cross-process delivery remain outside this fixture.
V2 supplies no platform stub, real permission grant or health exemption; forged
Context/PackageManager grants are negative controls.

The generic runner retains six protected input identities, eleven receipt
checks, isolated identity/data/home/surface, explicit environment, closed inherited
descriptors, 180/20-second deadlines, 4 MiB log and 8,192-byte line limits, one
exact PASS/READY pair, drained EOF and clean child exit. These host checks do not
establish an ARM verifier pass, functional broadcast delivery, GMS or Google login.

Paths below use `S=/Users/alex/.local/state/vinix/android`.

| Input | Path below S | SHA-256 |
| --- | --- | --- |
| Framework | `combined-account-webview-broadcast-permission-framework-2026-11-02-r1/api-impl.jar` | `9e998094f8e122c22195e0c9a8f79377dbf16cd04d321ab4d1a47650908082f9` |
| Native | `current-native-build-2026-11-02-broadcast-permission-r1/native/libvinix-android-native.so` | `29b2631c36a4a8c802e904e936c23e090fb2de3b5019ac93548df1b15de2a8f1` |
| V2 fixture | `broadcast-permission-fixture-2026-11-02-r3/probe.apk` | `8c6446247e9660eb58c54a166c839abe4e372403620d727fa004bafd847d41a3` |
| ARM runner | `broadcast-permission-v2-api-run-2026-11-02-r1/run` | `4b7de3a657bb55efd4ee80dee23cdaaf7677b070518e594d270af6232005f5e0` |
| Transfer | `broadcast-permission-v2-api-transfer-build-2026-11-02-r1/transfer` | `5d467eb5f3e761f103cbc00e910b29616af932d5c8de8a37a9ba9d7479a7eb38` |

The r3 fixture build receipt hashes to
`bfee2ae4d948f893bcc0b1c9a92fe3d27a187a5cdbe2718c8510976dd13fe691`.
All five delivery qualification phases passed on their first attempts. The
runner selftest rejected 3,421 malformed/mixed/failure cases. Transfer tests
retain binary snapshots, GET-only requests, traversal and absolute deadlines,
adding exact V2 selector/port refusal and route/path/hash uniqueness checks
against every historical profile, including V1. ELF inspection confirms static
AArch64 EXEC without INTERP or DYNAMIC segments.

| Check | Guard seconds | Sampled aggregate RSS bytes | Time maximum bytes |
| --- | ---: | ---: | ---: |
| Host runner compile | 1.401 | 356,040,704 | 375,144,448 |
| Runner selftest | 1.275 | 21,872,640 | 17,907,712 |
| Static ARM runner compile | 1.850 | 375,717,888 | 374,128,640 |
| Host transfer compile | 1.700 | 388,382,720 | 419,201,024 |
| Transfer selftest | 1.154 | 10,846,208 | 11,337,728 |

Every guard/child exit is zero, reason empty, cleanup complete and swaps zero
under the original 600 MiB RSS, 300-second, 512 MiB shared-growth, 1 GiB reserve,
4 MiB output and shell file-size cap 16777216 limits. Compilers were serialized.
SDK manifest/build/JAR/DEX, r3 fixture receipt/APK, native manifest/build/DSO, tool
and V1 predecessor pins were independently rehashed before and after checks.
Frozen sources equal the checkout. Both source bases are
`8d9b867939c7a624be5d9c6a6113a1485fe2fb3e`; runner/transfer source hashes are
respectively `4ab19975aa7b9abf2194d7937f2c5e60567940d926927bc827892967c5f2a707`
and `9a349220f2b7654c678810d346b43d4c1381ad70f425e6c2fcafee7b954f1acc`.

Six complete qualification roots passed sealing and separate fresh-process
readback for 112 entries: r3 fixture and its controls plus four delivery
tool/control roots. The manifest at
`S/broadcast-permission-v2-api-tools-sealed-2026-11-02-r1/manifest.json` hashes to
`afd0380c1beb2ae441a3beb74e3dc05a29c652872716c4006f4d360607cbefd4`.
Seal/readback guards took 51/243 ms, both guard/child exits zero and cleanup
complete under the same RSS/reserve/output/file caps and 64 MiB growth. Controls
remain in `S/broadcast-permission-v2-api-tools-seal-controls-2026-11-02-r1`.
The original SDK/native and failed ARM bundles remain separate and unchanged.
Independent source, final artifact and report reviews approved the exact pins,
marker, unchanged health policy, static ELF, guards, source copies and recipe.

## Guest recipe

Verify that `broadcast-permission-v2-probe`, UID/GID 10147, the dedicated runtime
mount and output path are absent. Provision and confirm the exact account:

```sh
grep -nE '(^broadcast-permission-v2-probe:|:10147:)' /etc/passwd /etc/group
/usr/sbin/addgroup -g 10147 broadcast-permission-v2-probe
/usr/sbin/adduser -D -H -u 10147 -G broadcast-permission-v2-probe -s /bin/false broadcast-permission-v2-probe
grep -nE '^broadcast-permission-v2-probe:' /etc/passwd /etc/group
grep ' /opt/broadcast-permission-v2-runtime ' /proc/self/mounts
test ! -e /var/lib/broadcast-permission-v2-r1
mkdir /opt/broadcast-permission-v2-runtime
mount -o bind /opt/vinix-android-aarch64 /opt/broadcast-permission-v2-runtime
mount -o remount,bind,ro,nosuid,nodev,strictatime,wxallowed none /opt/broadcast-permission-v2-runtime
grep ' /opt/broadcast-permission-v2-runtime ' /proc/self/mounts
mkdir -p /opt/input
```

Require read-only `nosuid,nodev,wxallowed` attachment without `noexec`. Start the
qualified host transfer with a fresh output only when the guest is ready to fetch:

```sh
S=/Users/alex/.local/state/vinix/android
"$S/broadcast-permission-v2-api-transfer-build-2026-11-02-r1/transfer" serve --broadcast-permission-v2-api "$S/broadcast-permission-v2-api-transfer-live-2026-11-02-r1" 55539
```

Download and verify both hashes before launch:

```sh
wget -O /opt/input/broadcast-permission-v2-run http://10.0.2.2:55539/broadcast-permission-v2-api-run
wget -O /opt/input/broadcast-permission-v2.apk http://10.0.2.2:55539/broadcast-permission-v2.apk
chmod 755 /opt/input/broadcast-permission-v2-run
chmod 644 /opt/input/broadcast-permission-v2.apk
sha256sum /opt/input/broadcast-permission-v2-run /opt/input/broadcast-permission-v2.apk
/opt/input/broadcast-permission-v2-run --broadcast-permission-v2 /opt/broadcast-permission-v2-runtime /opt/input/broadcast-permission-v2.apk 10147 10147 /var/lib/broadcast-permission-v2-r1
```

Keep guest input idle through UART export END. Preserve the full UART and derive
one exact interval using [uart-snapshot.md](uart-snapshot.md). The unchanged
no-removal diagnostic import must retain all chunks and validate the exact six
identities, eleven checks, complete child log and clean exit; it does not extend
strict fixture-protocol qualification. Release with
`umount /opt/broadcast-permission-v2-runtime` after validation before separate
GMS/Maps. Preserve failures without weakening diagnostics.
