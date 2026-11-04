# TrafficStats UID image preparation

The [qualified image tools](maps-traffic-stats-stage.md) prepared the SDK-only
TrafficStats successor successfully from source
`0b435b712faf112e30afdac84fdb66a6baf50de1`.
This establishes a completed host image; actual ARM fixture, GMS, Maps,
imagery and authentication results remain separate and unverified for this pair.

Paths use `S=/Users/alex/.local/state/vinix/android`. Prepared root:
`S/maps-traffic-stats-r1` (`P`); complete preparation controls:
`S/maps-traffic-stats-preparation-2026-11-04-r1` (`C`). The exact qualified
stager is `S/maps-traffic-stats-tools-2026-11-04-r1/stager-project/maps-traffic-stats-stage`,
SHA-256 `a63309357f0f4811b0972ebb0e5bedb780a3adf41bef7cb1faba42472ee06aa3`.
Neither closed P nor C may receive further runtime output.

| Prepared artifact | SHA-256 |
| --- | --- |
| Complete manifest | `2bb3c22ae5beb530dd468f1241c7e252eb8b6b894f3e744e8e770c4a51c290f9` |
| Stage receipt | `888af0a6e1f5e46f22c2811c3b4abcc5bd2d971c26e8190d55017bee9c26e2a8` |
| Boot image | `71ec7ebc3137e8905631cf2764c38a00ce19d574a3d2fa1819e43b23d26b8972` |
| Inherited frozen kernel | `a54505e3725e11bb2f769d62c1260f0b447a4d9fbcde21ba7f9119e08ba75151` |

The stager cloned the completed unbooted `maps-framework-jni-load-r8` image
and added its six-file SDK overlay. The retained native library and installed
frozen kernel remain unchanged; no kernel patcher or stopped runtime image was
used. Both complete 140-inventory audits passed in 64+64+12 batches. The typed
kernel inventory was verified separately before and after use. All 61 module
readbacks and inherited kernel/boot-configuration checks passed. The stage retains its
54-stage ancestry and 143 dependency seals, together with the complete
[SDK/native compatibility proof](traffic-stats-uid-pair-2026-11-04.md).

Preparation guard and child exited zero, reason empty and cleanup complete in
891,473 ms. Sampled aggregate RSS was 89,620,480 bytes and observed shared-volume
growth was 3,875,454,976 bytes. The run used the previously approved 30-minute
outer deadline and 4 GiB shared-growth allowance, with 600 MiB RSS, 1 GiB disk
reserve and original output/file limits retained. Filesystem-wide free-space
changes do not attribute writes to a particular process.

The stager's separate 512 MiB charged-write budget remained unchanged. Its log
reached 200,658,944 charged bytes at seal completion, including 128,974,848
bytes (123 MiB) reserved for the exact module/kernel digest receipts. The stage
receipt records the earlier pre-receipt value of 159,723,520 bytes. Complete
read-only audits refresh only this internal phase baseline with the reserve
enforced; the outer shared-volume guard remains active across the entire run.
All internal budget and audit checks remained enabled.

The first four prepared-evidence seals stopped at the original 64 MiB shared
growth limit. Complete attempt roots remain at
`S/maps-traffic-stats-preparation-sealed-2026-11-04-r1` through matching `r4`.

| Seal attempt | Elapsed ms | Observed shared growth bytes |
| --- | ---: | ---: |
| r1 | 21,329 | 70,197,248 |
| r2 | 7,930 | 68,157,440 |
| r3 | 10,900 | 73,687,040 |
| r4 | 4,006 | 77,385,728 |

Each records guard 125/child 137, reason `observed disk growth` and complete
cleanup. No functional validation error appeared. R2 retained P, C and failed
r1; r3/r4 also retained every earlier complete failed root. All original controls and
partial outputs remain preserved. These interrupted seals do not undo the
completed preparation or establish successful aggregate storage verification.
A complete aggregate seal and independent fresh readback remain pending; the
64 MiB limit has not been increased.

A fresh exact clone passed at
`S/maps-traffic-stats-vm-2026-11-04-r1`, with controls at
`S/maps-traffic-stats-live-controls-2026-11-04-r1`, retaining the original 2 GiB
clone-growth allowance. Guard/child exited zero with complete cleanup in
42,236 ms, sampled RSS 36,061,184 bytes and shared growth 146,739,200 bytes.
Its complete 162-file inventories and inode kinds/modes/sizes match P before
and after cloning. Clone receipt SHA-256:
`77fa64670e38ed970de723363bae2695e79f94225a3655df928619600e6853f7`.
No kernel patch was needed. Aggregate sealing is deferred until after the
guest run; the original inventories and all failed attempts remain intact.
No boot or ARM result is recorded here.
Future runtime controls must use fresh paths, retain every original bundle and
use the signed [TrafficStats UID fixture](traffic-stats-uid-fixture-run.md)
before GMS/Maps.
