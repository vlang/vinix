# Native JNI correction preparation attempts

Source `79c2eea86` qualifies the [native-only image tools](maps-framework-jni-load-stage.md).
The same qualified executable is used for every preparation attempt:
`S/maps-framework-jni-load-tools-2026-11-04-r1/stager-project-r2/maps-framework-jni-load-stage`,
SHA-256 `7b508aa5d4a0da20d8e01ca74f3e2048482bf409691fd5f82b9de712d4a12a6f`.
Here `S=/Users/alex/.local/state/vinix/android`.

Tool qualification, complete input capture, sealing and fresh readback passed.
The two-root, 16,609-entry qualification manifest is
`S/maps-framework-jni-load-tools-sealed-2026-11-04-r1/sealed/manifest.json`,
SHA-256 `ef7fb7ef6976a3b4d44451bc8ba197472f4c6e5c7a2ab7399867bd0aaa71aec8`.
The separate [clean kernel checkpoint](framework-jni-load-kernel-checkpoint.md)
remains intact. Complete original bundles and historical auditors remain required.

The first four preparation attempts stopped at the original shared disk-growth
limit while auditing immutable inputs. Each log contains only the 50-byte
`MAPS-FRAMEWORK-JNI-LOAD auditing immutable inputs` announcement. No destination
directory or prepared image was created by these attempts, and no functional
validation error appeared before the guard stopped them. The interrupted audits
do not establish successful preparation.

| Attempt | Elapsed ms | Observed disk growth bytes | Sampled peak RSS bytes |
| --- | ---: | ---: | ---: |
| r1 | 31,126 | 540,790,784 | 52,969,472 |
| r2 | 20,656 | 579,006,464 | 53,460,992 |
| r3 | 205,688 | 547,295,232 | 55,001,088 |
| r4 | 229,844 | 586,403,840 | 54,034,432 |

Each of these four attempts records guard exit 125, child exit 137, reason
`observed disk growth`, and complete cleanup. Their limits were 600 MiB aggregate
RSS, 900 seconds, 512 MiB observed disk growth, 1 GiB reserve, 4 MiB output
and shell file-size cap 16777216. Complete receipts and logs remain in
`S/maps-framework-jni-load-preparation-2026-11-04-r1` through matching `r4`;
their absent destination paths were `S/maps-framework-jni-load-r1` through `r4`.

The r3 controls also retain a 45-second `/bin/sleep` probe: guard/child zero,
complete cleanup, 45,104 ms and 173,277,184 bytes observed growth. Passing that
short probe did not establish a quiet full-preparation window. The guard reads
filesystem-wide available space, so these observations do not attribute the
loss to a particular process or establish its cause. CI remains unchanged and
running; no foreign process or VM was stopped or modified.

The four closed controls roots passed a 14-entry seal and independent fresh
readback in 204/183 ms, with guard/child zero, complete cleanup and zero observed
growth under the original 64 MiB seal allowance. Manifest:
`S/maps-framework-jni-load-preparation-sealed-2026-11-04-r1/sealed/manifest.json`,
SHA-256 `e6a121a21cea3abe36594ba1d6c758c8686e342d296ee9cd20a1b9634692df81`.

After that sealed handoff, the user replied **continue** to the concrete
proposal for a 4 GiB outer shared-filesystem growth allowance. The next attempt
used that allowance with the same qualified binary. The stager's separate
512 MiB charged write budget, 1 GiB reserve and all audits remained unchanged;
the outer RSS, wall, reserve, output and file-size limits also stayed unchanged.

R5 again stopped during the read-only input audit, before creating its
destination. Its receipt records 319,407 ms, initial free space 11,384,578,048
bytes, minimum free space 7,074,250,752 bytes, observed growth 4,310,327,296
bytes and sampled peak RSS 55,066,624 bytes. Guard/child exited 125/137 with
reason `observed disk growth` and complete cleanup. The log contains only the
same 50-byte audit announcement; no functional validation error appeared and
no prepared image was created. Complete controls remain at
`S/maps-framework-jni-load-preparation-2026-11-04-r5`; the absent destination
was `S/maps-framework-jni-load-r5`.

