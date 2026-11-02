# Disabled AppStandby fixture delivery, 2026-11-02

The additive runner selector `--usage-inactive` requires its successor framework,
retained broadcast native library and signed one-class fixture. Transfer selector
`serve --usage-inactive-api` exposes exactly `/usage-inactive-api-run` and
`/usage-inactive.apk`. Historical selectors, routes and identities remain unchanged.

The exact success marker is:

```text
USAGE-INACTIVE-PASS public-instance typed-service constructor arbitrary-packages null-empty-unicode repeat-32 legacy-service-null disabled-policy
```

The [fixture](usage-inactive-fixture-host.md) checks the public instance
UsageStatsManager.isAppInactive(String) query through real typed Activity and
application service managers and the public constructor. Seven argument cases
run for 32 rounds through seven manager sequences, making 1,568 real queries.
Own, GMS, Maps, unknown, empty, null and Unicode package arguments all return
false because AppStandby classification is disabled. Legacy string `usagestats`
lookup remains null. The only APK class is the fixture's application Main;
minSdk is 28, with no platform stub or SDK override.

False describes disabled policy. It does not establish measured usage history,
foreground state, permission enforcement, Google Play Services, Maps or
authentication. There is no fake usage backend or permission grant.

The runner retains six protected input identities, eleven receipt checks,
isolated identity/data/home/surface, explicit environment, closed inherited
descriptors, 180/20-second deadlines, 4 MiB log and 8,192-byte line limits, one
exact PASS/READY pair, drained EOF and clean child exit. Health diagnostics remain
unchanged. Host qualification is separate from ARM execution.

Paths below use `S=/Users/alex/.local/state/vinix/android`.

| Input | Path below S | SHA-256 |
| --- | --- | --- |
| Framework | `combined-account-webview-usage-inactive-framework-2026-11-02-r1/api-impl.jar` | `d7b6d8c37d5d09d200c19b429f07cf6666ed6d8cf5a1a1b4d29c0dfd27cd632b` |
| Native | `current-native-build-2026-11-02-broadcast-permission-r1/native/libvinix-android-native.so` | `29b2631c36a4a8c802e904e936c23e090fb2de3b5019ac93548df1b15de2a8f1` |
| Fixture | `usage-inactive-fixture-2026-11-02-r1/probe.apk` | `ae580b4c0ed99b97787f552d8e6f08a94daeed137fc346440cea832a7795a3d2` |
| ARM runner | `usage-inactive-api-run-2026-11-02-r1/run` | `d2adc8c54ccfdda67845e0d8b29f0ee4204dbb5066ab2487dc41129a95f7b179` |
| Transfer | `usage-inactive-api-transfer-build-2026-11-02-r1/transfer` | `d322b7ac5cc13d05390712973015e65b9ba2cce801ed0cfacf450254f20253e5` |

The signed fixture build receipt hashes to
`beee74016585a4a814d7dcb41573ef4e0b4e983adf8e23659767af27d571dc78`.
All five delivery qualification phases passed on their first attempts. The
runner selftest rejected 3,765 malformed/mixed/failure cases. Transfer tests
retain binary snapshots, GET-only requests, traversal and absolute deadlines,
adding exact selector/port refusal and route/path/hash uniqueness checks against
all historical profiles. ELF inspection confirms static AArch64 EXEC without
INTERP or DYNAMIC segments.

| Check | Guard seconds | Sampled aggregate RSS bytes | Time maximum bytes |
| --- | ---: | ---: | ---: |
| Host runner compile | 1.462 | 346,652,672 | 377,618,432 |
| Runner selftest | 1.272 | 22,298,624 | 17,907,712 |
| Static ARM runner compile | 1.923 | 373,276,672 | 371,163,136 |
| Host transfer compile | 1.736 | 391,561,216 | 421,527,552 |
| Transfer selftest | 1.147 | 10,829,824 | 11,862,016 |

