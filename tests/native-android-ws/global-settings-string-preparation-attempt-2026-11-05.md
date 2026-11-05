# Global String-write preparation attempts stopped by shared disk-growth guards

The first preparation attempt used the
[qualified image tools](maps-global-settings-string-stage.md) at source
revision `e3472ae08a3ba10ba7dcfb0c76ca96cbe226ac42`. Its outer supervisor
stopped the process during the final complete input recheck for
`observed disk growth`: 4,330,139,648 bytes exceeded the unchanged 4 GiB
allowance. Guard/child exited 125/137 after 764,114 ms, with complete cleanup.
Sampled peak RSS was 83,853,312 bytes. Free space fell from 74,483,126,272
to 70,152,986,624 bytes; the 1 GiB reserve remained intact.

The original limits were 600 MiB RSS, 1,800 seconds, 4 GiB observed shared
growth, 1 GiB reserve and 4 MiB output. Other host jobs continued writing to
the same volume. The guard measures shared free-space changes; this result
does not attribute the observed growth to a particular process. The stage's
last internal charged-growth sample was 178,073,600 bytes, below its separate
512 MiB budget, after the successor kernel readback.

The first complete dependency audit passed. All 62 inherited modules and the
frozen kernel passed readback before cloning. The six-file overlay and updated
boot configuration were installed, then all 63 successor modules and the
kernel passed readback. These completed phases do not establish final image
integrity: the final input audit did not finish, and neither `stage.json` nor
`sha256.json` was produced. No image admission or guest boot occurred. There
is no successor ARM, GMS, Maps or authentication result from this attempt.

With `S=/Users/alex/.local/state/vinix/android`, preserve the complete partial
output `S/maps-global-settings-string-r1` and controls
`S/maps-global-settings-string-preparation-2026-11-05-r1`, including the
original guard, full log, module/kernel digests and command receipts.
The complete two-root, 191-entry attempt seal is at
`S/maps-global-settings-string-preparation-attempts-sealed-2026-11-05-r1/sealed/manifest.json`,
SHA-256 `4091fd5d6d46df460da2c56e523768b2ddb7f98bf32fe4f273f83271aa0d45ba`.
Seal and separate fresh readback passed 0/0, empty reasons and complete cleanup
in 7,698/3,002 ms. Sampled RSS was 12,222,464/12,107,776 bytes and observed
shared growth was 12,480,512/2,252,800 bytes. Both used 600 MiB RSS,
900 seconds, 64 MiB growth, 1 GiB reserve and 4 MiB output. This seal preserves
the failed attempt; it does not qualify the partial image for use.

The fresh `maps-global-settings-string-r2` retry used the same original
limits and stopped during the final input audit for the same reason.
Controls are `S/maps-global-settings-string-preparation-2026-11-05-r2`.
Guard/child exited 125/137 after 675,301 ms, with complete cleanup and
4,295,491,584 bytes observed shared growth. Sampled peak RSS was 78,233,600
bytes; free space fell from 69,525,086,208 to 65,229,594,624 bytes.
The first full dependency audit and 62/63-module plus kernel readbacks passed.
Its last internal charged-growth sample was 354,799,616 bytes, below 512 MiB.
Neither final stage receipt nor output manifest was produced, and no image
admission or boot occurred. Preserve the entire second partial output and
controls; no final image-integrity or successor runtime result is established.

The second attempt's evidence-sealing run also stopped for shared disk growth:
72,810,496 bytes exceeded its original 64 MiB allowance after 8,788 ms,
guard/child 125/137 with complete cleanup and zero output. Preserve
`S/maps-global-settings-string-preparation-attempts-sealed-2026-11-05-r2`,
including its partial seal, root list and original guard/log. That run
does not establish a complete evidence seal or independent readback. The failed
sealing attempt remains part of the retained history.

The user subsequently explicitly approved an 8 GiB outer preparation growth
allowance and 512 MiB evidence-sealing growth allowance. These are
supported options of the existing [qualified host guard](audit-wall-guard-2026-11-04.md),
not implemented guard changes. Its original full checker passed backed 8 GiB
acceptance, larger-value refusals and default 512 MiB selection; its separate
focused checker passed the exact 30-minute option and 33 prewrite refusals.
The acceptance controls select limits without consuming a large disk fixture.
The supervisor requires free space covering reserve plus the complete growth
budget before launch, and retains monitoring and cleanup throughout the run.

The approved limits keep preparation at 30 minutes, evidence sealing at
900 seconds, 600 MiB RSS, 1 GiB reserve and 4 MiB output, with the stage's
separate internal 512 MiB charged-write budget unchanged. It changes only the outer shared-volume
growth allowances. A fresh seal retry at
`S/maps-global-settings-string-preparation-attempts-sealed-2026-11-05-r3`
retains the second partial image, its preparation controls and the failed
second seal directory. The complete three-root, 202-entry manifest at
`sealed/manifest.json` is SHA-256
`8fb98c164313bb2c5345c76b46e4b0b9208ec48ae6d077551a3758af9532f1e8`.
Seal and separate fresh readback passed 0/0, with empty reasons and complete
cleanup in 31,662/12,936 ms, using the approved 512 MiB growth allowance and
unchanged other limits. Observed shared growth was 83,279,872/152,207,360 bytes.
This preserves the failed attempt's complete evidence; it does not
qualify its partial image for use.

The third preparation, targeting `maps-global-settings-string-r3`, stopped
after 333,154 ms with `RSS probe failed: monitor command exceeded one second`.
Guard/child exited 125/137 with complete cleanup. Sampled RSS was 64,913,408
bytes and observed shared growth was 677,130,240 bytes, below the approved
600 MiB and 8 GiB limits. The fixed one-second host `ps` monitoring deadline
expired; this was not a measured target-RSS excess. The log contains only the
initial immutable-input auditing marker. No output directory was created and
no dependency audit or preparation completion is established. Preserve
`S/maps-global-settings-string-preparation-2026-11-05-r3`.

Those controls passed a complete one-root, three-entry seal and separate fresh
readback at
`S/maps-global-settings-string-preparation-attempts-sealed-2026-11-05-r4/sealed/manifest.json`,
SHA-256 `06f311bd96b6ece99d63532b95fde0e1082dd52cd3a16f916d3e7ac169f2bc6a`.
Both guard/child results were 0/0, with empty reasons and complete cleanup,
using the approved 512 MiB sealing growth allowance and unchanged other caps.
This preserves the monitoring failure without waiving or changing its
one-second deadline.

A fresh `maps-global-settings-string-r4` preparation has started, with controls
`S/maps-global-settings-string-preparation-2026-11-05-r4`. It uses the same
qualified tool and approved 8 GiB outer growth allowance; the 30-minute,
600 MiB RSS, 1 GiB reserve, 4 MiB output and internal 512 MiB stage budget
remain unchanged. No completed preparation or runtime result is established
here. All failed attempts and original audit bundles remain retained. CI
remains running and untouched; the active shared compiler cache was not deleted.
