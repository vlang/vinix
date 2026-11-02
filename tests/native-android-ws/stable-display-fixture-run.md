# Stable display fixture tools, 2026-11-02

The additive `--stable-display` runner profile requires its successor framework,
physical framebuffer query native library and signed fixture. The transfer
selector `serve --stable-display-api` serves exactly `/stable-display-api-run`
and `/stable-display.apk`. Historical profiles, pins and routes, including
PendingIntent, remain unchanged.

The exact success marker is:

```text
STABLE-DISPLAY-PASS physical-size window-size fresh-points mutation-isolation
```

The fixture requires independently verified physical geometry `1024×768` and
the generic runner's unchanged `64×64` application surface. It checks physical
dimensions, retained window-size APIs, fresh Point objects, mutation isolation
and cross-context queries. The generic runner retains six protected input pins,
eleven receipt checks, dedicated identity/data/home/surface, descriptor closure,
bounded lifetime, one exact PASS/READY pair, drained EOF and clean child exit.
This fixture does not establish Google Play Services or authentication behavior.

Paths below use `S=/Users/alex/.local/state/vinix/android`.

| Input | Path below S | SHA-256 |
| --- | --- | --- |
| Framework | `combined-account-webview-stable-display-framework-2026-11-02-r1/api-impl.jar` | `3b51a6cfe506db8e87908fdf74fcaebd585aaace383e8880a0183cd901780e52` |
| Native | `current-native-build-2026-11-02-stable-display-r2/native/libvinix-android-native.so` | `364f76761b57da6e0674d9a0c20f85e2589e5b8705d22aac6e6c3a9b82f8fcae` |
| Signed fixture | `stable-display-fixture-2026-11-02-r1/probe.apk` | `e29dc54e644e94a5a0a4040858cdca452ee8ebc83e29052c78e4b91b55e9d13c` |

Fixture receipt `S/stable-display-fixture-2026-11-02-r1/build.json` has SHA-256
`df67d985a9fe27f6d352b083dfb47e5699a1e7590f9c85b4354e119f982c59a2`.

All five host qualification phases passed on their first attempts. Runner
selftests rejected 2,205 malformed, mixed and failure cases. Transfer selftests
retain historical snapshot, GET-only, traversal, request and deadline checks,
adding StableDisplay selector/port refusals and exact route/path/hash uniqueness.
ELF inspection confirms static AArch64 EXEC without INTERP or DYNAMIC segments.
These host checks do not establish ARM fixture or live GMS success.

| Check | Guard seconds | Sampled aggregate RSS bytes | Time maximum bytes |
| --- | ---: | ---: | ---: |
| Host runner compile | 1.368 | 353,992,704 | 365,674,496 |
| Runner selftest | 1.025 | 19,644,416 | 17,809,408 |
| Static ARM runner compile | 1.723 | 370,294,784 | 362,872,832 |
| Host transfer compile | 1.578 | 384,745,472 | 388,857,856 |
| Transfer selftest | 0.896 | 11,419,648 | 9,568,256 |

All guards and children exited zero with complete cleanup and zero swaps under
600 MiB aggregate RSS, 300 seconds, 512 MiB observed shared growth, 1 GiB reserve,
4 MiB output and the existing file-size cap. Artifact, producer-receipt and tool
inputs were rehashed afterward; both frozen sources match the checkout. The
historical PendingIntent JAR, native library, APK, runner, transfer and seal pins
remain unchanged. Source base is `91ca4b7bd78575853f2ac23734080af9acaaa8d9`;
runner and transfer source hashes are respectively
`e5133666a3095e552571039ebad3313045bb9d368ba84a6d0762714338e3c615`
and `ef371471eec1fe6d49036df27b221e2cb898b26dd538768eeabab61ba71e6f31`.

ARM runner `S/stable-display-api-run-2026-11-02-r1/run` has SHA-256
`7ec0c25e072be272eef051bf3da4c1de72613ede5b5e54ae8d9c03abcebdbecf`.
Transfer `S/stable-display-api-transfer-build-2026-11-02-r1/transfer` has SHA-256
`f38346301f1faeeedbd072cbb93f0b1256c00bccbcee73cccf6447a8e6a0c35b`.
Four complete tool/control roots passed sealing and a separate fresh-process
readback for 35 entries at
`S/stable-display-api-tools-sealed-2026-11-02-r1/manifest.json`, SHA-256
`be8b2c829f48e83a4cdd68ab3936ca14d3b199161ebf9109665fcea530760866`.
Seal/readback took 0.069/0.239 guard seconds, with zero exits, complete cleanup
and zero swaps under the unchanged 600 MiB/300-second/64 MiB shared-growth/1 GiB
reserve/file-size caps. Controls remain at
`S/stable-display-api-tools-seal-controls-2026-11-02-r1`.
Independent source and final pin/artifact/guard/ELF/seal reviews passed.

## Guest recipe

Start the qualified host transfer with fresh output:

```sh
S=/Users/alex/.local/state/vinix/android
"$S/stable-display-api-transfer-build-2026-11-02-r1/transfer" serve --stable-display-api "$S/stable-display-api-transfer-live-2026-11-02-r1" 55531
```

In the fresh guest root terminal, require no passwd/group match for name
`stable-display-probe` or UID/GID 10139 before provisioning. An existing exact
account may be retained only after checking its UID, primary GID and group GID.

```sh
grep -nE '(^stable-display-probe:|:10139:)' /etc/passwd /etc/group
/usr/sbin/addgroup -g 10139 stable-display-probe
/usr/sbin/adduser -D -H -u 10139 -G stable-display-probe -s /bin/false stable-display-probe
grep -nE '^stable-display-probe:' /etc/passwd /etc/group
```