Every guard/child exit is zero, reason empty, cleanup complete and swaps zero
under the original 600 MiB RSS, 300-second, 512 MiB shared-growth, 1 GiB reserve,
4 MiB output and shell file-size cap 16777216 limits. Compilers were serialized.
SDK manifest/build/JAR/DEX, fixture receipt/APK, native manifest/build/DSO, tool
and predecessor pins were independently rehashed before and after checks.
Frozen sources equal the checkout. Both source bases are
`11d8ae664efc2b0704f4352553200510f96ef0eb`; runner/transfer source hashes are
respectively `24e78a97602b53c99b2e795ff127e87f066e1809ddfbafd24c8cdbafabc841cf`
and `4e6f7be3c9426368aba7e60ee4ed4a29d817c3d06d955be050804ada04f70e26`.

Four complete tool/control roots passed sealing and separate fresh-process
readback for 35 entries. The manifest at
`S/usage-inactive-api-tools-sealed-2026-11-02-r1/manifest.json` hashes to
`35662a4aa48312ac6f58c3d00e9377bebf7629f2bb3be5edea7d64b46a90dd0b`.
Seal/readback guards took 59/249 ms, both guard/child exits zero and cleanup
complete under the same RSS/reserve/output/file caps and 64 MiB growth. Controls
remain in `S/usage-inactive-api-tools-seal-controls-2026-11-02-r1`.

## Guest recipe

Verify that `usage-inactive-probe`, UID/GID 10149, the dedicated runtime mount
and output path are absent. Provision and confirm the exact account:

```sh
grep -nE '(^usage-inactive-probe:|:10149:)' /etc/passwd /etc/group
/usr/sbin/addgroup -g 10149 usage-inactive-probe
/usr/sbin/adduser -D -H -u 10149 -G usage-inactive-probe -s /bin/false usage-inactive-probe
grep -nE '^usage-inactive-probe:' /etc/passwd /etc/group
grep ' /opt/usage-inactive-runtime ' /proc/self/mounts
test ! -e /var/lib/usage-inactive-r1
mkdir /opt/usage-inactive-runtime
mount -o bind /opt/vinix-android-aarch64 /opt/usage-inactive-runtime
mount -o remount,bind,ro,nosuid,nodev,strictatime,wxallowed none /opt/usage-inactive-runtime
grep ' /opt/usage-inactive-runtime ' /proc/self/mounts
mkdir -p /opt/input
```

Require read-only `nosuid,nodev,wxallowed` attachment without `noexec`. Start the
qualified host transfer with a fresh output only when the guest is ready to fetch:

```sh
S=/Users/alex/.local/state/vinix/android
"$S/usage-inactive-api-transfer-build-2026-11-02-r1/transfer" serve --usage-inactive-api "$S/usage-inactive-api-transfer-live-2026-11-02-r1" 55541
```

Download and verify both hashes before launch:

```sh
wget -O /opt/input/usage-inactive-run http://10.0.2.2:55541/usage-inactive-api-run
wget -O /opt/input/usage-inactive.apk http://10.0.2.2:55541/usage-inactive.apk
chmod 755 /opt/input/usage-inactive-run
chmod 644 /opt/input/usage-inactive.apk
sha256sum /opt/input/usage-inactive-run /opt/input/usage-inactive.apk
/opt/input/usage-inactive-run --usage-inactive /opt/usage-inactive-runtime /opt/input/usage-inactive.apk 10149 10149 /var/lib/usage-inactive-r1
```

Keep guest input idle through UART export END. Preserve the full UART and derive
one exact interval using [uart-snapshot.md](uart-snapshot.md). The unchanged
no-removal diagnostic import must retain all chunks and validate the exact six
identities, eleven checks, complete child log and clean exit; it does not extend
strict fixture-protocol qualification. Release with
`umount /opt/usage-inactive-runtime` after validation before separate GMS/Maps.
Preserve failures without weakening diagnostics.
