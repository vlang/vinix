# EventLog fixture delivery, 2026-11-02

The additive runner selector `--event-log` selects the EventLog successor
framework, retained native library and separate signed fixture. Transfer
selector `serve --event-log-api` exposes exactly `/event-log-api-run` and
`/event-log.apk`. Every historical selector, route and pin remains unchanged,
including the explicitly scoped Messenger v1/v2 shared-APK exception.

The independent [Main/Poison fixture](event-log-fixture-host.md) checks all five public static EventLog
write overloads, their primitive-int return and varargs metadata, scalar and
boxed types, nulls, first-255-item selection, encoding boundaries/error order
and unchanged caller arrays. Accepted inputs return -19 (-ENODEV) because the
binary event backend is unavailable; earlier encoding failures return -5 (-EIO),
and processed unsupported items throw the exact IllegalArgumentException.
The API-28 ART oracle uses a 4,064-byte payload budget: valid surrogate pairs
take four bytes, lone surrogates three and NUL two. The two application classes
are in `org.vinix.bootstrap`, with minSdk 28 and no platform stub, SDK override,
UID hardcode or worker. There is no event storage, positive delivery, payload
readback, logd persistence, logcat/stdout substitution, Google task completion,
Maps or authentication claim.

The frozen success marker is:

```text
EVENT-LOG-PASS five-overloads public-static varargs null-types prefix-255 encoding-boundaries error-order unchanged-arrays unavailable-backend
```

Six protected inputs, eleven receipt checks, isolated identity/data/home/surface,
explicit environment, closed inherited descriptors, 180/20-second deadlines,
4 MiB log and 8,192-byte line limits, exact PASS/READY pair, drained EOF and clean
child exit remain required. Health diagnostics are unchanged. Host qualification
and ARM execution remain separate.

Paths use `S=/Users/alex/.local/state/vinix/android`.

| Input | Path below S | SHA-256 |
| --- | --- | --- |
| Framework | `combined-account-webview-event-log-framework-2026-11-02-r1/api-impl.jar` | `0a331f5595b4b6c1298dd0e944389cbeabe2b93f6e02e536c4d26d5d200967ad` |
| Native | `current-native-build-2026-11-02-broadcast-permission-r1/native/libvinix-android-native.so` | `29b2631c36a4a8c802e904e936c23e090fb2de3b5019ac93548df1b15de2a8f1` |
| Fixture | `event-log-fixture-2026-11-02-r1/probe.apk` | `22d733567f05b56fe7b40183c83eea5b680b867771620f9440a14939835c2844` |
| ARM runner | `event-log-api-run-2026-11-02-r1/run` | `36a9b6f597cd620c0a4a9ff805a960fa8260fbb9278f3db853212e7ee6b763ff` |
| Transfer | `event-log-api-transfer-build-2026-11-02-r1/transfer` | `627154251855049e7e8915960e6030a0a5f5fba2901ec59436cc1b23f09f82c2` |

The signed fixture build receipt hashes to
`53a2aa229233bdfc0f58402c1bc4a41ecdd04cb42b3b144663e481f929849efd`.
All five delivery qualification phases passed on their first attempts. The
runner selftest rejected 4,307 malformed/mixed/failure cases. Transfer tests
retain binary snapshots, GET-only requests, traversal, absolute deadlines and
all historical checks, adding exact EventLog selector/port refusals and asset
path/hash/URL uniqueness checks against every predecessor. The narrow shared
Messenger APK exception is unchanged. ELF inspection confirms static AArch64
EXEC without INTERP or DYNAMIC segments.

| Check | Guard seconds | Sampled aggregate RSS bytes | Time maximum bytes |
| --- | ---: | ---: | ---: |
| Host runner compile | 1.451 | 360,955,904 | 373,424,128 |
| Runner selftest | 1.292 | 22,691,840 | 17,940,480 |
| Static ARM runner compile | 2.023 | 378,880,000 | 374,996,992 |
| Host transfer compile | 1.829 | 427,704,320 | 439,123,968 |
| Transfer selftest | 1.341 | 10,010,624 | 12,812,288 |

