# Secure settings and tile fixture delivery, 2026-11-02

The additive runner selector `--secure-settings` requires the successor framework,
retained broadcast native library and signed four-class fixture. Transfer selector
`serve --secure-settings-api` exposes exactly `/secure-settings-api-run` and
`/secure-settings.apk`. All historical selectors, routes and identities remain
unchanged, including both broadcast-permission profiles.

The exact success marker is:

```text
SECURE-SETTINGS-PASS public-static virtual-insert secure-uri exact-string-null-values nearby-component empty-clear provider-result SQLException narrow-exceptions null-resolver absent-provider preserved-getters tile-broadcast intent-payload nullable-component fresh-intents inherited-static
```

The [fixture](secure-settings-fixture-host.md) checks public static Secure.putString
through real virtual ContentResolver insertion: exact secure URI, two String/null
entries, nearby component and empty clear, provider result, SQLException false,
other exception identity, null resolver and preserved getters. Activity/application
resolvers without a provider must return false. Thirteen recording resolver calls
exercise the positive, negative and recovery paths.

API-28 TileService checks capture the permission-aware broadcast, action/package,
exact nullable component extra, fresh intents, inherited static resolution and
exception propagation. Real Activity/application tile calls are smoke returns;
callback absence or SystemUI delivery is not inferred. Main, SettingsResolver,
RecordingContext and TileAdapter are the only APK classes, all in the fixture
package. There is no platform APK stub, foreground-user probe, status-bar backend,
permission grant or system SettingsProvider persistence claim.

The runner retains six protected input identities, eleven receipt checks,
isolated identity/data/home/surface, explicit environment, closed inherited
descriptors, 180/20-second deadlines, 4 MiB log and 8,192-byte line limits, one
exact PASS/READY pair, drained EOF and clean child exit. Health diagnostics remain
unchanged. Host qualification does not establish ARM, GMS, Maps or authentication.

Paths below use `S=/Users/alex/.local/state/vinix/android`.

| Input | Path below S | SHA-256 |
| --- | --- | --- |
| Framework | `combined-account-webview-secure-settings-framework-2026-11-02-r1/api-impl.jar` | `f7eef1e9b2a2a7730ce0b024823c9cc38dc1d510252dc6dccd30f1ada79f9768` |
| Native | `current-native-build-2026-11-02-broadcast-permission-r1/native/libvinix-android-native.so` | `29b2631c36a4a8c802e904e936c23e090fb2de3b5019ac93548df1b15de2a8f1` |
| Fixture | `secure-settings-fixture-2026-11-02-r1/probe.apk` | `1e2628151f851619bbae164f0c3a6830c354d11fe3f2104e584afe39482ccdd8` |
| ARM runner | `secure-settings-api-run-2026-11-02-r1/run` | `5a0e9319bee33804b3c406d6db9d1893ab4684e041c93db68147e2eaf075218a` |
| Transfer | `secure-settings-api-transfer-build-2026-11-02-r1/transfer` | `1e796e36a8e4b20d340b255bf92c3a220c24de81ed6131119df73a88a972db77` |

The signed fixture build receipt hashes to
`fdd8eacd953d3b125dd6087e4a2c5a28e3a84585fadb496ded23d4891a58e9fe`.
All five delivery qualification phases passed on their first attempts. The
runner selftest rejected 3,591 malformed/mixed/failure cases. Transfer tests
retain binary snapshots, GET-only requests, traversal and absolute deadlines,
adding exact selector/port refusal and route/path/hash uniqueness checks against
all historical profiles. ELF inspection confirms static AArch64 EXEC without
INTERP or DYNAMIC segments.

| Check | Guard seconds | Sampled aggregate RSS bytes | Time maximum bytes |
| --- | ---: | ---: | ---: |
| Host runner compile | 1.412 | 356,777,984 | 371,769,344 |
| Runner selftest | 1.368 | 21,708,800 | 17,924,096 |
| Static ARM runner compile | 1.874 | 373,817,344 | 372,015,104 |
| Host transfer compile | 1.674 | 378,667,008 | 417,562,624 |
| Transfer selftest | 1.151 | 10,813,440 | 11,763,712 |