Require no existing dedicated runtime mount. Bind the staged immutable runtime
to a fresh attachment and verify `ro,nosuid,nodev,wxallowed` without `noexec`.
Preserve independent desktop/framebuffer geometry evidence before launching.

```sh
grep ' /opt/stable-display-runtime ' /proc/self/mounts
mkdir /opt/stable-display-runtime
mount -o bind /opt/vinix-android-aarch64 /opt/stable-display-runtime
mount -o remount,bind,ro,nosuid,nodev,strictatime,wxallowed none /opt/stable-display-runtime
grep ' /opt/stable-display-runtime ' /proc/self/mounts
mkdir -p /opt/input
wget -O /opt/input/stable-display-run http://10.0.2.2:55531/stable-display-api-run
wget -O /opt/input/stable-display.apk http://10.0.2.2:55531/stable-display.apk
chmod 755 /opt/input/stable-display-run
chmod 644 /opt/input/stable-display.apk
/opt/input/stable-display-run --stable-display /opt/stable-display-runtime /opt/input/stable-display.apk 10139 10139 /var/lib/stable-display-r1
```

Before launch, verify fresh output `/var/lib/stable-display-r1` is absent and
downloaded runner/APK hashes match the qualified pins. Leave guest input untouched
through UART export. Preserve the complete UART and derive one exact interval
using [uart-snapshot.md](uart-snapshot.md). Strictly collect `child.log` and
`receipt.json`, requiring all eleven checks and the exact six identities. After
validation, run `umount /opt/stable-display-runtime` before the separate Maps/GMS
test. The fixture's 64×64 surface remains unchanged throughout.

## Diagnostic fixture refresh, r2

The r2 fixture labels stable queries 1–4 and reports actual and expected Point
coordinates on failure. All oracles, PASS/FAIL markers and the independently
pinned `1024×768` physical / `64×64` application geometry remain unchanged.
The framework and native library above are retained. This refresh changes
exactly five source constants: the runner APK pin and transfer runner/APK paths
and pins. Every historical profile, route and health check remains intact.
The complete r1 APK, tools and seal were rehashed without modification.

| Refreshed input | Path below S | SHA-256 |
| --- | --- | --- |
| Signed diagnostic APK | `stable-display-fixture-2026-11-02-r2/probe.apk` | `190b832396158ce1ac584ef41abf279d6f13b82b001d17c35e2bd711d5ebcee1` |
| Fixture receipt | `stable-display-fixture-2026-11-02-r2/build.json` | `b25f57ac33eba0b877ee66d5495e177c0832432b34d9cdafa6b84f43793f3df0` |
| Static ARM runner | `stable-display-api-run-2026-11-02-r2/run` | `2e819f47963d75a09345cacea3a81db28c119d267bff5818c6d0de6e4a5b476b` |
| Transfer | `stable-display-api-transfer-build-2026-11-02-r2/transfer` | `1437f4fe4d50cb6cc5af313eeb74dfbaa98fca0a4cc6a7cfda19dbaec24106f2` |

All five refreshed phases passed on their first attempts. Runner selftests
still reject 2,205 cases, transfer selftests pass, and ELF inspection confirms
static AArch64 EXEC without INTERP or DYNAMIC segments. This host qualification
establishes no diagnostic ARM or GMS result.

| Check | Guard seconds | Sampled aggregate RSS bytes | Time maximum bytes |
| --- | ---: | ---: | ---: |
| Host runner compile | 1.328 | 365,379,584 | 365,527,040 |
| Runner selftest | 1.003 | 19,251,200 | 17,842,176 |
| Static ARM runner compile | 1.736 | 369,868,800 | 367,394,816 |
| Host transfer compile | 1.500 | 370,900,992 | 386,711,552 |
| Transfer selftest | 1.186 | 10,829,824 | 9,601,024 |

All guard/child exits are zero, cleanup is complete and swaps are zero under
the original 600 MiB/300-second/512 MiB shared-growth/1 GiB reserve/4 MiB output
and file-size caps. Runtime/tool/producer-receipt inputs were rehashed after the
checks, and both frozen sources match the checkout. Source base is
`3ae622c2767df906fe6fae34eb8c156d1cbb3313`; runner/transfer source SHA-256 values
are `2b600af2b5b91d891d0fe427370e17d39734f63da292c62b67ea090af93a851f`
and `28eadb8e83ea73a06c94f644fe822e4026d6e3ddc1f0774a788ea07001479294`.

Four complete refreshed tool/control roots passed sealing and fresh-process
readback at `S/stable-display-api-tools-sealed-2026-11-02-r2/manifest.json`,
SHA-256 `24495aa97f66858c371f2f5bd65b14a0e0e4ab38a0e4b0798f2853d26e6c4663`
(35 entries). Seal/readback took 0.062/0.217 guard seconds with zero guard/child
exits, complete cleanup and zero swaps under the retained 64 MiB seal growth
cap. Controls remain at `S/stable-display-api-tools-seal-controls-2026-11-02-r2`.
Independent review confirmed the five-constant diff and all refreshed artifacts,
guard receipts, ELF properties and sealed readback.

For the controlled retry, use the same port, UID/GID, routes and protected mount
recipe with the r2 transfer, a fresh host result root and fresh guest output
`/var/lib/stable-display-r2`:

```sh
"$S/stable-display-api-transfer-build-2026-11-02-r2/transfer" serve --stable-display-api "$S/stable-display-api-transfer-live-2026-11-02-r2" 55531
/opt/input/stable-display-run --stable-display /opt/stable-display-runtime /opt/input/stable-display.apk 10139 10139 /var/lib/stable-display-r2
```

Keep the same geometry evidence, untouched UART interval and strict receipt
validation requirements; retain failed runtime evidence if an oracle still fails.
