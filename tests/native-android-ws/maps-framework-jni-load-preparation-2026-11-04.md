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

All four preparation attempts stopped at the unchanged shared disk-growth
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

Every stopped attempt records guard exit 125, child exit 137, reason
`observed disk growth`, and complete cleanup. Limits remain 600 MiB aggregate
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

Preparation needs a sufficiently quiet full-audit interval under the existing
outer 512 MiB shared-filesystem allowance. A larger outer allowance requires
an explicit resource-policy decision; no allowance was increased here. The
qualified stager separately retains its own 512 MiB charged write budget and
1 GiB free-space reserve, all 137 inherited inventories before and after,
typed kernel verification and 60 module readbacks. Once preparation succeeds,
clone its sealed result without another kernel patch and run the unchanged
signed ARM fixture using the [new delivery profile](bootclasspath-jni-fixture-run.md),
then retry GMS and Maps. No successor image or runtime result is established.
