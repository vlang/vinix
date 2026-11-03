# Framework boot-loader native source checks

The native source checker passed the complete two-file delta against the frozen
WebView-package r2 producer. It admits only the reviewed boot-path helper,
64 KiB stack buffer and explicit VM option, the 13/15 option counts with TLS
slots 13/14, and the absolute `Runtime.load(String, ClassLoader)` replacement.
The original 16-option allocation, all other flags, APK class path, system
API-JAR/resource-APK path, native paths and unrelated source bytes remain exact.
This deliberately retains the nonempty system path used by ATLPaths and
framework resource discovery. The boot path contains the ten original ordered
ART JARs followed by the framework JAR; the resource-only APK stays on the
system path. The companion SDK resource-loader edits are checked separately.

`framework-boot-source-check.v` extracts the actual `ws_boot_classpath` function
verbatim into fresh host projects. `frameworkbootcheck/main.v` supplies an
independent eleven-path expectation. Twenty-seven cases passed: the real runtime
root, a percent-containing root and a 4,095-byte root, zero/one/two-byte and
truncated buffers, exact fit, extra capacity and 64 KiB capacity, null roots and
buffers, exact output bytes, NUL termination and unchanged surrounding sentinels.
The long-root result qualifies this helper only: the retained 8 KiB system-class
path formatter has its preexisting size limit.

Seventeen source controls reject wrong VM counts, colliding/unused option slots,
insufficient option allocation, smaller stack storage, empty system path,
modified APK/native paths or flags, inclusive helper bounds, library-name
loading, missing loader association, changed JNI descriptor and unrelated
runtime changes. Two independently compiled helper mutations failed the intended
assertions: inclusive success at capacity equal to the required text length,
and an extra byte passed to snprintf crossing the caller's sentinel. Their
actual exit-1 assertion output remains retained; the qualifying controller and
actual helper exit zero.

Complete evidence remains outside Git under
`S/framework-boot-source-check-2026-11-03-r1` and matching `r2`, where
`S=/Users/alex/.local/state/vinix/android`. Both contain original controls and
frozen test sources. The r2 proof includes complete before/after native files,
all three actual/mutant projects, compiler/run records and final input readback.
The source base is `612beac7a86338d61a20594453baf554f939d34a`.

| Input or result | SHA-256 |
| --- | --- |
| Frozen native r2 manifest | `1434754497efa741ddb2b378cbb693862ee96eb04cb304d9cbeeae5cc98b4dc0` |
| Original bootstrap | `2214cb26fd0ea9cd31041e1eca250c347793b6306b1ef9440ae991f764270469` |
| Original runtime | `145c627c5d069c907fcb649650132e17e378508c122a18f22d0a37e3a8d3b1de` |
| New bootstrap | `a716e6820e6581f018fe6bd25ebc6735251d6265c71f4290e8c9224c2dcf5bae` |
| New runtime | `bba5097f2ebfaad299af46192ec3b672630e9a3db2ca86d8cc73c84a6121440b` |
| Extracted helper | `ff3112e26b87e83ce58d52011d41567dad9c011d30ed58bd945f5319d1f575b5` |
| Checker source | `9d720408ce482a21eb7da7cba18fc61341e03ec3786150ccb6c76b362819d19f` |
| Harness source | `4c97a41ab7fe096ab844e20a17ce060d91d47036f79615a5ac85c38665ab7d1a` |
| Passing r2 proof receipt | `2b1d44920aa607e0b62f392915657795933eca95e199dbf2770ecc020cba9c1b` |

The initial driver compiled cleanly, then stopped during input capture because
its source-file 16 MiB bound was incorrectly applied to the qualified 29.6 MiB
compiler. The failed r1 receipt records exit 1 with complete cleanup before any
helper compilation. The corrected r2 keeps the 16 MiB source bound and uses a
separate compiler-only 32 MiB bound plus the exact qualified compiler hash.
No source oracle, semantic check or resource guard was relaxed.

R2 compile/proof guards and children exit zero with empty reasons, complete
cleanup and zero swaps. Compile took 1.489 seconds at 340,393,984 bytes sampled
aggregate RSS; proof took 3.673 seconds at 205,864,960 bytes sampled RSS and
150,224,896 bytes detailed maximum RSS. Observed growth was 1,413,120/7,577,600
bytes. Limits remain 600 MiB aggregate RSS, 300 seconds, 512 MiB shared-volume
growth, 1 GiB reserve, 4 MiB output and file-size cap 16777216. Sources and
compiler pins passed final readback; no compiler diagnostics were suppressed.
Full native/SDK production, deployment and ART execution remain separate work.
