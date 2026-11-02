# PendingIntent fixture tools, 2026-11-02

The additive `--pending-intent` runner profile requires the PendingIntent
successor framework, retained resource-lock native library and separately
signed fixture. `serve --pending-intent-api` supplies exactly
`/pending-intent-api-run` and `/pending-intent.apk`. Every historical profile,
pin and route remains unchanged.

The exact success marker is:

```text
PENDING-INTENT-PASS no-create identity send fill-in update cancel one-shot immutable parcel service recovery broadcast cleanup
```

The generic runner retains six protected input pins, eleven receipt checks,
dedicated identity/data/home/surface, descriptor closure, bounded lifetime,
one exact PASS/READY pair, drained EOF and clean child exit. The fixture tests
process-local token identity, flags, parcel aliases, snapshots, cancellation,
atomic one-shot consumption and service/broadcast dispatch. It does not establish
cross-process token transport or Google authentication.

Paths below use `S=/Users/alex/.local/state/vinix/android`.

| Input | Path below S | SHA-256 |
| --- | --- | --- |
| Framework | `combined-account-webview-pending-intent-framework-2026-11-02-r1/api-impl.jar` | `bc82567de6d8abd6a4084c68e0e4c698df12d2c7848c7d23b6af7e5d0e6df7cc` |
| Native | `current-native-build-2026-11-01-resource-lock-r2/native/libvinix-android-native.so` | `aeb5ccd643020cbb20ad5630dabff4bfd0ff8b04a5b0fbcfd1b657b3bcd91dd7` |
| Signed fixture | `pending-intent-fixture-2026-11-02-r1/probe.apk` | `24ee07ce193fbde0ee448aeceee70a6013095301cbb6b487c9e61aaf175a9456` |

Fixture build receipt `S/pending-intent-fixture-2026-11-02-r1/build.json` has
SHA-256 `9548b5945191d95697f39f30e4ac5b56cc9ee678b0639030e03e6b7b81437545`.

All five qualification phases passed. Runner selftests rejected 2,071 malformed,
mixed and failure cases. Transfer selftests retain the complete historical
snapshot, GET-only, traversal, request and deadline checks, adding the new
selector/port refusals and exact two-route uniqueness. ELF inspection confirms
static AArch64 EXEC without INTERP or DYNAMIC segments. These host checks do not
establish ARM fixture or live Maps success.

| Check | Guard seconds | Sampled aggregate RSS bytes | Time maximum bytes |
| --- | ---: | ---: | ---: |
| Host runner compile | 1.402 | 350,060,544 | 365,805,568 |
| Runner selftest | 0.952 | 19,169,280 | 17,793,024 |
| Static ARM runner compile | 1.929 | 363,544,576 | 361,201,664 |
| Host transfer compile | 1.593 | 385,253,376 | 405,143,552 |
| Transfer selftest | 0.881 | 10,485,760 | 8,814,592 |

All guards and children exited zero, with complete cleanup and zero swaps under
600 MiB aggregate RSS, 300 seconds, 512 MiB observed shared-volume growth,
1 GiB reserve, 4 MiB output and the existing file-size cap. All artifact/tool
inputs were rehashed afterward; frozen sources still match the checkout.
Historical resource-lock APK, runner, transfer and seal pins remain unchanged.
Source base is `7820a7685b44bbe31c2a5c9c76ce0c1626da937d`; runner and transfer
source hashes are respectively
`e197240ebe7a75858c88462b0c3bb0fd2910c84ff1931f4043ded3f354eb217f`
and `cda28726d508f94b17189741445c02f7974f05c92fe7861ee26b47c1891dd0d7`.
The initial precompile inventory named nonexistent `manifest.json`; its partial
output and note are retained in the runner-build root. The corrected inventory
uses the producer's `sha256.json`. No compiler ran before that correction.

ARM runner `S/pending-intent-api-run-2026-11-02-r1/run` has SHA-256
`1c54386f45e64b1879cc6d0954b8dff59dc605ad6a70b52b286e86ccdaaaeecf`.
Transfer `S/pending-intent-api-transfer-build-2026-11-02-r1/transfer` has SHA-256
`9010b4e342591e121be0b0eebe4d04baa2016238daa986af15cfb9cac23456dc`.
The four complete tool/control roots passed sealing and a separate fresh-process
readback for 37 entries at
`S/pending-intent-api-tools-sealed-2026-11-02-r1/manifest.json`, SHA-256
`b0f9f3299708287bb999cecaa6b0a70dee2f2bfa40573fb21cd35e1cb028a11e`.
Seal/readback took 0.047/0.287 guard seconds, exited zero with complete cleanup
and zero swaps, and retained the 600 MiB/300-second/64 MiB shared-growth/1 GiB
reserve/file-size caps. Controls remain in
`S/pending-intent-api-tools-seal-controls-2026-11-02-r1`.
Independent source and final pin/artifact/guard/ELF/seal reviews passed.

## Guest recipe

Start the qualified transfer with a fresh output path on the host:

```sh
S=/Users/alex/.local/state/vinix/android
"$S/pending-intent-api-transfer-build-2026-11-02-r1/transfer" serve --pending-intent-api "$S/pending-intent-api-transfer-live-2026-11-02-r1" 55530
```

In a fresh guest root terminal, verify no passwd/group record uses the name
`pending-intent-probe` or numeric UID/GID 10138. Proceed only when there are no
matches; retain an already provisioned account only after verifying all three
numeric fields are exactly 10138.

```sh
grep -nE '(^pending-intent-probe:|:10138:)' /etc/passwd /etc/group
/usr/sbin/addgroup -g 10138 pending-intent-probe
/usr/sbin/adduser -D -H -u 10138 -G pending-intent-probe -s /bin/false pending-intent-probe
grep -nE '^pending-intent-probe:' /etc/passwd /etc/group
```

Require no existing `/opt/pending-intent-runtime` mount and protect the dedicated
runtime attachment with the existing execution policy. The source directory is
the staged immutable runtime; the bind mount changes only this dedicated target.
Verify its mount entry contains `ro,nosuid,nodev,wxallowed` and lacks `noexec`.

```sh
grep ' /opt/pending-intent-runtime ' /proc/self/mounts
mkdir /opt/pending-intent-runtime
mount -o bind /opt/vinix-android-aarch64 /opt/pending-intent-runtime
mount -o remount,bind,ro,nosuid,nodev,strictatime,wxallowed none /opt/pending-intent-runtime
grep ' /opt/pending-intent-runtime ' /proc/self/mounts
mkdir -p /opt/input
wget -O /opt/input/pending-intent-run http://10.0.2.2:55530/pending-intent-api-run
wget -O /opt/input/pending-intent.apk http://10.0.2.2:55530/pending-intent.apk
chmod 755 /opt/input/pending-intent-run
chmod 644 /opt/input/pending-intent.apk
/opt/input/pending-intent-run --pending-intent /opt/pending-intent-runtime /opt/input/pending-intent.apk 10138 10138 /var/lib/pending-intent-r1
```

Before the launch, verify `/var/lib/pending-intent-r1` is absent and the downloaded
runner/APK hashes match the qualified pins. Keep guest input untouched until the
runner finishes UART export. Preserve the complete UART and derive one exact
fixture interval following [uart-snapshot.md](uart-snapshot.md). Strictly collect
and validate the exported `child.log` and `receipt.json`, including the exact
APK/framework/native/runner identities and all eleven checks. Only then release
the dedicated attachment with `umount /opt/pending-intent-runtime` before the
separate Maps/Play Services run.