R6 used the same binary and 4 GiB outer allowance, recording checkout revision
`5de25f37c684c1de7db3a7fb17d3e2c6a9b8f100`. Its initial full 137-inventory
audit passed, and the five-file native overlay was installed. All 60 module
readbacks, the inherited kernel and boot configuration passed. The stager's
charged write budget reached 135,344,128 bytes, within its 512 MiB allowance.
The final full input audit was still progressing when the original 900-second
outer deadline stopped it. No functional validation error appeared.

The R6 receipt records 900,132 ms, initial/minimum free space
7,102,328,832/3,218,063,360 bytes, observed shared growth 3,884,265,472 bytes and
sampled peak RSS 72,384,512 bytes. Guard/child exited 125/137 with reason
`wall time` and complete cleanup. Controls remain at
`S/maps-framework-jni-load-preparation-2026-11-04-r6`. The partial output at
`S/maps-framework-jni-load-r6` has neither `stage.json` nor `sha256.json` and
must not be treated as prepared or used for a guest run. It remains preserved;
any retry must use a fresh output and complete every audit again.

The complete R5 controls, R6 controls and partial R6 output passed a three-root,
186-entry seal and independent fresh readback in 17,691/9,385 ms. Both guards
and children exited zero with complete cleanup; observed growth was
33,456,128/58,368,000 bytes under the original 64 MiB seal allowance. Manifest:
`S/maps-framework-jni-load-preparation-sealed-2026-11-04-r2/sealed/manifest.json`,
SHA-256 `2719100244e241677d6edfb9fc0604d77f3bc69d1698d518704c7d7238e38395`.
The historical four-root seal above remains untouched.

The user then continued after the concrete 30-minute outer deadline proposal,
retaining the same 4 GiB shared-growth allowance and every other limit. R7's
legacy `wall_ms=1800000` invocation was rejected by the original guard before
any child, receipt or output. The additive explicit
[audit-wall option](audit-wall-guard-2026-11-04.md) is now qualified, including
the unchanged original full suite and new focused controls. Its evidence seal
also preserves the R7 record. A fresh full preparation will use
`audit_wall_ms=1800000`; neither R6's partial output nor an interrupted audit
can substitute for successful preparation.

R8 completed successfully from source `cd8b57df0add14767e5ba89f5b2d8e87f1885ef0`
at `S/maps-framework-jni-load-r8`. Both complete 137-inventory audits, typed
kernel verification and all 60 module readbacks passed. The completion manifest
is `31cf35f40e606d6c08d7b6e4daaad3d8b935d2afccfb5971199819456eadbfdb`;
stage receipt `1253d40b75878fd444946a55c86d4f48521d6756b5d1f427d99ca9615335769f`.
Guard/child exited zero with complete cleanup in 764,657 ms, sampled RSS
70,893,568 bytes and shared growth 2,133,159,936 bytes under the approved
30-minute/4 GiB outer limits. The stager's unchanged 512 MiB charged write
budget reached 189,050,880 bytes at seal completion, with 1 GiB reserve intact.

The prepared image and complete R8 controls passed a two-root, 184-entry seal
and independent fresh readback in 11,573/7,539 ms, guard/child zero and complete
cleanup under the original 64 MiB seal allowance. Manifest:
`S/maps-framework-jni-load-preparation-sealed-2026-11-04-r3/sealed/manifest.json`,
SHA-256 `2e09250ad19f7b088af20c92de09cc03a235f629d2c7b245a6f937f1c625bf90`.
Independent metadata review confirmed all native/SDK/kernel pins, 59 preserved
modules plus the new overlay, five payload files and 141 dependency seals.

The qualified exact clone at `S/maps-framework-jni-load-vm-2026-11-04-r1`
passed complete source/destination inventory and inode checks in 18,027 ms,
guard/child zero with complete cleanup and 67,198,976 bytes observed growth.
Its sidecar receipt hashes to
`b6cd2bbc9b3956ee340bc7eff49db40d555bd5573d62d6267c05ed4193fa924e`;
controls are in `S/maps-framework-jni-load-live-controls-2026-11-04-r1`.
The verified kernel is already inherited; no new kernel patch is required.
Run the unchanged signed ARM fixture using the
[new delivery profile](bootclasspath-jni-fixture-run.md), then retry GMS and
Maps. Preparation establishes a sealed host image; ARM/GMS/Maps remain separate.
