# Explicit 30-minute audit guard

The user continued after the concrete 30-minute preparation proposal. The
additive `audit_wall_ms=1800000` option selects that exact duration. Ordinary
`wall_ms` remains limited to 900 seconds and defaults to 300 seconds. Mixed or
repeated audit settings and every other audit value are refused before files
or children are created. Receipt fields, resource limits, monitoring and
cleanup code remain unchanged. Independent source review passed.

The source base is `169cc9078`. Guard source before/after SHA-256:
`ffd4b958f331b48f909d04826c20fd7e5e8edc9edc91b567982d319795414937` /
`7e36eb0abdf454bfd4c7ddde09cb25d6a75790d37f5234b3eca043cd326fa5b5`.
Checker source: `fa64f990d6fd71fe2356440e0e6f0bb951e83854de4a5cc117b78f0dc3804598`.
Guard executable: `82bf70451bb01ccb09ff162e388f8b64869b63f823e463c51fe0ffa785dd91ec`.

The unchanged original checker was compiled separately and its complete suite
passed against the new guard in 4,646 ms, including backed 8 GiB acceptance,
default/900-second behavior, short deadlines, descendant RSS and nested group
cleanup. The additive focused suite passed in 1,325 ms: exact 30-minute
selection, 33 prewrite/spawn refusals, unchanged receipt/resource fields and
real 250 ms timeout cleanup. The immediate acceptance fixture tests option
selection; enforcement uses the unchanged deadline path and short controls.

All three compiles and both suites passed first attempt under the original
600 MiB RSS, 300-second, 512 MiB growth, 1 GiB reserve and output/file caps.
Outer guards and children exited zero with complete cleanup; expected inner
refusals remain in the evidence. Maximum sampled build RSS was 402,112,512
bytes and maximum observed build growth was 259,313,664 bytes.

Paths use `S=/Users/alex/.local/state/vinix/android`. Frozen before/after sources,
binaries and complete controls remain in `audit-wall-guard-2026-11-04-r1` and
`audit-wall-guard-controls-2026-11-04-r1`. The first legacy-option invocation
record at `maps-framework-jni-load-preparation-2026-11-04-r7` is also retained:
the old guard rejected `wall_ms=1800000` before a receipt, child or image.
These three roots passed a 99-entry seal and independent fresh readback in
180/139 ms under the original 900-second/64 MiB seal limits:
`S/audit-wall-guard-sealed-2026-11-04-r1/sealed/manifest.json`, SHA-256
`09f3af8b944a722fc6f52fdd08ef9a8da91ed98ecacf2eef2d556c86ce0d28c4`.
Both exited zero with complete cleanup. All historical originals remain
required. This qualifies the host guard; preparation and ARM execution remain
separate. CI remains running and unchanged.
