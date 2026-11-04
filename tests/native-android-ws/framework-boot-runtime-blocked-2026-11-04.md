# Framework boot kernel installed; ARM checks await admission

The framework boot-classpath image is prepared and the frozen replacement
kernel is installed, with complete readbacks passed. Installation reused the
exact qualified SDK 27.0 patcher; the SDK 27.2 draft remains unqualified.
Boot and ARM execution await qualified host admission while the user's
**Leave CI running** choice remains in force. No new fixture, GMS, Maps
rendering, imagery or authentication result is established.

The preparation, clone and first two handoffs below record historical states.
Their pending-kernel statements are superseded by the current installation
and admission results appended afterward; all original evidence remains required.

Preparation used source `38aa4e5dd7ae9471427afde9e90a0adea33f75cf`, containing
core `992b426c3`, SDK companion `a16baf6c3`, signed fixture `63ba81754`,
delivery `133c69c0a` and [SDK/native qualification](framework-boot-pair-2026-11-03.md)
`399af92a1`. The Android SDK, native library and fixture remain unchanged by
the host SDK 27.0 → 27.2 requalification described in the
[media report](maps-framework-boot-stage.md). Earlier complete evidence and
the [November 3 resource handoff](framework-boot-runtime-blocked-2026-11-03.md)
remain required.

Paths use `S=/Users/alex/.local/state/vinix/android`. The independently qualified
stager prepared `S/maps-framework-boot-r1` with completion manifest
`43309208792e5ce55ed9c4b8af9e0ae5b6ff1f849f43b27a04948659224dd499`
and stage receipt
`a87760cf0daef526558da7b2b24068b868fe16f194e2f8692da8548eed8f465b`.
Both complete 134-inventory audits and all 59 module readbacks passed.
Preparation controls `maps-framework-boot-preparation-2026-11-04-r1` (`P`)
record guard/child zero, empty reason and complete cleanup in 606,929 ms under
unchanged preparation caps. The stager invokes no kernel patcher.

The separately granted exact clone is
`S/maps-framework-boot-vm-2026-11-04-r1`; all four clone sidecars remain intact.
Its sidecar receipt hashes to
`2e3c15bbcb2ff95335aca69a62a0a347a32cd56c963a35c5366357b97f9dd74e`.
Source/destination inventories, typed metadata and manifest/stage hashes match.
Guard/child exited zero with complete cleanup in 14,395 ms: sampled/detailed
RSS 33,226,752/32,227,328 bytes and observed growth 52,682,752 bytes, under
original 600 MiB RSS, 300-second, 2 GiB growth and 1 GiB reserve limits.
At this earlier handoff, the clone had not received the frozen replacement
kernel or booted.

Complete failed attempts remain retained. The closed tool root
`maps-framework-boot-tools-2026-11-03-r1` (`T`) preserves original SDK 27.0
attempts and failed current input capture; `T/sdk27.2` preserves the original,
r3 and r4 FAT stops and their complete scratch. The SDK 27.2 patcher
`628cd967d406e25123980be7f5f0daa188b8efb659f36442b6c776170188119f`
remains unqualified for production kernel installation. A fresh same-binary
r5 at `S/maps-framework-boot-patcher-fat-2026-11-04-r5` stopped after 28 FAT
passes at the original growth cap: guard 125/child 137, complete cleanup,
66,663 ms and 546,426,880 bytes observed growth. Its receipt hashes to
`f4b852fe01c2c09febd48aaa460b32acc222af3646049b5253ff7bd992461790`;
log to `3f97205f4e9807de7bb81bea0a689bffb9a76ebb3946dd658b2647e71f1b2647`.
Complete r5 scratch remains under `r5/scratch`; preservation passed 0/0 with
complete cleanup in 63 ms. No functional failure appeared and no cap was raised.

At that stage, aggregate tool evidence sealing remained pending. Both failed seal
roots `maps-framework-boot-tools-sealed-2026-11-04-r1` and matching `r2` remain
preserved. Closed `T`, the separate inventory-batch root and the original
complete SDK 27.0 closure retain their original audits and source snapshots;
the smaller handoff seal below does not substitute for that pending aggregate.

