# Global String-write ARM pass and GMS network-activity linkage failure

The signed Global String-write regression passed on ARM against the
[prepared SDK/native image](global-settings-string-preparation-2026-11-05.md).
The separate GMS retry reached readiness, then exited after a missing virtual
`ConnectivityManager.isDefaultNetworkActive()Z` call. No manual Maps launch
followed. This establishes no GMS stability, Maps rendering or authentication
result.

Paths use `S=/Users/alex/.local/state/vinix/android`. Complete evidence is
`S/maps-global-settings-string-runtime-audit-2026-11-05-r1` (`A`), matching
`S/maps-global-settings-string-live-controls-2026-11-05-r1` (`C`), the stopped
clone `S/maps-global-settings-string-vm-2026-11-05-r1` (`VM`), and
`S/global-settings-string-api-transfer-live-2026-11-05-r1`. Preserve complete
UART, screenshots, clone sidecars, controls, raw results and original
host/preparation bundles. Prepared manifest:
`eeb0c745f7a2d2fc18cd946586d1d5853349d52e14480352c2897151625bb892`.

Qualified coexistence admission launched owned VM93372 at 04:15:01 UTC on
November 5 with 12 GiB/four CPUs, alongside CI23708 at 16 GiB/four CPUs.
The saved admission uses the authorized half-host/64 GiB policy on a
128 GiB/18-logical-CPU host with normal pressure. Admission is a snapshot,
not continuous host monitoring; CI was left running and untouched.

An extra outer guard interrupted initial guest-preflight typing for observed
shared growth: 68,448,256 bytes exceeded 64 MiB after 3,149 ms, guard/child
125/137 with complete cleanup. Its guard, screenshot and partial text remain
retained. The qualified VM driver then recovered the command line and reran
preflight successfully with bounded 30-second calls. The complete UART records
unused UID/GID10158 and fixture paths before provisioning. No fixture input,
health, receipt or reconstruction check was waived.

The isolated UID/GID10158 fixture child48355 exited zero. Receipt
`A/fixture-diagnostic/exported-receipt.json`, SHA-256
`447dd07077fdabcb74032cd987b4ade0d9c098fd8a655f80a0e660956927cafc`,
selects `global-settings-string`, retains 180/20-second deadlines and the
4 MiB log cap, and contains all eleven unchanged checks. It records the sole
exact PASS and native READY, bounded log/lines, live input through readiness,
drained EOF, clean exit, isolated identity/data/home/surface, explicit activity
and environment, closed inherited descriptors and unchanged pinned inputs.
All six input hashes match qualified delivery:

| Input | SHA-256 |
| --- | --- |
| `/opt/input/global-settings-string-run` | `7dedaf0f25f4eb3daa9a6af9f94b6d65329dded9d90645fa2d1f37c195010ae7` |
| `/opt/input/global-settings-string.apk` | `faee136b4cdb500ff165b7b7aceb6649f8af27054593a5905a64f217553c806a` |
| Runtime `usr/bin/run-android` | `1b4d3e3d2dbc2eb5ae95343847218d4afd44d64aeb9d52cc0b07cb8f9c37b112` |
| Runtime `usr/bin/vinix-android-native` | `b1061601ebbcd5bc4c81c68d354704e58ff472a2bc9c8666fad6a588a614b98d` |
| Runtime `usr/lib/art/libvinix-android-native.so` | `b69c62304448c1aa0fd5f0cc660acf81cfdd8614b280dad691f53a07d8abcc5f` |
| Runtime `usr/lib/java/dex/android_translation_layer/api-impl.jar` | `9207dab7a6a37e09fb049bb636ba6ebad3e63e43bfe7fd95821f67fc2aebeeb7` |

Runtime paths are under `/opt/global-settings-string-runtime`. The complete
fixture child log is 11,770 bytes/116 lines, SHA-256
`9a8d3e473c5b3fc4273328f2a102cf1107ac30f04fc4b76ae44d440cf11eb068`.
The exact PASS is at line 99, native READY at 109, and normal pause/stop/destroy
finishes at 116. It measures public static virtual-resolver delegation, exact
Global URI, fresh ContentValues, null/empty/Unicode Strings, one insert per
call, provider results and narrow exception identity on UI and bounded worker.
It establishes no SettingsProvider persistence, permission grant or moved-key
routing behavior.

