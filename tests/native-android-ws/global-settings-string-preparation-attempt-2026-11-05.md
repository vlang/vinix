# Global String-write preparation attempt stopped by shared disk-growth guard

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

Retry preparation in a fresh `maps-global-settings-string-r2` destination
under the same original limits. Preserve the first attempt and leave the
separate CI job running; no allowance increase or audit waiver is required.
