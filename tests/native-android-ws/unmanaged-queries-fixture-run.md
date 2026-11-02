# Unmanaged query fixture tools, 2026-11-02

The additive `--unmanaged-queries` runner profile requires its successor
framework, verified native pair and signed fixture. The transfer selector
`serve --unmanaged-queries-api` serves exactly `/unmanaged-queries-api-run`
and `/unmanaged-queries.apk`. Historical profiles, pins and routes, including
asset locales, remain unchanged.

The exact success marker is:

```text
UNMANAGED-QUERIES-PASS owner-null profile-false service-lookups restrictions-defaults snapshots repeated-queries
```

The fixture checks the unmanaged device-owner and managed-profile query
contracts. The generic runner retains six protected input pins, eleven receipt
checks, dedicated identity/data/home/surface, descriptor closure, bounded
lifetime, one exact PASS/READY pair, drained EOF and clean child exit. These
contracts do not establish Google Play Services or authentication success.

Paths below use `S=/Users/alex/.local/state/vinix/android`.

| Input | Path below S | SHA-256 |
| --- | --- | --- |
| Framework | `combined-account-webview-unmanaged-queries-framework-2026-11-02-r1/api-impl.jar` | `25500d52cf7c03a2a1c82656c00284c507dbdb03cff546dbc6e5840aa45b5c1c` |
| Native | `current-native-build-2026-11-02-asset-locales-r1/native/libvinix-android-native.so` | `c87ccc623d70b1d582cd5486a9a6316c5117091ca10113682aa07cc72c80912f` |
| Signed fixture | `unmanaged-queries-fixture-2026-11-02-r1/probe.apk` | `dcea26199cfb0bfc2b0b44126b45923c717893b3670f1788b60c4038d4213400` |

Fixture receipt `S/unmanaged-queries-fixture-2026-11-02-r1/build.json` has SHA-256
`81511dac6f9ba5d99ce5ca284669a9dbf4cd17601403ee1dc6b424db471ab7b2`.

All five host qualification phases passed. Runner selftests rejected 2,485
malformed, mixed and failure cases. Transfer selftests retain historical
snapshot, GET-only, traversal, request and deadline checks, adding the new
selector/port refusals and exact route/path/hash uniqueness. ELF inspection
confirms static AArch64 EXEC without INTERP or DYNAMIC segments. These host
checks do not establish ARM fixture or live GMS success.

| Check | Guard seconds | Sampled aggregate RSS bytes | Time maximum bytes |
| --- | ---: | ---: | ---: |
| Host runner compile | 1.487 | 338,132,992 | 369,639,424 |
| Runner selftest | 1.073 | 19,709,952 | 17,825,792 |
| Static ARM runner compile, retry | 1.913 | 371,441,664 | 363,364,352 |
| Host transfer compile | 1.671 | 385,925,120 | 394,690,560 |
| Transfer selftest | 1.494 | 10,944,512 | 9,715,712 |

The initial ARM command named a nonexistent compiler executable and exited 127
before compiling. Its original `arm-build.log` and `arm-build.guard.json` remain
in the runner-build root. The successful `arm-build-retry` used the pinned V
compiler and unchanged frozen source; no checks or limits were relaxed.

All successful guard/child exits are zero, cleanup is complete and swaps are
zero under 600 MiB aggregate RSS, 300 seconds, 512 MiB observed shared growth,
1 GiB reserve, 4 MiB output and the existing file-size cap. Runtime, producer
receipt and tool inputs were rehashed afterward; frozen sources still match the
checkout. Historical asset-locales framework/native/APK, runner, transfer and
seal pins remain unchanged. Source base is
`1c4794ab3084d377bd264adcbc322a5d889608fd`; runner and transfer source SHA-256
values are `1be491ceefc395a3f10280f4da72990286f4d8078c409f1452f207de02a3e381`
and `aa9925ad7ce3b92ad7ad595b6ae0b4b61c886299f3941ef36ce8cbb1858a1ef5`.

