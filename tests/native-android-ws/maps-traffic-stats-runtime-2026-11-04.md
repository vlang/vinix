# TrafficStats UID ARM pass and GMS process-info field failure

The signed TrafficStats UID regression **passed on ARM**. GMS subsequently
reached authenticator readiness, then exited after an uncaught missing
`ActivityManager.RunningAppProcessInfo.pkgList` field error. No manual Maps
launch, Skip, tiles, search, route, Sign in or credentials occurred. Current
Maps rendering, imagery and authentication remain unverified.

Core `417211d3a`, [SDK/native and delivery qualification](traffic-stats-uid-pair-2026-11-04.md)
`09120d4ca`, and [image tools](maps-traffic-stats-stage.md) `0b435b712`
remain bound to the prepared image. Only TrafficStats changes among the same
2,117 canonical SDK classes; the verified retained native DSO and inherited
frozen kernel remain unchanged. Prepared manifest is
`2bb3c22ae5beb530dd468f1241c7e252eb8b6b894f3e744e8e770c4a51c290f9`;
stage receipt `888af0a6e1f5e46f22c2811c3b4abcc5bd2d971c26e8190d55017bee9c26e2a8`.

Paths use `S=/Users/alex/.local/state/vinix/android`. Complete runtime evidence
is at `S/maps-traffic-stats-runtime-audit-2026-11-04-r3` (`A`), matching
`maps-traffic-stats-live-controls-2026-11-04-r3` (`C`), stopped
`maps-traffic-stats-vm-2026-11-04-r3` (`VM`) and
`traffic-stats-uid-api-transfer-live-2026-11-04-r3` (`F`). The prepared image,
earlier stopped/failed attempts, clone sidecars and all original auditors
remain required. Raw logs, captures, binaries and images remain outside Git.

The exact r3 clone passed in 10,122 ms with guard/child zero, empty reason and
complete cleanup: sampled RSS 34,406,400 bytes and observed growth 81,326,080
bytes under the original 2 GiB clone-growth limit. Qualified coexistence
launched owned 12 GiB/four-CPU VM 70754 at 18:39:40 UTC. Both admission
snapshots record separate foreign PID 23708 at 16 GiB/four CPUs, 128 GiB host
RAM, 18 logical CPUs and normal pressure under the explicit 64 GiB/half-host
policy. This is snapshot admission, not continuous monitoring. CI was neither
modified nor signalled. No cache files were deleted.

The isolated UID/GID10156 child42021 exited zero. Its receipt selects
`traffic-stats-uid`, matches all six protected input hashes and contains all
eleven unchanged checks. Receipt SHA-256 is
`73b64aac4e1c10519e760639b027a71ef5c8b9436bf48897115e1fc6ee655757`.
The complete 11,052-byte/114-line child log hashes to
`63dd557ef3ea15b46c0e84fd1338f83b037ad85c70a34fad9ac0b8ea0f5b6a15`:
sole exact PASS at line99, sole native READY at108 and normal pause/stop/destroy
through114. Independent receipt/source review confirmed the pass. This covers
public static UID reflection, exact signed values, clear/default state, tag
independence and bounded worker isolation/non-inheritance. It does not exercise
socket attribution or kernel accounting.

Guest input remained idle through the complete fixture export END. The unchanged
zero-removal diagnostic reconstruction preserved two entries, 35 chunks and
17,619 bytes, archive SHA-256
`ea8a502b7e80ea6580935b41aaf2dd0631dbe475afed1516a20e835b56ff8e93`.
The plan retains `removals: []`; no fixture health or protocol rule was waived.
This diagnostic import does not extend strict fixture-protocol qualification.
The dedicated runtime mount was released before the separate broker retry.

The GMS controller ran from 18:44:32 to 18:46:40 UTC. Receipt
`549cf837dda6da223496ab82e3494584f3ed3d51f45b69d0a461596d3762607f`
records broker9790, readiness true, failed/exit1, drained EOF/status1 with
400,820 bytes and zero cleanup survivors. Its trace selections are both true.
Controller preparation precedes the internal 45-second readiness and 15-minute
session timers; readiness establishes transport attachment, not startup or
authentication success. The supported Maps launch was not invoked.

The complete private broker log at `A/broker-log-diagnostic/child.log` is
400,820 bytes, SHA-256
`c564fe625ecf2795aaa3968498123ed36864346268c9f2d451461acafa1d2c49`.
At9172, `ANDROID-WS-UNCAUGHT thread=lowpool[6]` reports a RuntimeException
rethrown by StandaloneSchedulingEngine. Its cause is a NoSuchFieldError for
instance field `pkgList:[Ljava/lang/String;` in
`android.app.ActivityManager$RunningAppProcessInfo`, reached through `eqbh.hD`
and HeterodyneSyncTaskChimeraService. The app calls killProcess on itself;
System.exit records status0 at9245, while the controller records broker exit1.
The full trace establishes the new failure; its framework correction is
separate work.

