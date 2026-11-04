# Global String SDK and retained native compatibility

The complete retained-native audit passed for the
[Global String SDK](global-settings-string-sdk-2026-11-05.md). It retains the
process-package native producer's original coupling to the process-package
SDK; it does not rewrite that receipt or claim a fresh native compilation.
All 70 consumed classes are identical across native copies and both SDKs in
raw and canonical form. No formatting exception is admitted. Only Global
changes among 2,117 canonical classes; it is absent from native declarations,
generated JNI and exports, and contains no native method.

The audit retains all 91 native origins/92 inputs, generated C, bindings,
721 exports, 58 C/header inputs, ELF dependencies, compiler inputs and the
340-input generator/660-input builder closures. Complete native and both SDK
inventories are rechecked before output; source/C/helper/header deltas are empty.

Using `S=/Users/alex/.local/state/vinix/android`, the retained native root is
`S/current-native-build-2026-11-04-process-packages-r1`, manifest
`0b8ad44d408b90824a69fa7d42c9376965eaa34a93dc81b056050ef227bc3d7f`,
DSO `b69c62304448c1aa0fd5f0cc660acf81cfdd8614b280dad691f53a07d8abcc5f`.
Its original SDK manifest is
`4a354ead173048b39fb26cce709922f8954e27e53e2d3a5d92ecdf427db0645d`;
the successor manifest is
`cadfaa0105eb24580f1cdcef590f707e52aab334e9d7bf164524a403f1b43cbc`.
The complete proof is
`S/global-settings-string-native-proof-2026-11-05-r1/readback.json`, SHA-256
`2d013796764f530124fac248964c53b7e4772c0a2359875d3e8d6f0d1f5ad58b`.

The maintained reader source SHA-256 is
`77b5a7fdffbd0f9a092bcad56524a7daf70ccdd2066be0fced6eefbba82842a8`.
Its first frozen compile omitted three module dependencies and exited1/1 with
complete cleanup; preserve both `global-settings-string-native-proof-tools-2026-11-05-r1`
and `global-settings-string-native-proof-controls-2026-11-05-r1`.
The corrected `r2` tools root freezes the module and transitive sources from
committed `31567cabf`, independently of concurrent media-profile source edits.

The `r2` compile, 721 refusal-control self-test and full readback passed 0/0
with empty reasons and complete cleanup. Matching controls are at
`S/global-settings-string-native-proof-controls-2026-11-05-r2`. Full readback
took 6,507 ms, sampled RSS 47,366,144 bytes and shared growth 13,193,216 bytes,
under 600 MiB RSS, 900 seconds, 512 MiB growth, 1 GiB reserve, 4 MiB output and
an 8 GiB shell file cap. Preserve complete original bundles, frozen inputs and
failed attempts. Delivery, image preparation and ARM execution remain pending;
aggregate evidence sealing/readback is separate.