ARM runner `S/unmanaged-queries-api-run-2026-11-02-r1/run` has SHA-256
`1e056cefa8c7af1ffc0f9477fcd22b4377f290129d560981e6c13ba8ca52872f`.
Transfer `S/unmanaged-queries-api-transfer-build-2026-11-02-r1/transfer` has SHA-256
`516593c3f818ca2dcfa3fe898e1c6e792a7ee53156ae173b5836f07c66b880df`.
Four complete tool/control roots passed sealing and separate fresh-process
readback for 37 entries, including the preserved failure, at
`S/unmanaged-queries-api-tools-sealed-2026-11-02-r1/manifest.json`, SHA-256
`d91905d83c4971338f66a330bcb9a5a2d8151fdf3e5085efebe00efc6c4f4c36`.
Seal/readback took 0.061/0.145 guard seconds, with zero guard/child exits,
complete cleanup and zero swaps under the unchanged 600 MiB/300-second/64 MiB
shared-growth/1 GiB reserve/file-size caps. Controls remain at
`S/unmanaged-queries-api-tools-seal-controls-2026-11-02-r1`.
Independent source, marker, final artifact/guard/ELF and full-inventory reviews passed.

## Guest recipe

Start the qualified transfer with a fresh host output root:

```sh
S=/Users/alex/.local/state/vinix/android
"$S/unmanaged-queries-api-transfer-build-2026-11-02-r1/transfer" serve --unmanaged-queries-api "$S/unmanaged-queries-api-transfer-live-2026-11-02-r1" 55533
```

In a fresh guest root terminal, require no passwd/group match for name
`unmanaged-queries-probe` or UID/GID 10141 before provisioning. Retain an existing
exact account only after verifying its UID, primary GID and group GID.

```sh
grep -nE '(^unmanaged-queries-probe:|:10141:)' /etc/passwd /etc/group
/usr/sbin/addgroup -g 10141 unmanaged-queries-probe
/usr/sbin/adduser -D -H -u 10141 -G unmanaged-queries-probe -s /bin/false unmanaged-queries-probe
grep -nE '^unmanaged-queries-probe:' /etc/passwd /etc/group
```

Require no existing dedicated runtime mount. Bind the staged immutable runtime
to a fresh attachment and verify `ro,nosuid,nodev,wxallowed` without `noexec`.

```sh
grep ' /opt/unmanaged-queries-runtime ' /proc/self/mounts
mkdir /opt/unmanaged-queries-runtime
mount -o bind /opt/vinix-android-aarch64 /opt/unmanaged-queries-runtime
mount -o remount,bind,ro,nosuid,nodev,strictatime,wxallowed none /opt/unmanaged-queries-runtime
grep ' /opt/unmanaged-queries-runtime ' /proc/self/mounts
mkdir -p /opt/input
wget -O /opt/input/unmanaged-queries-run http://10.0.2.2:55533/unmanaged-queries-api-run
wget -O /opt/input/unmanaged-queries.apk http://10.0.2.2:55533/unmanaged-queries.apk
chmod 755 /opt/input/unmanaged-queries-run
chmod 644 /opt/input/unmanaged-queries.apk
/opt/input/unmanaged-queries-run --unmanaged-queries /opt/unmanaged-queries-runtime /opt/input/unmanaged-queries.apk 10141 10141 /var/lib/unmanaged-queries-r1
```

Before launch, verify the output path is absent and downloaded runner/APK hashes
match the qualified pins. Leave guest input untouched through UART export.
Preserve the complete UART and derive one exact interval using
[uart-snapshot.md](uart-snapshot.md). Strictly collect `child.log` and
`receipt.json`, requiring all eleven checks and the exact six identities.
Run `umount /opt/unmanaged-queries-runtime` after validation before the separate
Maps/GMS test. Preserve failed runtime evidence if an assertion fails.
