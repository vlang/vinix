# Unavailable stats fixture tools, 2026-11-02

The additive `--stats-unavailable` runner profile requires its successor
framework, verified native pair and signed fixture. The transfer selector
`serve --stats-unavailable-api` serves exactly `/stats-unavailable-api-run`
and `/stats-unavailable.apk`. Historical profiles, pins and routes, including
unmanaged queries, remain unchanged.

The exact success marker is:

```text
STATS-UNAVAILABLE-PASS class-identity string-null typed-null early-returns dormant-references service-fallback repeated-queries
```

The fixture checks the StatsManager class identity, null string/typed service
lookups and guarded early returns. Its actual Main class also contains a
never-called `removeConfig(J)V` reference and a catch reference to
`StatsManager$StatsUnavailableException`; the APK supplies neither platform type
nor method. Existing ART/verifier/health diagnostics remain intact. The generic
runner retains six protected input pins, eleven receipt checks, dedicated
identity/data/home/surface, descriptor closure, bounded lifetime, one exact
PASS/READY pair, drained EOF and clean child exit. These contracts do not
establish Google Play Services or authentication success.

Paths below use `S=/Users/alex/.local/state/vinix/android`.

| Input | Path below S | SHA-256 |
| --- | --- | --- |
| Framework | `combined-account-webview-stats-unavailable-framework-2026-11-02-r1/api-impl.jar` | `86d1cc8dc592082aeb837fd260e36a4a0c93bbe5a23e3f22e4f97b5ba09e7ffd` |
| Native | `current-native-build-2026-11-02-asset-locales-r1/native/libvinix-android-native.so` | `c87ccc623d70b1d582cd5486a9a6316c5117091ca10113682aa07cc72c80912f` |
| Signed fixture | `stats-unavailable-fixture-2026-11-02-r1/probe.apk` | `a0742e010e52dd042500a6811fddc6fe369b28852a85bfd22987dbb0c894a4dc` |

Fixture receipt `S/stats-unavailable-fixture-2026-11-02-r1/build.json` has SHA-256
`dc708735955aedc4fff17b5932a280e4e5340e0eccc093a816eb5824988ec320`.

All five host qualification phases passed on their first attempts. Runner
selftests rejected 2,631 malformed, mixed and failure cases. Transfer selftests
retain historical snapshot, GET-only, traversal, request and deadline checks,
adding the new selector/port refusals and exact route/path/hash uniqueness.
ELF inspection confirms static AArch64 EXEC without INTERP or DYNAMIC segments.
These host checks do not establish ART fixture or live GMS success.

| Check | Guard seconds | Sampled aggregate RSS bytes | Time maximum bytes |
| --- | ---: | ---: | ---: |
| Host runner compile | 1.497 | 337,625,088 | 364,625,920 |
| Runner selftest | 1.114 | 21,069,824 | 17,858,560 |
| Static ARM runner compile | 1.901 | 371,638,272 | 370,655,232 |
| Host transfer compile | 1.729 | 386,727,936 | 396,378,112 |
| Transfer selftest | 1.042 | 10,698,752 | 9,502,720 |

All guards and children exited zero, cleanup is complete and swaps are zero
under 600 MiB aggregate RSS, 300 seconds, 512 MiB observed shared growth,
1 GiB reserve, 4 MiB output and the existing file-size cap. Runtime, producer
receipt and tool inputs were rehashed afterward; both frozen sources match the
checkout. Historical unmanaged framework/native/APK, runner, transfer and seal
pins remain unchanged. Runner/transfer source bases are respectively
`635dbaf0f347c82b4d2eb920fec2af28d0878140` and
`2c917b136bca7850f142e221640533c0fd0108ce`; source SHA-256 values are
`c82bea805397b3e931bc706a4d1cdf528c6b1f76130f170d9971fb7d9225da55`
and `eb633f5ec69825ce7f4f0950be55b962b399e3bf4718f1ae0fb9ffaa42a67678`.

ARM runner `S/stats-unavailable-api-run-2026-11-02-r1/run` has SHA-256
`53299db9d33cb1f1513ff80ba81037bad675c59be949ddd3d675dfdaa7131520`.
Transfer `S/stats-unavailable-api-transfer-build-2026-11-02-r1/transfer` has SHA-256
`bd4c305cf0f9bd85f6ecea2778d6c2c90548a7d6f0ef49e1f2945e694d8b8508`.
Four complete tool/control roots passed sealing and separate fresh-process
readback for 35 entries at
`S/stats-unavailable-api-tools-sealed-2026-11-02-r1/manifest.json`, SHA-256
`443db70c2756df3aa08b66bdd5d230fe0b18d0f00d82c5f56c4cd3ac54924976`.
Seal/readback took 0.052/0.237 guard seconds, with zero guard/child exits,
complete cleanup and zero swaps under the unchanged 600 MiB/300-second/64 MiB
shared-growth/1 GiB reserve/file-size caps. Controls remain at
`S/stats-unavailable-api-tools-seal-controls-2026-11-02-r1`.
Independent source, marker, artifact/guard/ELF, report and full-inventory reviews passed.

## Guest recipe

Start the qualified transfer with a fresh host output root:

```sh
S=/Users/alex/.local/state/vinix/android
"$S/stats-unavailable-api-transfer-build-2026-11-02-r1/transfer" serve --stats-unavailable-api "$S/stats-unavailable-api-transfer-live-2026-11-02-r1" 55534
```

In a fresh guest root terminal, require no passwd/group match for name
`stats-unavailable-probe` or UID/GID 10142 before provisioning. Retain an existing
exact account only after verifying its UID, primary GID and group GID.

```sh
grep -nE '(^stats-unavailable-probe:|:10142:)' /etc/passwd /etc/group
/usr/sbin/addgroup -g 10142 stats-unavailable-probe
/usr/sbin/adduser -D -H -u 10142 -G stats-unavailable-probe -s /bin/false stats-unavailable-probe
grep -nE '^stats-unavailable-probe:' /etc/passwd /etc/group
```

Require no existing dedicated runtime mount. Bind the staged immutable runtime
to a fresh attachment and verify `ro,nosuid,nodev,wxallowed` without `noexec`.

```sh
grep ' /opt/stats-unavailable-runtime ' /proc/self/mounts
mkdir /opt/stats-unavailable-runtime
mount -o bind /opt/vinix-android-aarch64 /opt/stats-unavailable-runtime
mount -o remount,bind,ro,nosuid,nodev,strictatime,wxallowed none /opt/stats-unavailable-runtime
grep ' /opt/stats-unavailable-runtime ' /proc/self/mounts
mkdir -p /opt/input
wget -O /opt/input/stats-unavailable-run http://10.0.2.2:55534/stats-unavailable-api-run
wget -O /opt/input/stats-unavailable.apk http://10.0.2.2:55534/stats-unavailable.apk
chmod 755 /opt/input/stats-unavailable-run
chmod 644 /opt/input/stats-unavailable.apk
/opt/input/stats-unavailable-run --stats-unavailable /opt/stats-unavailable-runtime /opt/input/stats-unavailable.apk 10142 10142 /var/lib/stats-unavailable-r1
```

Before launch, verify the output path is absent and downloaded runner/APK hashes
match the qualified pins. Leave guest input untouched through UART export.
Preserve the complete UART and derive one exact interval using
[uart-snapshot.md](uart-snapshot.md). Strictly collect `child.log` and
`receipt.json`, requiring all eleven checks and the exact six identities.
Run `umount /opt/stats-unavailable-runtime` after validation before the separate
Maps/GMS test. Preserve failed runtime evidence if an assertion fails.
