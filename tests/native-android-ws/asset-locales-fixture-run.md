# Asset locales fixture tools, 2026-11-02

The additive `--asset-locales` runner profile requires its successor framework,
native asset-manager locale query and signed fixture. The transfer selector
`serve --asset-locales-api` serves exactly `/asset-locales-api-run` and
`/asset-locales.apk`. Historical profiles, pins and routes, including the
StableDisplay diagnostic r2 inputs, remain unchanged.

The exact success marker is:

```text
ASSET-LOCALES-PASS framework-app canonical-set fresh-arrays mutation-isolation default-locale device-secure
```

The fixture checks the exact canonical union of compiled framework/application
locale tables, fresh arrays, mutation isolation, independence from the default
locale and the absent Android credential backend's `isDeviceSecure()` result.
The generic runner retains six protected input pins, eleven receipt checks,
dedicated identity/data/home/surface, descriptor closure, bounded lifetime,
one exact PASS/READY pair, drained EOF and clean child exit. These fixture
contracts do not establish Google Play Services or authentication success.

Paths below use `S=/Users/alex/.local/state/vinix/android`.

| Input | Path below S | SHA-256 |
| --- | --- | --- |
| Framework | `combined-account-webview-device-secure-framework-2026-11-02-r1/api-impl.jar` | `43e3e2b941677cda70021ae9cd674aac6f4897af4ab4bda1d2d751b805d1f137` |
| Native | `current-native-build-2026-11-02-asset-locales-r1/native/libvinix-android-native.so` | `c87ccc623d70b1d582cd5486a9a6316c5117091ca10113682aa07cc72c80912f` |
| Signed fixture | `asset-locales-fixture-2026-11-02-r1/probe.apk` | `03877624fde8928fac5efb3a2c49d9306356f5cb1488c3fa343799a39044a265` |

Fixture receipt `S/asset-locales-fixture-2026-11-02-r1/build.json` has SHA-256
`bd4d3d928057de1978885429b9805fd5f4fa8ff87f5736d6a1b9f74a38f9e6a6`.

All five host qualification phases passed on their first attempts. Runner
selftests rejected 2,343 malformed, mixed and failure cases. Transfer selftests
retain historical snapshot, GET-only, traversal, request and deadline checks,
adding the new selectors, port refusals and exact route/path/hash uniqueness.
ELF inspection confirms static AArch64 EXEC without INTERP or DYNAMIC segments.
These host checks do not establish ARM fixture or live GMS success.

| Check | Guard seconds | Sampled aggregate RSS bytes | Time maximum bytes |
| --- | ---: | ---: | ---: |
| Host runner compile | 1.888 | 356,122,624 | 373,276,672 |
| Runner selftest | 1.322 | 21,987,328 | 17,842,176 |
| Static ARM runner compile | 3.027 | 376,291,328 | 368,394,240 |
| Host transfer compile | 2.667 | 383,893,504 | 391,217,152 |
| Transfer selftest | 1.401 | 10,846,208 | 9,584,640 |

All guards and children exited zero, cleanup is complete and swaps are zero
under 600 MiB aggregate RSS, 300 seconds, 512 MiB observed shared growth,
1 GiB reserve, 4 MiB output and the existing file-size cap. Runtime, producer
receipt and tool inputs were rehashed afterward; frozen sources still match the
checkout. Historical StableDisplay diagnostic r2 framework/native/APK, runner,
transfer and seal pins remain unchanged. Source base is
`6d3f38087cf3b588d1d0a5161a3049146da48216`; runner and transfer source hashes
are respectively `58c5c1dc09cbd9419d223d8963c0044c33f7acb08662c2e0b644dbaaf86b492d`
and `68f48b51eab6026f8bdf804b0ba427b970a715747827ba71372e2310f65e32c6`.

ARM runner `S/asset-locales-api-run-2026-11-02-r1/run` has SHA-256
`8470df7af7820263e1c2dfb132f51f2fadc808e759d07dce7212344af9a20885`.
Transfer `S/asset-locales-api-transfer-build-2026-11-02-r1/transfer` has SHA-256
`1cf08e1266eb688ae7e6d669ce8033d9112ad73feaed7fed3dbf4436af3231e9`.
Four complete tool/control roots passed sealing and separate fresh-process
readback for 35 entries at
`S/asset-locales-api-tools-sealed-2026-11-02-r1/manifest.json`, SHA-256
`0dff247f5609da37adb95de36ac99c5b18635701a1bfc2dfaab5b9df6bbbc1e1`.
Seal/readback took 0.064/0.575 guard seconds, with zero guard/child exits,
complete cleanup and zero swaps under the unchanged 600 MiB/300-second/64 MiB
shared-growth/1 GiB reserve/file-size caps. Controls remain at
`S/asset-locales-api-tools-seal-controls-2026-11-02-r1`.
Independent source and final artifact/pin/guard/ELF/full-inventory reviews passed.

## Guest recipe

Start the qualified transfer with a fresh host output root:

```sh
S=/Users/alex/.local/state/vinix/android
"$S/asset-locales-api-transfer-build-2026-11-02-r1/transfer" serve --asset-locales-api "$S/asset-locales-api-transfer-live-2026-11-02-r1" 55532
```

In a fresh guest root terminal, require no passwd/group match for name
`asset-locales-probe` or UID/GID 10140 before provisioning. Retain an existing
exact account only after verifying its UID, primary GID and group GID.

```sh
grep -nE '(^asset-locales-probe:|:10140:)' /etc/passwd /etc/group
/usr/sbin/addgroup -g 10140 asset-locales-probe
/usr/sbin/adduser -D -H -u 10140 -G asset-locales-probe -s /bin/false asset-locales-probe
grep -nE '^asset-locales-probe:' /etc/passwd /etc/group
```

Require no existing dedicated runtime mount. Bind the staged immutable runtime
to a fresh attachment and verify `ro,nosuid,nodev,wxallowed` without `noexec`.

```sh
grep ' /opt/asset-locales-runtime ' /proc/self/mounts
mkdir /opt/asset-locales-runtime
mount -o bind /opt/vinix-android-aarch64 /opt/asset-locales-runtime
mount -o remount,bind,ro,nosuid,nodev,strictatime,wxallowed none /opt/asset-locales-runtime
grep ' /opt/asset-locales-runtime ' /proc/self/mounts
mkdir -p /opt/input
wget -O /opt/input/asset-locales-run http://10.0.2.2:55532/asset-locales-api-run
wget -O /opt/input/asset-locales.apk http://10.0.2.2:55532/asset-locales.apk
chmod 755 /opt/input/asset-locales-run
chmod 644 /opt/input/asset-locales.apk
/opt/input/asset-locales-run --asset-locales /opt/asset-locales-runtime /opt/input/asset-locales.apk 10140 10140 /var/lib/asset-locales-r1
```

Before launch, verify the output path is absent and downloaded runner/APK hashes
match the qualified pins. Leave guest input untouched through UART export.
Preserve the complete UART and derive one exact interval using
[uart-snapshot.md](uart-snapshot.md). Strictly collect `child.log` and
`receipt.json`, requiring all eleven checks and the exact six identities.
Run `umount /opt/asset-locales-runtime` after validation before the separate
Maps/GMS test. Preserve failed runtime evidence if an assertion fails.