Automatic account export completed with guest input idle. The unchanged strict
collector accepted 21 entries, 2,831 chunks and 1,449,138 bytes, archive
`baddec481e66521b7c0ba99d719bea4107976c5d441b89a96d7ab13bf16105cb`.
Only afterward was the complete private log transferred using guest byte count,
SHA-256 and canonical base64. The qualified decoder and separate fresh retained
decoder check passed against those exact guest pins without repair. Private
logs remain outside the strict account archive apart from hashes.

All fixture snapshot/plan/import/extraction, strict collection and private-log
decode/check guards and children exited zero with complete cleanup under the
original 600 MiB RSS, 300-second, 64 MiB growth, 1 GiB reserve and output/file
limits. One owned-VM SIGTERM succeeded at18:51:07 UTC; matching stop/ownership
and gone receipts record70754 absent, and QEMU records signal15. CI remained
untouched. The stopped VM retains the final original UART and evidence files.

Storage coverage is retained in four component seals under
`E=S/maps-traffic-stats-checkpoint-sealed-2026-11-04-r1`. Each manifest is at
`E/COMPONENT/sealed/manifest.json`:

| Component | Entries | Manifest SHA-256 | Separate fresh readback |
| --- | ---: | --- | --- |
| prepared | 185 | `1525d9e0e3dc3da8537250ae88d25667beb5b2783cf4ec1d040289f4beaaeb5c` | Passed |
| stopped-r1 | 212 | `e6658ef52e719092849f351868a6c340af9f2fe0c65828f641dab66363e81eaf` | Passed in separate recheck root; earlier five stops retained |
| stopped-r3 | 234 | `d6177f72d7f9d2281d7f1b3bf2c14fb8808c1aa0fefd48e458eaeb670c959ef7` | Passed in separate recheck root; earlier two stops retained |
| controls (17 roots) | 299 | `a0e680253c50ce95793dc1a28961078d9ba8aa2ec901d6ec3278a95f15f17bd3` | Passed |

Every component completed its seal-time internal check. The controls seal
freezes all 14 complete small original roots and the three media-proof
directories, including each interrupted fresh readback. Across the four
component seals, all 17 original roots remain covered; no input or historical
full-bundle requirement was waived. The seven separate VM readbacks record
guard125/child137, reason `observed disk growth` and complete cleanup. Their
initial fresh validation stopped. Subsequent independent VM readbacks passed
under unchanged limits in the separate root described below. No single combined
aggregate fresh readback is claimed.

The original 600 MiB RSS, 900-second, 64 MiB growth and 1 GiB reserve limits
remained unchanged. Prepared-evidence seal r6 at
`S/maps-traffic-stats-preparation-sealed-2026-11-04-r6` also remains intact:
guard125/child137, complete cleanup, 10,452 ms and 70,606,848 bytes growth.
All failed seal roots, original controls and partial outputs remain preserved,
together with every unchanged original checker and complete bundle.

At 20:54 UTC, both pending complete VM readbacks passed in
`S/maps-traffic-stats-checkpoint-rechecks-2026-11-04-r1`, with controls outside
the already sealed component roots. R1 passed in 2,708 ms, sampled RSS
11,354,112 bytes and observed growth 4,157,440 bytes; R3 passed in 2,208 ms,
sampled RSS 12,353,536 bytes and observed growth 12,288 bytes. Both guards and
children exited zero with empty reasons and complete cleanup under the original
600 MiB RSS, 900-second, 64 MiB growth and 1 GiB reserve limits. The qualified
checker received each exact original manifest pin. All four component seals
now have successful separate fresh readbacks; the original complete bundles
remain required.

The new five-entry control root is sealed at
`S/maps-traffic-stats-checkpoint-rechecks-sealed-2026-11-04-r1/sealed/manifest.json`,
SHA-256 `ea45ee40ff767160fd889e4c2efd07cb3aad9c11a3bd4f4bfcda4d8f5f2671bd`.
Sealing and its internal check passed with guard/child zero and complete
cleanup. The separate control-seal readback was refused before launch when
free space fell to 1,139,257,344 bytes, below the 1 GiB reserve plus 64 MiB
growth allowance: guard125, child-1, PID0, zero samples/groups and
`cleanup_complete=false`. Its independent readback remains pending. The two
complete VM readbacks themselves passed; the earlier component and controls
seals were not modified.
