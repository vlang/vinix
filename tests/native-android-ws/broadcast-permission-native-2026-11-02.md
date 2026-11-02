# Broadcast permission fresh native coupling

The complete JNI producer passed against the new 2,111-class broadcast-permission
SDK. This is a fresh native bundle with new SDK provenance. The original
asset-locales native producer remains unchanged as historical evidence.
Context and ATLLoadedApp are two of its 70 consumed classes, so their Java
changes required new coupling even though native implementation and JNI stayed
unchanged. Signed ARM broadcast behavior and GMS/Maps remain separate checks.

The [SDK result](broadcast-permission-sdk-2026-11-02.md) records core `0b00959bc`
and producer `84a791b70`. Native source revision is
`0b00959bc20d3dd9e6e6804b9a60393949d29a94`. The qualified public producer froze
the current builder, old compiler/library, current native source and generator
closures before generation and compilation. Its strict AArch64 ELF64 shared
link, Werror/no-undefined, complete header checks, exact source-export comparison
and final input rechecks passed on the first attempt.

Paths below use `S=/Users/alex/.local/state/vinix/android`.

| Artifact | SHA-256 |
| --- | --- |
| New SDK manifest | `49daffbfa9dc1dcc598e453eaae3611df7702963aa5b659022545149af7132d5` |
| `current-native-build-2026-11-02-broadcast-permission-r1/sha256.json` | `e371c8d365b78493f9f9d660ceceb1cb2b1382eaa60cae06bcbe4aad0c6c233b` |
| Native `build.json` | `193944e2025385ae69641fa6fc4dc0da52123d508929748727d479be88628732` |
| Native DSO | `29b2631c36a4a8c802e904e936c23e090fb2de3b5019ac93548df1b15de2a8f1` |
| Generated JNI | `d054fd51235e1893db9f5d78a747660abb69f185a803a6caa01c0dfc206d7a6c` |
| Generated C | `d96b7dd8e1e69bb22575bd7762e8e2890feaed379e8a57031aab73c27c8160c7` |
| Native guard receipt | `0c40a017d64f8a609993f5c6b1ba1f153bab46420458897ec18cb4d241a9e0dc` |

Guard and child exited zero with complete cleanup in 20.235 seconds. Sampled
aggregate RSS peaked at 544,473,088 bytes; the detailed time maximum was
374,308,864 bytes, with zero swaps and 97,693,696 bytes observed shared growth.
Limits remained 600 MiB RSS, 300 seconds, 1 GiB growth, 1 GiB reserve, 4 MiB
output and shell file cap 16777216. No VM or other task-owned compilation lane
overlapped the build. The reusable bootstrap executable still hashes to
`197c331ccdd9cd2064e6dcf2c0a9ef4af9b41eec4c64cdbf2e438d644073af72`;
builder source remains `b307f9afc36f19aefdf160c51c528f6bf7b157b4cfcced7d625fc697dfe55eeb`.

Independent read-only comparisons confirm all 91 native source origins,
92 current inputs, 721 exports, binding specification, generated JNI and generated
C remain byte-identical to the asset-locales producer. The complete 70-class
input tree differs only in Context and ATLLoadedApp; both copied files match
the exact new SDK. The other 68 inputs remain unchanged. The new utility class
stays outside native membership. The media audit separately verifies the full
canonical SDK/native pair before image admission.

All 58 consumed C/header values remain equal. Only five local keys rebase from
the old native root to the new root: generated C and four copied headers.
The remaining 53 toolchain keys stay unchanged. The new raw inventory hashes
to `7e36f5094960bb5608d4b537a800cfcaf23894ade36e90efc25cd742d6365764`;
the root-bearing JSON itself is different. Full compiler-root trees and both
copied compiler-library closure maps compare equal. After exact compiler-root
normalization, the native-generator closure retains 340 entries. Builder closure
grows from 644 to 650: 642 unchanged, two changed and six added, with no removals.
The changed helpers are framework.v and framework_autofill.v; the additions are
the unmanaged-query, stats, subscription, autofill-service, keyguard-policy and
broadcast-permission providers. Complete old/new maps and exact pins are retained.

The DSO is a different artifact from the old `c87ccc…` library. Both have 961,776
bytes, the same dependencies and export ABI. Link compiler/hash, flags and input
DSOs match; fresh source/include/output paths differ. Each DSO embeds its own
absolute stb_image.h and stb_truetype.h assertion paths. Generated code/header
bytes are equal; no broader binary-equivalence claim is made.

Complete new evidence remains in `S/current-native-build-2026-11-02-broadcast-permission-r1`
and `S/broadcast-permission-native-controls-2026-11-02-r1`. Controls include the
original plan, guard/log, four exact comparison diffs, header-path strings and
`result.md`, SHA-256 `bf5ddf7123445303d5f7411c1fab86ef466876a4249ed0717b78d199ea45a264`.
The joint twelve-root source/producer seal and separate fresh-process readback
passed all 11,486 entries, including both native bundles and these controls.
Its manifest at `S/broadcast-permission-producers-sealed-2026-11-02-r1/sealed/manifest.json`
hashes to `b755b2951d12e064f648b6baa872019aba414dfe61739c65197500382d9ef67d`.
Historical complete bundles and their original auditors remain required.
