# Process-package preparation resumed after scoped cache cleanup

After the user continued in response to the explicit V3-cache cleanup proposal,
36 reviewed `/private/tmp/v_501/v3_module_cache_HEX` directories were removed.
The saved target list contains exactly 36 ordinary directories with hexadecimal
suffixes. These match V's own `is_v3_cache_subdir` classification and selective
`wipe-cache --v3cache` handling in
`/Users/alex/code/v-tccbin-bootstrap-20261026/cmd/v/toolcache.v`, SHA-256
`6e5a11bd99253b4747e5988b911b07ff053d2ddcf16c76743df7098bfcae54f2`.
The operation used an explicit path list rather than wiping the whole temporary
directory. Retained Android evidence and CI files were preserved.

Paths use `S=/Users/alex/.local/state/vinix/android`. Complete cleanup records
are at `S/v3-module-cache-cleanup-2026-11-05-r1`: reviewed targets, allocated
usage, process/open-file snapshots, removal output, disk snapshots and times.
The selected directories occupied 7,157,240 KiB. At 21:14:24/21:16:03 UTC on
November 4, shared filesystem free space was 408,172/8,594,840 KiB. Other host
jobs remained active, so these are shared-filesystem snapshots. Both open-file
output streams were empty. Ordinary `/bin/rm -r` completed with exit zero and
empty output streams; the remaining-module-cache listing was also empty.
The initial forced recursive removal was rejected before dispatch. Its preserved
rejection records that no removal child or shell redirection ran for that attempt.

| Cleanup record | SHA-256 |
| --- | --- |
| `targets-before.txt` | `9cb270dfa2c1ca16ee0ed0a1988763345d4e9922b12cc41cbacb78215991de08` |
| `usage-before.txt` | `f6eb00dd8cf5ca689578cc996809fd34880c5fec486a0c5e28940bc8b0120f81` |
| `disk-before.txt` | `e1c3d91c035d2113b0c731f81181c1a5d8b1368245fb06d17cc3fe0bb3564663` |
| `disk-after.txt` | `8cfeab8aef2a4fd678c0600ae2f0228508be3be0491b1d7f943628620573bd3f` |

The current SDK build receipt, native source/header/compiler/helper input
manifests and media capture input/resolution maps were checked: eight small
JSON files contain no V3-module-cache or `/tmp/v_501` dependency paths. This
bounded dependency review leaves all complete historical audits intact. CI
PID23708 remained running; no CI process was signalled or accessed through its
guest interfaces.

The [qualified image tools](maps-process-packages-stage.md), source commit
`385535613`, are reused unchanged. Stager SHA-256 remains
`c341a1ea643046cc25adc193871726d72988275805aefa7c20f995f847a67600`;
the qualified 30-minute guard remains
`82bf70451bb01ccb09ff162e388f8b64869b63f823e463c51fe0ffa785dd91ec`.
Fresh preparation controls are at
`S/maps-process-packages-preparation-2026-11-05-r1`, targeting
`S/maps-process-packages-r1`. Preparation has started its immutable-input audit;
completion and the final image seal remain pending. The 4 GiB outer growth
allowance, 1 GiB reserve, 600 MiB RSS and stager's separate 512 MiB budget are
unchanged. This report establishes no ARM, GMS or Maps result. The earlier
[disk-refused preparation](process-packages-preparation-blocked-2026-11-04.md)
and its complete sealed controls remain required.