Every guard/child exit is zero, reason empty, cleanup complete and swaps zero
under the original 600 MiB RSS, 300-second, 512 MiB shared-growth, 1 GiB reserve,
4 MiB output and shell file-size cap 16777216 limits. Compilers were serialized.
SDK manifest/build/JAR/DEX, fixture receipt/APK, native manifest/build/DSO, tool
and predecessor pins were independently rehashed before and after checks.
Frozen sources equal the checkout. Both source bases are
`460a026d54191e0a8c5e64fc35ea7022981fe2ec`; runner/transfer source hashes are
respectively `cf4786f92428136c75484fdee62bdd54e295cafc8d218e4041dad2ff221173b2`
and `3313a44a45c1ee532c77e4073e758d543783a27a547735ce8788a210db29a2ee`.

Four complete tool/control roots passed sealing and separate fresh-process
readback for 35 entries. The manifest at
`S/event-log-api-tools-sealed-2026-11-02-r1/manifest.json` hashes to
`0f377d451d18bf0d1f863514a2b0dede4f4c5c5b5fd09d72449ea64dd3ad28c1`.
Seal/readback guards took 91/301 ms, both guard/child exits zero and cleanup
complete under the same RSS/reserve/output/file caps and 64 MiB growth. Controls
remain in `S/event-log-api-tools-seal-controls-2026-11-02-r1`.

## Guest recipe

Verify that `event-log-probe`, UID/GID 10151, the runtime mount and output path
are absent. Provision and confirm the exact account:

```sh
grep -nE '(^event-log-probe:|:10151:)' /etc/passwd /etc/group
/usr/sbin/addgroup -g 10151 event-log-probe
/usr/sbin/adduser -D -H -u 10151 -G event-log-probe -s /bin/false event-log-probe
grep -nE '^event-log-probe:' /etc/passwd /etc/group
grep ' /opt/event-log-runtime ' /proc/self/mounts
test ! -e /var/lib/event-log-r1
mkdir /opt/event-log-runtime
mount -o bind /opt/vinix-android-aarch64 /opt/event-log-runtime
mount -o remount,bind,ro,nosuid,nodev,strictatime,wxallowed none /opt/event-log-runtime
grep ' /opt/event-log-runtime ' /proc/self/mounts
mkdir -p /opt/input
```

Require read-only `nosuid,nodev,wxallowed` attachment without `noexec`. Start the
qualified host transfer only when the guest is ready to fetch:

```sh
S=/Users/alex/.local/state/vinix/android
"$S/event-log-api-transfer-build-2026-11-02-r1/transfer" serve --event-log-api "$S/event-log-api-transfer-live-2026-11-02-r1" 55544
```

Download and verify both hashes before launch:

```sh
wget -O /opt/input/event-log-run http://10.0.2.2:55544/event-log-api-run
wget -O /opt/input/event-log.apk http://10.0.2.2:55544/event-log.apk
chmod 755 /opt/input/event-log-run
chmod 644 /opt/input/event-log.apk
sha256sum /opt/input/event-log-run /opt/input/event-log.apk
/opt/input/event-log-run --event-log /opt/event-log-runtime /opt/input/event-log.apk 10151 10151 /var/lib/event-log-r1
```

Keep guest input idle through UART export END. Preserve the full UART and derive
one exact interval using [uart-snapshot.md](uart-snapshot.md). The unchanged
no-removal diagnostic import must retain every chunk and validate all six input
identities, eleven checks, full child log and clean exit; it does not extend
strict fixture-protocol qualification. Release with
`umount /opt/event-log-runtime` after validation before separate GMS/Maps.
Preserve failures without weakening diagnostics.
