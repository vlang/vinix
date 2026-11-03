# WebView provider-package query SDK and fresh native pair

The complete SDK and a freshly coupled native library passed host production
and independent readback. Source `63e1e4374dbae1589ec89d979499ae79a01568ff`
contains the nullable public static `WebView.getCurrentWebViewPackage()` query
from `e6035988e`, with declaration checks that accept the generator and DEX
disassembler's different orders. The query returns null without initializing a
provider or renderer. The [source checks](../native-android-tools/webview-package-source-check.md)
preserve all 42 existing WebView methods, two fields and six native declarations.
Host qualification does not establish ART execution, GMS stability, Maps,
authentication or imagery; those remain separate runtime checks.

Paths below use `S=/Users/alex/.local/state/vinix/android`. The producer at
`S/webview-package-framework-builder-2026-11-03-r1` passed fresh compilation and
the complete producer self-tests. The first full SDK attempt at
`S/combined-account-webview-webview-package-framework-2026-11-03-r1` passed over
the exact Build ABI parent, manifest
`23c75e5be1445f177d7a6a801f907235d166b7a0f541c41bf0895f861bbed3e9`.
Class membership remains 2,117. Only WebView changes, gaining one Java method;
all 2,116 other canonical classes, existing methods, fields and native
declarations remain unchanged. Complete raw/canonical class and JAR gates,
assembly roundtrips and final source/input rechecks passed. Only classes.dex
changes within the JAR. The SDK retains exact compiler/smali inputs and full
source closures; host SDK and dynamic libraries remain environmental inputs.

| SDK artifact | SHA-256 |
| --- | --- |
| SDK `sha256.json` | `c79d421bd385777aefd00b0be85a287af7907b1bb6dd55244d7546eb99ea958a` |
| SDK `build.json` | `4233d762a124f215eaa798f66af1c2c6407511aa829d30b3279ccdee6a01aba5` |
| Framework JAR | `0e5e2632bc64ad9d548379491c59ed4e8a91d42fcfa6677b75aae4798dfeb7a9` |
| Framework DEX | `5c6e4914d93c63566484ac907f69bb94fe7aef161a58cba589126922c0478f7b` |
| Raw WebView | `3cd08baf04f82e1f0d7587219f4f6e5c3310d439086ba6ad6c016b20e543ba1d` |
| Canonical WebView | `dd38134f402fbcb5297a50cea97eb7f903963e526026be3a49301ba67e69434e` |
| SDK production guard | `5968e62711c332839dfd2c4f518746a9c22ee2af3cba44928c578db2b50ce2a1` |

WebView is one of the 70 native-consumed classes, so the old native bundle was
retained as comparison evidence and a fresh producer was required. The old
bundle remains at `S/current-native-build-2026-11-02-broadcast-permission-r1`,
manifest `e371c8d365b78493f9f9d660ceceb1cb2b1382eaa60cae06bcbe4aad0c6c233b`,
with its original broadcast SDK provenance. The qualified Resource-lock r2
bootstrap `197c331ccdd9cd2064e6dcf2c0a9ef4af9b41eec4c64cdbf2e438d644073af72`
captured and compiled the unchanged native producer
`b307f9afc36f19aefdf160c51c528f6bf7b157b4cfcced7d625fc697dfe55eeb`,
then replaced its process with the private frozen builder. The new native
receipt couples directly to the new SDK manifest above. The original r5
baseline, restored compiler library, complete frozen inputs and strict
AArch64 Werror shared-link policy remain unchanged.

The first native attempt at
`S/current-native-build-2026-11-03-webview-package-r1` stopped at the original
1 GiB shared-volume growth limit after 19.208 seconds. Guard/child exited
125/137 with complete cleanup, sampled RSS 560,021,504 bytes and observed
growth 1,251,438,592 bytes. JNI/C generation and header discovery completed;
there is no DSO or completion seal. Its complete scratch output and original
control root `S/webview-package-native-controls-2026-11-03-r1` remain preserved.
The guard hashes to
`38b3c9526f3e098b725779591503b58cad643dae26712b1f461636158455dd7e`.
No functional compiler error was reported and no limit was raised for retry.

The fresh retry at `S/current-native-build-2026-11-03-webview-package-r2`
passed with the same bootstrap, source and limits. Its original command,
logs, source snapshots and guards remain in
`S/webview-package-native-controls-2026-11-03-r2`. Both SDK and native
immutable receipts record source revision `63e1e4374dbae1589ec89d979499ae79a01568ff`.

| Fresh native artifact | SHA-256 |
| --- | --- |
| Native `sha256.json` | `1434754497efa741ddb2b378cbb693862ee96eb04cb304d9cbeeae5cc98b4dc0` |
| Native `build.json` | `6ecd2f94ae08b0062d5830e3c8f2903ac6c0559c8615d81ac085646c85bf2e3c` |
| Native DSO | `e72e10edd8fed637ec0053100afe535aca7ad6a763e5cd311e712d4d2362c8c2` |
| Generated JNI | `d054fd51235e1893db9f5d78a747660abb69f185a803a6caa01c0dfc206d7a6c` |
| Generated C | `d96b7dd8e1e69bb22575bd7762e8e2890feaed379e8a57031aab73c27c8160c7` |
| Complete exports | `8ca376443ae60e8324646f967220d753a1f23d732b7aa1eddb5488f1fb43cc1b` |
| Consumed C/header inventory | `7b6c9cac169e58e08656c278be9e7ec498c9cb1490b85b3832c3a3a8d932dff7` |
| Native production guard | `71e43f3e0856dd2a6e7a8e0d4e0a92a62f595c5b7fba20d7ec85ba3b9e2c94a0` |