An earlier root-requested read-only check at 08:03:56 +0300 found unrelated
Debian CI QEMU PID 89417, PPID 1, group 89416, started November 4 at 06:47:15
local time, with unchanged 32 GiB/eight-CPU configuration and active owner
evidence writes. Its workspace is `/Users/alex/code/v-linux-ci-followup-20261104`.
Qualified [coexistence policy](../android-webview-browser-probe/run.v)
allows at most 20 GiB foreign RAM and 32 GiB combined RAM on this host;
32 + Vinix's fixed 12 = 44 GiB exceeds that allowance. Its drive keys and
QMP option also fall outside the qualified foreign-argv schema. One read-only
admission check recorded the schema refusal. No foreign VM signal, file change,
QMP/guest access or policy relaxation occurred. No stop is authorized by its
apparent activity or completion state.

The small closed handoff roots are the complete
`maps-framework-boot-runtime-audit-2026-11-04-r1` (`A`), matching
`maps-framework-boot-live-controls-2026-11-04-r1` (`C`) and `P`. They preserve
the plan, clone result, exact helper/foreign identities, refusal and controls.
The separate three-root, 28-entry seal at
`S/maps-framework-boot-handoff-sealed-2026-11-04-r1/sealed/manifest.json`
hashes to
`2e5c92bda9e876a2a1696b4ebe3f54f312b386043659a54c2f33b747b34d3d86`.
Seal and independent fresh-process readback passed guard/child zero with
complete cleanup in 128/203 ms, observing 1,257,472/110,592 bytes growth under
the unchanged 64 MiB cap. This binds only the complete small handoff controls.
At that historical handoff, full aggregate qualification, kernel installation,
boot admission and actual ARM/Maps checks were still required.

Later on November 4, the user selected **Leave CI running**. That preference
remains in force; no foreign VM was stopped or changed. A fresh read-only
snapshot at 11:24:41 +0300 found replacement QEMU PID 6395, PPID 1, group 6394,
started at 09:45:45 local time, with the same 32 GiB/eight-CPU allocation and
unsupported foreign-argv options. Its writable CI state now resides under
`/Volumes/V-CI-RAM-20261104`. The same qualified admission constraints still
block our fixed 12 GiB guest. Earlier sealed `A/C/P` remain unchanged.

The same-binary FAT r6 at `S/maps-framework-boot-patcher-fat-2026-11-04-r6`
again stopped at the original shared-growth cap after 17 FAT passes: guard
125/child 137, complete cleanup, 29,478 ms and 538,308,608 bytes growth.
Receipt SHA-256 is
`fcce211235be9800dc8558e63b1f2de8fee3717030fc94f3f2b6c028616a4d3a`;
log SHA-256 is
`158f6da2078b484226745b37075c76076630932d632a24a336cdf10d57f9fd5b`.
Its full scratch remains intact under `r6/scratch`; preservation passed 0/0
with complete cleanup in 127 ms. No cap was raised or functional failure found.
No further retry is planned while host writes persist.

Fresh complete read-only handoff roots
`maps-framework-boot-runtime-audit-2026-11-04-r2` and matching
`maps-framework-boot-live-controls-2026-11-04-r2` passed a separate two-root,
11-entry seal and independent fresh-process readback. Manifest at
`S/maps-framework-boot-handoff-sealed-2026-11-04-r2/sealed/manifest.json`
hashes to
`228843b8581f64457da056f9db88f0d1f67e7b465d0aa77c11ebe61aea7f6336`.
Both guards/children exited zero with complete cleanup in 208/306 ms,
observing 438,272/40,960 bytes growth under the unchanged 64 MiB cap.
This covers only the small second handoff controls. At that historical point,
full aggregate sealing, patcher qualification, kernel installation and runtime
checks remained pending.
Future kernel output must use a fresh kernel-controls root; future live output
must use live-controls-r3 or later, without appending to sealed C2. The existing
exact clone was then unmodified and unbooted; no runtime result was claimed.

