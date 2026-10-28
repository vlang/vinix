# Maps browser polling runtime, 2026-10-28

The rebuilt browser passes the previously stalled Skip transition: Maps reaches
its main UI and London search returns place details. The map remains beige;
usable map tiles and Google account authentication are unverified. This is
four of six completed milestones (about 67%), counting ARM regressions, broker
startup, onboarding and Skip. It is not an estimate of remaining effort.

All artifact paths below are relative to
`/Users/alex/.local/state/vinix/android/`. The complete preparation and host
checks are recorded in [the staging report](maps-browser-poll-stage.md).
Stage `maps-browser-poll-r3` records source revision
`41f03337d50d38446799dc98e2fece4b626e87a5` and inventory SHA-256
`f27b08e45994fb2e9cf2c2aac695e73c62f17e0b4785fdb310cbebb1f54ac297`.
Its browser producer is `current-browser-build-2026-10-27-poll-r1`, inventory
`fa39f1486d651dff8904a9d75e82cf67d462b2c41511a1a4cd3a184c49239e62`,
with library SHA-256
`16def2047bf7605a23d949ff7b6b56bc56dcece038136553a98a0524b26ded1a`.
The deadline correction is committed as `9f01a1edb`; its exact source digest is
`3d40120b6b3c8c3fd60d54fed64977476d588f88b39665e2766a132507a74513`.

The single VM, `maps-browser-poll-vm-r2`, used 12 GiB and four CPUs. Its frozen
kernel has SHA-256
`a54505e3725e11bb2f769d62c1260f0b447a4d9fbcde21ba7f9119e08ba75151`,
source revision `ecbd3964aff243304e16df45271c7de8dee4d2da` and build receipt
`1e9077779aaed08188e6f8111ca9ceb27b479517ece736a58157049f004fb36d`.
Kernel installation preserved all nineteen modules. The runner is
`maps-native-heartbeat-runtime-build-2026-10-27-r1/runner`, SHA-256
`2419d0760fa92a3e9caa3e60c5596836400616cad8205ca8e6118ade14979908`,
with retained source digest
`c13a45576372481b911e0623dda7b0080438c7c5ba54b668c681459d57b67e12`.
`launch.json` pins QEMU, firmware, media and exact argv. No later checkout edit
is part of this deployment.

Skip was clicked at (602,149) at 08:58:52 UTC. The 08:59:44 capture shows the
main search bar, Explore/You/Contribute navigation and map controls. Input
sequence 24/25 was dispatched with `handled=1`, `exception=0`; frame publication
continued. Main heartbeat samples advance from progress 14,743 to 26,939 and
31,159 in sleep, then 36,235 in render, rather than remaining in the old web
stall. A bounded public uncaught-exception count was zero after opening search.

The London query was entered after the field focused. The 09:50:35 host capture
shows London, United Kingdom and Directions/Share/Save/More actions. The map
area and photo placeholders remain blank. The 09:52:07 diagnostic capture shows
EGL and COMPOSE samples with `different_rgb=0`, `opaque=307200`,
`transparent=0`, and matching first/center pixels `f0ede5ff`. This establishes
uniform sampled buffers, without proving a particular tile/network/GL cause.
Readback memory is reused, so these counters alone do not establish successful
readback on every frame. No Google account flow or successful login was observed.

| Capture in VM root | Host UTC | SHA-256 |
| --- | --- | --- |
| `maps-after-skip-02.png` | 08:59:44 | `cc763c5512d356fc2f7bb57e1a6935a3bdfc392f9c36fae125170d637043a9eb` |
| `maps-input-frame-after-skip-01.png` | 08:59:32 | `61eae33fb8595d3408d86cafaa65b7db5616e4063ac0e2c25c8e6fe4c436b42a` |
| `maps-main-after-search-01.png` | 09:00:28 | `c177465bf11370099d27b667824a8a5d86f56116aeab8228a34dd8ce29437970` |
| `maps-london-result-01.png` | 09:50:35 | `b154eec062fa04fd57fb14bb28febd9f832ee83ec412cfda38eb27e10b8858d1` |
| `maps-surface-query-02.png` | 09:52:07 | `ea415c97a4f6754ceaa8cc548cc5af378d07af2db71567593d74a7c8054b9b13` |

Host and guest elapsed time differ substantially in this run. The controller
receipt records guest 08:54:16–09:10:36, `service_ready=true` and
`bounded-session-ended-no-authentication-claim`. Both initialization failure
lists are empty. `broker_exit=137` and `cleanup_survivors=2` prevent a clean
guest-shutdown claim. Host SIGTERM was requested at 09:52:51. The stop command
returned 1 while observing a transient ownership mismatch during exit; the
ownership-bound `reconcile-stop` succeeded at 09:53:21 and recorded absence of
PID 46644. Final UART exactly matches the captured full snapshot.

The unchanged strict collector accepted the exact suffix without frame repair:
24 entries, 1,441,584 archive bytes, 2,816 chunks, archive SHA-256
`27e0f830d7d0755b1de7d5081ee999b08b77a18636873aed4163641737d5c353`.
The 2,290,518-byte interval SHA-256 is
`09b8e0342e089676f80231ef708cd614891be3e57ca35ebc71f0cf8af4cb3fc8`;
the full 2,291,391-byte UART SHA-256 is
`1f258f38bf490ef68576f6f96b6342a1738f7f28cd590b5089ed611accea596b`.
Snapshot and import guards/children exited zero with complete cleanup. Their
sampled process-tree peaks were 12,189,696 and 27,951,104 bytes respectively;
limits were 600 MiB RSS, 300 seconds, 1 GiB reserve and 512 MiB shared growth.
Complete commands, receipts, source closures and exact bytes remain in
`maps-browser-poll-runtime-audit-2026-10-28-r1`, the VM and retained build roots.
Private Maps/broker logs are excluded from the producer's public archive.

The complete-root seal `maps-browser-poll-runtime-sealed-2026-10-28-r1` passed:
89 roots, 90,950 entries, manifest SHA-256
`27896fea28f2e177f05516e97a68b103b6480b10784b493624c50fdc70d4676a`.
Its adjacent `maps-browser-poll-runtime-seal-2026-10-28-r1.json`/`.log` record
guard/child exit zero, complete cleanup, 148.332 seconds, 35,405,824 bytes sampled
RSS and zero swaps. The independent complete readback also passed, with receipts
`maps-browser-poll-runtime-readback-peer-2026-10-28-r1.json`/`.log`, 77.827
seconds and 23,314,432 bytes sampled RSS. Its receipt SHA-256 is
`aab5d2790b3864f6805e57e66e7172f2b3b79964328a53516013fc17f4773816`.
The independent UART snapshot, strict import and five PNG comparisons passed
too. Both complete-root commands used a 600 MiB RSS cap, 300 seconds, 1 GiB disk
reserve and a 4 GiB shared-growth cap backed by available space.
