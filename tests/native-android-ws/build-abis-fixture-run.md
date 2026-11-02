# Build ABI fixture delivery

The additive runner selector `--build-abis` selects the Build ABI successor
framework, retained native library and separate signed fixture. Transfer selector
`serve --build-abis-api` exposes exactly `/build-abis-api-run` and
`/build-abis.apk`. Every historical selector, route and pin remains unchanged,
including the explicitly scoped Messenger v1/v2 shared-APK exception.

The independent [one-Main fixture](build-abis-fixture-host.md) checks the real
Process.is64Bit and `os.arch` observations before requiring aarch64 values.
Those printed observations remain pending ARM execution. It checks exact public
static final String[] metadata and ordered ALL/64-bit values of `arm64-v8a`,
an empty 32-bit list, CPU primary/secondary and existing property consistency.
The three public arrays must be distinct and retain stable field identities.
Element mutation must leave the other array and capability properties unchanged;
finally cleanup restores the exact original elements before baseline rechecks.

The private property-list helper must return fresh arrays for missing, empty,
ordered, whitespace and separator cases. Only the unique fixture property is
changed through the existing process-local Properties object; finally cleanup
restores its exact prior presence and Object. The fixture supplies only
`org.vinix.bootstrap.Main`, retains minSdk 28 and has no worker, runtime path,
UID hardcode or platform stub. Real capability properties, `os.arch`, Build.VERSION
and SDK state remain untouched. There is no native-library loading, 32-bit
execution, Google module completion, Maps or authentication claim.

The frozen success marker is:

```text
BUILD-ABIS-PASS measured-arm64 public-static-final ordered-arrays empty-32 independent-mutable stable-fields fresh-helper custom-property-restored
```

Six protected inputs, eleven receipt checks, isolated identity/data/home/surface,
explicit environment, closed inherited descriptors, 180/20-second deadlines,
4 MiB log and 8,192-byte line limits, exact PASS/READY pair, drained EOF and clean
child exit remain required. Health diagnostics are unchanged. Host qualification
and ARM execution remain separate.

Paths use `S=/Users/alex/.local/state/vinix/android`; the new artifact roots retain
the campaign identifier `2026-11-02-r1`.

| Input | Path below S | SHA-256 |
| --- | --- | --- |
| Framework | `combined-account-webview-build-abis-framework-2026-11-02-r1/api-impl.jar` | `251753fdee85367880a9b0c48d1cb0058fd17a819e4651a8dc29f232673f531f` |
| Native | `current-native-build-2026-11-02-broadcast-permission-r1/native/libvinix-android-native.so` | `29b2631c36a4a8c802e904e936c23e090fb2de3b5019ac93548df1b15de2a8f1` |
| Fixture | `build-abis-fixture-2026-11-02-r1/probe.apk` | `2036c430d632f7fbca0cfbbe2c0c975b146e80686934fc482ae59ab9662b439a` |
| ARM runner | `build-abis-api-run-2026-11-02-r1/run` | `31fe9f0fe8d80ac5c568d380fb0317afba9fc672f8c490d5b8289aea3b80d1ff` |
| Transfer | `build-abis-api-transfer-build-2026-11-02-r1/transfer` | `e7f556f4ad7144045f547d27b961fc6afbe5dad54b7de32c90285c45aaf42cea` |

The signed fixture build receipt hashes to
`1fc189dbcbd26ad3247d8f0d1926e33e25ab63e82b2716310c2f94a1cef89705`.
All five delivery qualification phases passed on their first attempts. The
runner selftest rejected 4,497 malformed/mixed/failure cases. Transfer tests
retain binary snapshots, GET-only requests, traversal, absolute deadlines and
all historical checks, adding exact Build ABIs selector/port refusals and asset
path/hash/URL uniqueness checks against every predecessor. The narrow shared
Messenger APK exception is unchanged. ELF inspection confirms static AArch64
EXEC without INTERP or DYNAMIC segments.