A later no-write probe observed 103,120,896 bytes shared growth in 10,890 ms;
the next 45-second probe passed 0/0 with complete cleanup and 122,880 bytes
growth. A fresh same-binary FAT r7 at
`S/maps-framework-boot-patcher-fat-2026-11-04-r7` nevertheless stopped after
37 FAT passes at the original growth cap: guard 125/child 137, complete
cleanup, 155,018 ms and 539,459,584 bytes growth. Its complete scratch remains
under `r7/scratch`; preservation passed 0/0 with complete cleanup in 131 ms.
The brief quiet interval did not establish a quiet full-run window. All failed
attempts remain retained; the SDK 27.2 draft `628cd967...` stays unqualified.

The exact old SDK 27.0 executable
`864cd44a611fc4e2f0a5ecb5bc85f2fecaed4ef0768e598a2769b817cc481542`
was instead qualified for reuse by the
[archived-input verifier](framework-boot-archived-patcher.md), source
`461e2ac187db1a7db3b70dba2058ebd2b7a840a5` and report commit `6ba379aa9`.
Its original complete 52-profile/45-FAT pass remains bound to that binary.
The specific old-tool four-root, 8,408-entry seal hashes to
`5b0218f4451713a99c86969a13659cdcd57e97f83b49f9b7700cac85494c51a1`
and passed separate fresh readback. This does not transfer qualification to
the new SDK 27.2 draft or weaken the original auditors.

The separately granted kernel-only operation used that exact old executable
against the existing clone and frozen kernel build receipt
`1e9077779aaed08188e6f8111ca9ceb27b479517ece736a58157049f004fb36d`.
All kernel, FAT, module and final readbacks passed. Fresh controls
`S/maps-framework-boot-kernel-controls-2026-11-04-r1` (`K`) record guard/child
zero, empty reason and complete cleanup in 75,639 ms, sampled RSS 39,976,960
bytes and growth 1,203,974,144 bytes, below the original 2 GiB cap. Original
600 MiB RSS, 300-second, 1 GiB reserve and output/file caps remained unchanged.

| Installed artifact | SHA-256 |
| --- | --- |
| Kernel patch receipt | `4ae68440e0ae6525245cb6cafc00e0cdad4ddbdbce6c18f176b76098ce772d75` |
| Frozen replacement kernel | `a54505e3725e11bb2f769d62c1260f0b447a4d9fbcde21ba7f9119e08ba75151` |
| Patched stage receipt | `f89341c069721d053ac168dd1ddd2fadbf4262dcb4715fdd5d194ad17d15e60d` |
| Patched boot image | `8a9ed7d36ef13c3006039cc8643b3eb7d0335abb5e1311f7c3121f10ba4c06bf` |

The original stage remains at `stage-before-kernel.json`. Later qualified
read-only admission at `S/maps-framework-boot-boot-admission-2026-11-04-r1`
(`R`) refused with `exactly the selected foreign QEMU required`: multiple
active QEMUs were present in its process snapshot. Guard/child exited 1/1
with complete cleanup in 116 ms. No lifecycle start, boot, foreign stop,
QMP/guest access or policy relaxation occurred. **Leave CI running** persists.

Complete closed `K+R` passed a separate two-root, 13-entry seal and independent
fresh readback at
`S/maps-framework-boot-kernel-handoff-sealed-2026-11-04-r1/sealed/manifest.json`,
SHA-256 `7bcaf0f32e78fa0d942e8b4877d6338b7635076d6c79fe3e2d62bde21ddfd7a9`.
Seal/readback took 146/290 ms, both with complete cleanup. `R` retains snapshots
of the actual stage/kernel JSONs at the identities above. All earlier sealed
`A/C/P` and archival roots remain unchanged; future live controls require a
fresh root beyond those already sealed.

Whole `T/B/new-draft` aggregate sealing remains pending. Its further attempts
at `S/maps-framework-boot-tools-sealed-2026-11-04-r3` and matching `r4` both
stopped at the original 64 MiB shared-growth cap: guard 125/child 137 and
complete cleanup. Q3 took 12,735 ms at 81,108,992 bytes growth; Q4 took
18,181 ms at 67,657,728 bytes growth and produced no manifest. All complete
attempt roots and partial outputs remain preserved. These aggregate stops do
not undo the exact old-tool qualification or actual kernel installation pass.
The new draft remains unqualified; boot admission and ARM/Maps checks remain
outstanding. No additional aggregate or full-FAT retry is planned this turn.