The independent [readback checker](webview-package-native-readback.v) fully
rehashes both native bundles and their original/new SDKs, checks strict native
receipt/export/ELF contracts, and repeats the complete four-bundle readback
before writing its result. Its source review passed before compilation.
All 91 native origins, 92 current inputs, generated JNI/C, bindings, four
native headers and 721 exports remain byte-identical. All 70 copied native
class inputs match the new SDK exactly. Comparing original/native class inputs
finds exactly the established Context and ATLLoadedApp raw formatting pairs
plus WebView; canonical comparison changes only WebView. Both raw pairs and
the complete WebView pair are recorded explicitly in the result.

The full 58-entry consumed C/header inventory has equal values after rebasing
exactly five owned keys: generated C and the four copied headers. The other
53 absolute keys are unchanged and their live bytes were checked. Complete
restored compiler-root inputs and the 340-input native-generator closure are
equal after exact compiler-root normalization. The complete native-builder
closure grows from 650 to 659 inputs: framework.v changes and exactly nine
providers are added (Build ABI, Component parcel, EventLog, Message parcel,
Messenger, Quick Settings, Secure Settings, Usage inactive and WebView package).
Every before/after pin and the complete ten-entry after map are retained in
the readback result; there are no removals or compiler-library changes. The
image gate must admit that measured map explicitly, without a broad whitelist.

The strict native compiler argv differs only in the exact output root.
ELF dependency/SONAME/interpreter/search-path identities agree: libandroidfw,
libpng16, libsqlite3 and libc remain the dependencies, with no interpreter or
search path. The new DSO has different bytes from its predecessor; equal
JNI/C does not imply binary equality across the changed embedded build paths.

| Successful phase | Guard seconds | Sampled RSS bytes | Detailed RSS bytes | Shared growth bytes |
| --- | ---: | ---: | ---: | ---: |
| SDK producer compile | 2.833 | 420,544,512 | 432,652,288 | 4,771,840 |
| SDK producer self-tests | 0.395 | 15,515,648 | 14,434,304 | 2,211,840 |
| Full SDK production | 66.732 | 502,890,496 | 490,307,584 | 449,667,072 |
| Fresh native production r2 | 33.165 | 561,594,368 | 376,700,928 | 173,744,128 |
| Readback checker compile | 4.020 | 355,745,792 | 282,247,168 | 73,609,216 |
| Complete independent readback | 6.183 | 48,070,656 | 48,250,880 | 14,622,720 |

All successful guards/children exited zero, reasons are empty, cleanup is
complete and detailed logs report zero swaps. The readback compiler emitted
one pre-existing unused `parse_pax` notice and no error. Limits remain 600 MiB
sampled aggregate RSS, 300 seconds for compilation/production, 900 seconds for
complete readback, 1 GiB reserve, 4 MiB output and file cap 16777216; growth
remains 512 MiB for tool compilation/readback and 1 GiB for SDK/native production.
No compiler or Java overlapped another task-owned compiler, Java or VM phase.

The readback result remains at
`S/webview-package-native-readback-2026-11-03-r1.json`; its byte-identical copy
is `S/webview-package-native-controls-2026-11-03-r2/readback-result.json`, both
SHA-256 `eac13fc17657011adf9aa022eeb393cfa9c34fdf9ef10ef4297e1185b6d380ef`.
The matching frozen/current checker source hashes to
`6a94ffa4984464ee84bcae37a742bb51bd4b79af921e02b6376383f20d3c9c2a`,
and its actual readback guard is
`b2a83cdabd1afd7089daf457c096b03d4b739ac37d98e4a9480b6e337f8f65b3`.
All four native roots are closed. Full historical prerequisite evidence,
including the failed attempt, remains required. Image qualification and live
ARM/GMS/Maps results are reported separately.

Joint sealing and separate fresh-process readback passed on their first
attempts for 13 complete roots and 18,987 typed entries, including both focused
proofs, caller audit, producer/SDK controls, exact Build ABI parent, both native
attempts and controls, and signed fixture/controls. The list remains at
`S/webview-package-producers-sealed-2026-11-03-r1/roots.txt`, SHA-256
`dc5420912c5a0bbece32901e484ac92ddc0ccd70ece9a2c0d468975760161337`.
Its `sealed/manifest.json` hashes to
`79ddd9ad129cc7bdc89b37a3ff7378b5e5453e2ed638b430202862c89c027367`.
Seal/readback took 2.288/1.112 guard seconds at sampled RSS
28,622,848/21,905,408 bytes, detailed RSS 27,361,280/23,576,576 bytes and
observed growth 8,151,040/2,215,936 bytes. Both guards/children exited zero
with empty reasons, complete cleanup and zero swaps under unchanged
600 MiB RSS, 900-second, 64 MiB growth, 1 GiB reserve, 4 MiB output and
file-size limits. The original standalone readback JSON remains retained in
addition to its sealed byte-identical controls copy. Historical prerequisite
bundles and their unchanged auditors remain required.