Guest input stayed idle through export END. Immutable before/after snapshots
bind the fixture interval at byte 100,545, length 30,076, SHA-256
`da78dbb38c379d37451390c06e80625c5d2bfba175b6d5d2897c6cc50d171112`.
The unchanged no-removal plan retained two entries, 37 chunks and 18,791 bytes,
archive SHA-256 `6798c0e0c16e175fb6b51ec5b43b832d46e8b06c8d0cf5c6082d2a8eb6c4c5f9`.
This diagnostic reconstruction does not extend strict fixture-protocol
qualification; original bytes, receipt checks and exact child extraction
remain retained.

After the validated fixture, both runtime mounts were released before separate
GMS startup. The controller ran from 04:25:48 to 04:31:35 UTC with both trace
flags enabled. Strict receipt `A/broker-strict/results/receipt.json`, SHA-256
`9f058ab0cf21926b35f2581b4f345c8c27e0e7cd2a0438d31f1e2d0845417b1f`,
records broker35463, readiness true, failed/exit1, drained EOF/status1 with
456,506 bytes and zero cleanup survivors. Readiness is transport attachment,
not completed startup or authentication. The unchanged strict collector
accepted 21 entries, 2,831 chunks and 1,449,243 bytes, archive SHA-256
`1a1cde83c02b4d1858213794b0fc79686e342fcc4b2b393f89efce1788e01d63`.

The complete private broker log was separately recovered from guest-pinned
byte count, SHA-256 and canonical base64. The qualified decoder and independent
check passed without repair. `A/broker-log-diagnostic/child.log` is 456,506 bytes,
SHA-256 `981651899a85fa68153c3b49751428c400942300ffcd1d310212b222effe7061`.
Its source UART interval is 624,805 bytes, SHA-256
`fefb5d6c7ecadf0acf276630e1acbb2c415e089b38f1779d238a1dfee74d0ec2`.
At 10745, `ANDROID-WS-UNCAUGHT` names `lowpool[7]`. At 10764 the causal
NoSuchMethodError names `ConnectivityManager.isDefaultNetworkActive()Z`,
through `QosUploaderChimeraService.g` source 222 and `.a` source 46.
System.exit records status 0 at 10836; the controller separately records the
broker's failed status 1. These are distinct recorded statuses.

The final full UART is 3,004,124 bytes, SHA-256
`ac2df9a19dd94c07d128b3dadd2d42eb98042a75387340970d1c438f131ff55e`.
One owned-VM SIGTERM was requested at 04:36:22 UTC. The initial stop returned
an ownership/disappearance race after writing `stop.json`; its failed output
remains retained. The qualified `reconcile-stop` path confirmed PID93372
absent at 04:36:32 without another signal, binding the original ownership and
stop receipts. QEMU records signal 15. CI23708 remained running and untouched.

The complete four-root, 394-entry runtime aggregate is
`S/global-settings-string-runtime-sealed-2026-11-05-r1/sealed/manifest.json`,
SHA-256 `5334e783965222ac8fb57cc625967f440598ca0d8cad291177020bdf7cdc6281`.
It retains A, C, VM and transfer output, including failed preflight/stop
controls and all sidecars. Seal and separate fresh readback passed 0/0,
with empty reasons and complete cleanup in 15,858/4,674 ms. Sampled RSS was
22,036,480/14,286,848 bytes and observed shared growth was
85,954,560/6,082,560 bytes. Both kept the approved 512 MiB growth allowance,
900 seconds, 600 MiB RSS, 1 GiB reserve, 4 MiB output and 8 GiB shell file cap.
Preserve complete runtime and historical input bundles. The next measured
blocker is the missing basic ConnectivityManager query; the fixture pass and
new GMS failure do not establish Maps or authentication success.