| Check | Guard seconds | Sampled aggregate RSS bytes | Time maximum bytes |
| --- | ---: | ---: | ---: |
| Host runner compile | 2.299 | 353,697,792 | 366,854,144 |
| Runner selftest | 2.028 | 22,364,160 | 17,956,864 |
| Static ARM runner compile | 2.923 | 376,684,544 | 364,429,312 |
| Host transfer compile | 2.891 | 430,768,128 | 444,743,680 |
| Transfer selftest | 1.988 | 13,713,408 | 12,484,608 |

Every guard/child exit is zero, reason empty, cleanup complete and swaps zero
under the original 600 MiB RSS, 300-second, 512 MiB shared-growth, 1 GiB reserve,
4 MiB output and shell file-size cap 16777216 limits. Compilers were serialized.
SDK manifest/build/JAR/DEX, fixture receipt/APK, native manifest/build/DSO, tool
and predecessor pins were independently rehashed before and after checks.
Frozen sources equal the checkout. Both source bases are
`0d6272593dd7ef76d61853ac56a498b29c8615de`; runner/transfer source hashes are
respectively `2ab1b9da3d7b4ace015b0cddd93dee7841c2f1362622a7a1fb155fdf54997b4d`
and `4effedfd316df83cbb0abfde8eb66accc08ba7227c07ec397001024a59c2d2bb`.

Four complete tool/control roots passed sealing and separate fresh-process
readback for 35 entries. The manifest at
`S/build-abis-api-tools-sealed-2026-11-02-r1/manifest.json` hashes to
`ca7d9bf2fe0329794ee40190b0defd87f0cadb0bb72e1cc95a5e89938f76f9b7`.
Seal/readback guards took 132/258 ms, both guard/child exits zero and cleanup
complete under the same RSS/reserve/output/file caps and 64 MiB growth. Controls
remain in `S/build-abis-api-tools-seal-controls-2026-11-02-r1`.

## Guest recipe

Verify that `build-abis-probe`, UID/GID 10152, the runtime mount and output path
are absent. Provision and confirm the exact account:

```sh
grep -nE '(^build-abis-probe:|:10152:)' /etc/passwd /etc/group
/usr/sbin/addgroup -g 10152 build-abis-probe
/usr/sbin/adduser -D -H -u 10152 -G build-abis-probe -s /bin/false build-abis-probe
grep -nE '^build-abis-probe:' /etc/passwd /etc/group
grep ' /opt/build-abis-runtime ' /proc/self/mounts
test ! -e /var/lib/build-abis-r1
mkdir /opt/build-abis-runtime
mount -o bind /opt/vinix-android-aarch64 /opt/build-abis-runtime
mount -o remount,bind,ro,nosuid,nodev,strictatime,wxallowed none /opt/build-abis-runtime
grep ' /opt/build-abis-runtime ' /proc/self/mounts
mkdir -p /opt/input
```

Require read-only `nosuid,nodev,wxallowed` attachment without `noexec`. Start the
qualified host transfer only when the guest is ready to fetch:

```sh
S=/Users/alex/.local/state/vinix/android
"$S/build-abis-api-transfer-build-2026-11-02-r1/transfer" serve --build-abis-api "$S/build-abis-api-transfer-live-2026-11-02-r1" 55545
```

Download and verify both hashes before launch:

```sh
wget -O /opt/input/build-abis-run http://10.0.2.2:55545/build-abis-api-run
wget -O /opt/input/build-abis.apk http://10.0.2.2:55545/build-abis.apk
chmod 755 /opt/input/build-abis-run
chmod 644 /opt/input/build-abis.apk
sha256sum /opt/input/build-abis-run /opt/input/build-abis.apk
/opt/input/build-abis-run --build-abis /opt/build-abis-runtime /opt/input/build-abis.apk 10152 10152 /var/lib/build-abis-r1
```

Keep guest input idle through UART export END. Preserve the full UART and derive
one exact interval using [uart-snapshot.md](uart-snapshot.md). The unchanged
no-removal diagnostic import must retain every chunk and validate all six input
identities, eleven checks, full child log and clean exit; it does not extend
strict fixture-protocol qualification. Release with
`umount /opt/build-abis-runtime` after validation before separate GMS/Maps.
Preserve failures without weakening diagnostics.