Every guard/child exit is zero, reason empty, cleanup complete and swaps zero
under the original 600 MiB RSS, 300-second, 512 MiB shared-growth, 1 GiB reserve,
4 MiB output and shell file-size cap 16777216 limits. Compilers were serialized.
SDK manifest/build/JAR/DEX, fixture receipt/APK, native manifest/build/DSO, tool
and predecessor pins were independently rehashed before and after checks.
Frozen sources equal the checkout. Both source bases are
`a6e4192e2e45c79e957e2ed41639d396e22ebb3b`; runner/transfer source hashes are
respectively `3b71c7704b4f4438c20f468701f43095d3c62a315d9fbeab90f86b2aeda64d36`
and `0ea43ea5ff26623dee4bcfb98e843de9aa64a4ef3a8b53aa2dccb2636ca222b8`.

Four complete tool/control roots passed sealing and separate fresh-process
readback for 35 entries. The manifest at
`S/secure-settings-api-tools-sealed-2026-11-02-r1/manifest.json` hashes to
`9aba8f800a1c8ee2a29238613d8190cee1ce3b531e1b5264a77f3a7048f1ad75`.
Seal/readback guards took 46/132 ms, both guard/child exits zero and cleanup
complete under the same RSS/reserve/output/file caps and 64 MiB growth. Controls
remain in `S/secure-settings-api-tools-seal-controls-2026-11-02-r1`.
Independent source, final artifact and report reviews approved the exact pins,
marker, unchanged health policy, static ELF, guards, source copies and recipe.

## Guest recipe

Verify that `secure-settings-probe`, UID/GID 10148, the dedicated runtime mount
and output path are absent. Provision and confirm the exact account:

```sh
grep -nE '(^secure-settings-probe:|:10148:)' /etc/passwd /etc/group
/usr/sbin/addgroup -g 10148 secure-settings-probe
/usr/sbin/adduser -D -H -u 10148 -G secure-settings-probe -s /bin/false secure-settings-probe
grep -nE '^secure-settings-probe:' /etc/passwd /etc/group
grep ' /opt/secure-settings-runtime ' /proc/self/mounts
test ! -e /var/lib/secure-settings-r1
mkdir /opt/secure-settings-runtime
mount -o bind /opt/vinix-android-aarch64 /opt/secure-settings-runtime
mount -o remount,bind,ro,nosuid,nodev,strictatime,wxallowed none /opt/secure-settings-runtime
grep ' /opt/secure-settings-runtime ' /proc/self/mounts
mkdir -p /opt/input
```

Require read-only `nosuid,nodev,wxallowed` attachment without `noexec`. Start the
qualified host transfer with a fresh output only when the guest is ready to fetch:

```sh
S=/Users/alex/.local/state/vinix/android
"$S/secure-settings-api-transfer-build-2026-11-02-r1/transfer" serve --secure-settings-api "$S/secure-settings-api-transfer-live-2026-11-02-r1" 55540
```

Download and verify both hashes before launch:

```sh
wget -O /opt/input/secure-settings-run http://10.0.2.2:55540/secure-settings-api-run
wget -O /opt/input/secure-settings.apk http://10.0.2.2:55540/secure-settings.apk
chmod 755 /opt/input/secure-settings-run
chmod 644 /opt/input/secure-settings.apk
sha256sum /opt/input/secure-settings-run /opt/input/secure-settings.apk
/opt/input/secure-settings-run --secure-settings /opt/secure-settings-runtime /opt/input/secure-settings.apk 10148 10148 /var/lib/secure-settings-r1
```

Keep guest input idle through UART export END. Preserve the full UART and derive
one exact interval using [uart-snapshot.md](uart-snapshot.md). The unchanged
no-removal diagnostic import must retain all chunks and validate the exact six
identities, eleven checks, complete child log and clean exit; it does not extend
strict fixture-protocol qualification. Release with
`umount /opt/secure-settings-runtime` after validation before separate GMS/Maps.
Preserve failures without weakening diagnostics.
