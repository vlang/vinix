# Autofill service fixture delivery, 2026-11-02

The additive runner selector `--autofill-service` requires the successor
framework, retained native pair and signed fixture. Transfer selector
`serve --autofill-service-api` exposes exactly `/autofill-service-api-run` and
`/autofill-service.apk`. Historical profiles, routes and pins remain unchanged.

The exact success marker is:

```text
AUTOFILL-SERVICE-PASS typed-manager string-null component-null public-instance null-branch notifications typed-values
```

The fixture exercises real typed managers, the existing null string lookup,
public instance query shape, repeated absent-component results and the called
GMS-like null-to-false branch. It also checks inactive notifications and ordinary
AutofillValue text, toggle, list and date values. It supplies no platform stub or
autofill provider and makes no cache-identity assertion. The generic runner
retains six protected input identities, eleven receipt checks, isolated identity,
data/home/surface, explicit environment, closed inherited descriptors, the
180/20-second deadlines, 4 MiB log and 8,192-byte line limits, one exact PASS/READY
pair, drained EOF and clean child exit. Existing health diagnostics stay intact.
These host results do not establish ARM execution, GMS, Maps or authentication.

Paths below use `S=/Users/alex/.local/state/vinix/android`.

| Input | Path below S | SHA-256 |
| --- | --- | --- |
| Framework | `combined-account-webview-autofill-service-framework-2026-11-02-r1/api-impl.jar` | `e2bea62dcd6f59269c36612f76b806942018700f37fbf202915cc2e74329a54a` |
| Native | `current-native-build-2026-11-02-asset-locales-r1/native/libvinix-android-native.so` | `c87ccc623d70b1d582cd5486a9a6316c5117091ca10113682aa07cc72c80912f` |
| Fixture | `autofill-service-fixture-2026-11-02-r1/probe.apk` | `e9e3e6ce83e99f439550d494438fb3d245d67d74be3f915dcecf83b7c452e360` |
| ARM runner | `autofill-service-api-run-2026-11-02-r1/run` | `ba3c6e2a2b88406441210b2f58113e6b70fcdba43e36600aa17b3da07644af69` |
| Transfer | `autofill-service-api-transfer-build-2026-11-02-r1/transfer` | `d16eed7e257ea29d58347f1fb2bf5df32add9550c5ef5d6b539da9c4af77da48` |

The fixture build receipt hashes to
`2e2041b34354fcb6ac7e0e8105b1e54eb23caa3c585df482a0135ce5f2ba1359`.
SDK manifest/build pins were rechecked alongside JAR, DEX, APK and native bytes.
All five qualification phases passed on their first attempts. The runner
selftest rejected 2,935 malformed/mixed/failure cases; transfer tests retain
historical binary snapshots, GET-only requests, traversal and absolute deadlines,
adding the exact selector, port and route/path/hash uniqueness cases. ELF
inspection confirms static AArch64 EXEC without INTERP or DYNAMIC segments.

| Check | Guard seconds | Sampled aggregate RSS bytes | Time maximum bytes |
| --- | ---: | ---: | ---: |
| Host runner compile | 1.393 | 342,556,672 | 364,199,936 |
| Runner selftest | 1.041 | 21,921,792 | 17,891,328 |
| Static ARM runner compile | 1.832 | 373,768,192 | 368,803,840 |
| Host transfer compile | 1.665 | 377,831,424 | 403,406,848 |
| Transfer selftest | 1.037 | 10,764,288 | 11,042,816 |

Every guard/child exit is zero, reason empty, cleanup complete and swaps zero
under the original 600 MiB RSS, 300-second, 512 MiB shared-growth, 1 GiB reserve,
4 MiB output and shell file-size cap 16777216 limits. Compilers were serialized.
Runtime/tool/predecessor identities were freshly rehashed afterward; frozen
sources equal the checkout. Source base is `c58ed4fc08041c4e18ed375d785d4e07a67d820e`.
Runner/transfer source hashes are respectively
`f2fd3c56c248f7c4ccfdfd0229aef6fce652c09f6654144b2d0e15cc2d02c49e`
and `9b70b12c639662d2645b16468160169136dfc1aee1295bdf094ed0a4202f8148`.

Four complete tool/control roots passed sealing and separate fresh-process
readback for 35 entries. The manifest at
`S/autofill-service-api-tools-sealed-2026-11-02-r1/manifest.json` hashes to
`a993aa3fd82c798e6de4094836d3298eaf84d669bf709a76378e68bd11442266`.
Seal/readback guard durations are 48/118 ms, both guard/child exits zero with
complete cleanup under the same RSS/reserve/output/file caps and 64 MiB growth.
Controls remain in `S/autofill-service-api-tools-seal-controls-2026-11-02-r1`.
Independent draft and final source/artifact/report reviews approved the exact
pins, marker, static ELF, guards, source copies, seal and guest recipe.

## Guest recipe

Verify that `autofill-service-probe`, UID/GID 10144, the dedicated runtime mount
and output path are absent. Provision and confirm the exact account:

```sh
grep -nE '(^autofill-service-probe:|:10144:)' /etc/passwd /etc/group
/usr/sbin/addgroup -g 10144 autofill-service-probe
/usr/sbin/adduser -D -H -u 10144 -G autofill-service-probe -s /bin/false autofill-service-probe
grep -nE '^autofill-service-probe:' /etc/passwd /etc/group
grep ' /opt/autofill-service-runtime ' /proc/self/mounts
test ! -e /var/lib/autofill-service-r1
mkdir /opt/autofill-service-runtime
mount -o bind /opt/vinix-android-aarch64 /opt/autofill-service-runtime
mount -o remount,bind,ro,nosuid,nodev,strictatime,wxallowed none /opt/autofill-service-runtime
grep ' /opt/autofill-service-runtime ' /proc/self/mounts
mkdir -p /opt/input
```

Require read-only `nosuid,nodev,wxallowed` attachment without `noexec`. Start the
qualified host transfer with a fresh output only when the guest is ready to fetch:

```sh
S=/Users/alex/.local/state/vinix/android
"$S/autofill-service-api-transfer-build-2026-11-02-r1/transfer" serve --autofill-service-api "$S/autofill-service-api-transfer-live-2026-11-02-r1" 55536
```

Download and verify both hashes before launch:

```sh
wget -O /opt/input/autofill-service-run http://10.0.2.2:55536/autofill-service-api-run
wget -O /opt/input/autofill-service.apk http://10.0.2.2:55536/autofill-service.apk
chmod 755 /opt/input/autofill-service-run
chmod 644 /opt/input/autofill-service.apk
sha256sum /opt/input/autofill-service-run /opt/input/autofill-service.apk
/opt/input/autofill-service-run --autofill-service /opt/autofill-service-runtime /opt/input/autofill-service.apk 10144 10144 /var/lib/autofill-service-r1
```

Keep guest input idle through UART export END. Preserve the full UART and derive
one exact interval using [uart-snapshot.md](uart-snapshot.md). The unchanged
no-removal diagnostic import must retain all chunks and validate the exact six
identities, eleven checks, complete child log and clean exit; it does not extend
strict fixture-protocol qualification. Release with
`umount /opt/autofill-service-runtime` after validation before separate GMS/Maps.
Preserve failures without weakening diagnostics.
