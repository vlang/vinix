# Subscription service fixture tools, 2026-11-02

The additive `--subscription-service` runner profile requires its successor
framework, verified native pair and signed fixture. The transfer selector
`serve --subscription-service-api` serves exactly `/subscription-service-api-run`
and `/subscription-service.apk`. Historical profiles, pins and routes, including
stats unavailability, remain unchanged.

The exact success marker is:

```text
SUBSCRIPTION-SERVICE-PASS service-identity null-list null-info unavailable-phone zero-modems fresh-bound-wrappers dormant-getters fallback-controls
```

The fixture checks cached service identity, absent-backend null list/info,
unavailable phone-number failure, zero phone/modem counts and fresh subscription
wrappers. Actual called null branches retain SubscriptionInfo getter references;
the APK supplies no platform getter stub. Existing ART/verifier/health diagnostics
remain intact. The generic runner retains six protected input pins, eleven
receipt checks, dedicated identity/data/home/surface, descriptor closure,
bounded lifetime, one exact PASS/READY pair, drained EOF and clean child exit.
These contracts do not establish Google Play Services or authentication success.

Paths below use `S=/Users/alex/.local/state/vinix/android`.

| Input | Path below S | SHA-256 |
| --- | --- | --- |
| Framework | `combined-account-webview-subscription-service-framework-2026-11-02-r1/api-impl.jar` | `72c57e05b4458d8c62f82cd29fe70065318303af6b741bf1726337ce922c60ef` |
| Native | `current-native-build-2026-11-02-asset-locales-r1/native/libvinix-android-native.so` | `c87ccc623d70b1d582cd5486a9a6316c5117091ca10113682aa07cc72c80912f` |
| Signed fixture | `subscription-service-fixture-2026-11-02-r1/probe.apk` | `c841324557b839b051bceb8f847d9e943cb69139ebe09d0422b13938164853e5` |

Fixture receipt `S/subscription-service-fixture-2026-11-02-r1/build.json` has SHA-256
`311daae7d07a18b2ff6a88a9173e751a3f3d685373570646036c9873ed758cd8`.

All five host qualification phases passed on their first attempts. Runner
selftests rejected 2,781 malformed, mixed and failure cases. Transfer selftests
retain historical snapshot, GET-only, traversal, request and deadline checks,
adding the new selector/port refusals and exact route/path/hash uniqueness.
ELF inspection confirms static AArch64 EXEC without INTERP or DYNAMIC segments.
These host checks do not establish ARM fixture or live GMS success.

| Check | Guard seconds | Sampled aggregate RSS bytes | Time maximum bytes |
| --- | ---: | ---: | ---: |
| Host runner compile | 1.465 | 339,312,640 | 372,785,152 |
| Runner selftest | 1.033 | 21,905,408 | 17,842,176 |
| Static ARM runner compile | 1.905 | 370,507,776 | 364,888,064 |
| Host transfer compile | 1.711 | 381,042,688 | 406,831,104 |
| Transfer selftest | 1.026 | 10,764,288 | 10,338,304 |

All guards and children exited zero, cleanup is complete and swaps are zero
under 600 MiB aggregate RSS, 300 seconds, 512 MiB observed shared growth,
1 GiB reserve, 4 MiB output and the existing file-size cap. Runtime, producer
receipt and tool inputs were rehashed afterward; frozen sources still match the
checkout. Historical Stats framework/native/APK, runner, transfer and seal pins
remain unchanged. Source base is `bf4a357a6c9a66f64df24a2f572c72dfd493ebdf`;
runner and transfer source SHA-256 values are respectively
`7165598b5bc30ab175b6804cd492bd66825acd3c32ec795b67e167578c9d59a9`
and `df3a471ba974a8fe599c01fb557827807d6744c4032b4aac3312f9709464d71d`.

ARM runner `S/subscription-service-api-run-2026-11-02-r1/run` has SHA-256
`dfc7f4a0e6dfc299f88568c739a07e5fd87766e570871086c35834f52b7513dd`.
Transfer `S/subscription-service-api-transfer-build-2026-11-02-r1/transfer` has SHA-256
`eb73f4b0e3e5dd178512ce4682e540131f1fcdabb4818b6427dfee4b1594bb72`.
Four complete tool/control roots passed sealing and separate fresh-process
readback for 35 entries at
`S/subscription-service-api-tools-sealed-2026-11-02-r1/manifest.json`, SHA-256
`b2e1e716d367476f8e4c347d568a49c45aa16f7ea40158b796a28c55872fffa3`.
Seal/readback took 0.047/0.243 guard seconds, with zero guard/child exits,
complete cleanup and zero swaps under the unchanged 600 MiB/300-second/64 MiB
shared-growth/1 GiB reserve/file-size caps. Controls remain at
`S/subscription-service-api-tools-seal-controls-2026-11-02-r1`.
Independent source, marker/getter, artifact/guard/ELF, report and full-inventory reviews passed.

## Guest recipe

Start the qualified transfer with a fresh host output root:

```sh
S=/Users/alex/.local/state/vinix/android
"$S/subscription-service-api-transfer-build-2026-11-02-r1/transfer" serve --subscription-service-api "$S/subscription-service-api-transfer-live-2026-11-02-r1" 55535
```

In a fresh guest root terminal, require no passwd/group match for name
`subscription-service-probe` or UID/GID 10143 before provisioning. Retain an
existing exact account only after verifying its UID, primary GID and group GID.

```sh
grep -nE '(^subscription-service-probe:|:10143:)' /etc/passwd /etc/group
/usr/sbin/addgroup -g 10143 subscription-service-probe
/usr/sbin/adduser -D -H -u 10143 -G subscription-service-probe -s /bin/false subscription-service-probe
grep -nE '^subscription-service-probe:' /etc/passwd /etc/group
```

Require no existing dedicated runtime mount. Bind the staged immutable runtime
to a fresh attachment and verify `ro,nosuid,nodev,wxallowed` without `noexec`.

```sh
grep ' /opt/subscription-service-runtime ' /proc/self/mounts
mkdir /opt/subscription-service-runtime
mount -o bind /opt/vinix-android-aarch64 /opt/subscription-service-runtime
mount -o remount,bind,ro,nosuid,nodev,strictatime,wxallowed none /opt/subscription-service-runtime
grep ' /opt/subscription-service-runtime ' /proc/self/mounts
mkdir -p /opt/input
wget -O /opt/input/subscription-service-run http://10.0.2.2:55535/subscription-service-api-run
wget -O /opt/input/subscription-service.apk http://10.0.2.2:55535/subscription-service.apk
chmod 755 /opt/input/subscription-service-run
chmod 644 /opt/input/subscription-service.apk
/opt/input/subscription-service-run --subscription-service /opt/subscription-service-runtime /opt/input/subscription-service.apk 10143 10143 /var/lib/subscription-service-r1
```

Before launch, verify the output path is absent and downloaded runner/APK hashes
match the qualified pins. Leave guest input untouched through UART export.
Preserve the complete UART and derive one exact interval using
[uart-snapshot.md](uart-snapshot.md). Strictly collect `child.log` and
`receipt.json`, requiring all eleven checks and the exact six identities.
Run `umount /opt/subscription-service-runtime` after validation before the separate
Maps/GMS test. Preserve failed runtime evidence if an assertion fails.
