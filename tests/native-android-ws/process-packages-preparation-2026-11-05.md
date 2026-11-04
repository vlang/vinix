# Process package-list image preparation

The [qualified image tools](maps-process-packages-stage.md) prepared the
process-package SDK/native successor successfully from source
`5b80e7f7b1c82f1f215fb1b6fe11923e0d9b356f`. Preparation, complete module readback
and evidence sealing passed. ARM fixture execution, GMS stability, Maps
rendering, imagery and authentication remain separate and unverified for this pair.

Paths use `S=/Users/alex/.local/state/vinix/android`. The closed prepared root
is `S/maps-process-packages-r1` (`P`); complete preparation controls are
`S/maps-process-packages-preparation-2026-11-05-r1` (`C`). Reused qualified
stager `S/maps-process-packages-tools-2026-11-04-r2/stager-project/maps-process-packages-stage`
hashes to `c341a1ea643046cc25adc193871726d72988275805aefa7c20f995f847a67600`.
Keep P and C closed; runtime output belongs in fresh clone/control paths.

| Prepared artifact | SHA-256 |
| --- | --- |
| Complete manifest | `9e032c999e8d57b7ce205841c53146ed653996be037deaf0e82cfd4b1262b535` |
| Stage receipt | `4cab7f95e92594b9d65172ebf78daa105419f4f6886aa6c261235b0404a643de` |
| Boot image | `86d0625dd7d6e866d9f3f7cc6208cfab4767fe5775db1c4cd951f3d442f0b5ff` |
| Inherited frozen kernel | `a54505e3725e11bb2f769d62c1260f0b447a4d9fbcde21ba7f9119e08ba75151` |

The stager cloned the closed `maps-traffic-stats-r1` parent directly and added
the exact nine-file SDK/native overlay. The [host-qualified pair](process-packages-host-2026-11-04.md)
retains framework manifest `4a354ead173048b39fb26cce709922f8954e27e53e2d3a5d92ecdf427db0645d`
and freshly coupled native manifest
`0b8ad44d408b90824a69fa7d42c9376965eaa34a93dc81b056050ef227bc3d7f`.
The installed JAR and DSO match their qualified pins. The overlay retains
native DSO mode 0755, other regular-file modes 0644 and directory modes 0755;
no unexpected inode kind is admitted. Headless inputs change only JAR/DSO;
Maps deployment changes the eight qualified inputs and its framework/native
manifest fields.

Both complete 142-flat-inventory audits passed in 64+64+14 batches. The typed
kernel inventory was checked separately before and after use. All 61 inherited
modules remain unchanged; all 62 successor module readbacks and both kernel
readbacks passed. The stage retains 55 parent stages and 146 dependency seals.
The installed kernel is inherited unchanged, with its original separate
59-module checkpoint lineage preserved. No kernel patcher or stopped runtime
image was used. Independent metadata review matched the SDK/native/kernel pins,
module and dependency membership, payload modes and completed guard results.

Preparation guard and child exited zero, with empty reason and complete cleanup,
in 502,501 ms. Sampled aggregate RSS was 92,127,232 bytes; observed shared-volume
growth was 2,326,458,368 bytes. The previously authorized 30-minute deadline and
4 GiB outer growth allowance remained enabled, with 600 MiB RSS, 1 GiB reserve
and original output/file limits. Shared free-space changes do not attribute
writes to a particular process.

The separate 512 MiB internal charged-write budget remained enabled. Its final
trace records 226,635,776 charged bytes, including 131,072,000 bytes (125 MiB)
reserved for exact module/kernel digest receipts. The stage receipt captures
the earlier pre-receipt value of 157,999,104 bytes. Subsequent receipt/seal writes
explain the difference; neither value replaces the outer shared-volume guard.

The complete three-root, 210-entry preparation aggregate is
`S/maps-process-packages-preparation-sealed-2026-11-05-r1/sealed/manifest.json`,
SHA-256 `aafacf7484fdddcc5b39062a1c8815d42ff2340bb0905c07e8cded2ccf67c923`.
It preserves P, C and the complete [scoped cache-cleanup records](process-packages-cache-resume-2026-11-05.md).
Seal and separate fresh readback passed with guard/child zero, empty reasons
and complete cleanup in 4,360/2,091 ms; sampled RSS was 13,041,664/11,042,816
bytes and observed growth 5,361,664/6,897,664 bytes. Both retain the original
600 MiB RSS, 900-second, 64 MiB growth, 1 GiB reserve and 4 MiB output limits.
All original bundles, failed attempts and historical auditors remain required.

A fresh exact runtime clone passed at
`S/maps-process-packages-vm-2026-11-05-r1`, with controls at
`S/maps-process-packages-live-controls-2026-11-05-r1`. Its complete 167-file
inventories and inode kinds, modes and sizes match P before and after cloning.
Clone guard/child exited zero with empty reason and complete cleanup in
7,919 ms, sampled RSS 36,126,720 bytes and observed growth 83,111,936 bytes,
under 600 MiB RSS, 900 seconds, 2 GiB growth, 1 GiB reserve and 4 MiB output.
The sibling clone receipt hashes to
`9e3ea7b574e614c6a6b414eeeb19d2d7c719dffc519ff087fbbb3d879406e28f`;
all original clone tool/source/receipt sidecars remain required. No kernel
installation is needed.

The [signed ARM fixture](process-packages-fixture-run.md) and separate GMS/Maps
retry remain pending. The [earlier disk-refused attempt](process-packages-preparation-blocked-2026-11-04.md)
and its sealed complete controls remain preserved. CI remains running and
untouched. This report establishes no ARM fixture or GMS/Maps result.
