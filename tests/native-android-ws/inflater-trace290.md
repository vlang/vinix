# Opt-in inflater diagnostics

Base source revision: `78f265f07`; timing scan/report correction:
`a7219aefd`. The Maps287 replay already establishes the full search, details,
directions and route-preview UI path; see [frame-metrics287.md](frame-metrics287.md).

Maps287 contains 1,831 thresholded timing records. One complete record shares a
line with an unrelated console prefix, so strict analysis correctly rejects it.
The explicit `maps-timing.v scan` mode recovers that prefix, reports its recovery
and rejection counts, and retains the original serial hash and line count.
Its selftests pass; strict `analyze` still rejects line 31,176. The recovered
sample set has zero rejected records. Maximum sampled looper, rendering and input
phases are 9,623, 8,262 and 4,377 ms respectively. These overlapping, thresholded
samples do not measure interaction latency or isolate the cause of a stall.

Verbose per-tag LayoutInflater diagnostics format parents/results and resolve
resource names even when nobody needs the trace. `framework_inflater_trace.v`
guards the two `createViewFromTag` verbose blocks before formatting. A cached
`VINIX_ANDROID_TRACE_INFLATER=1` opt-in restores them. Factory calls, return values,
exception paths and warning/error logging retain their existing instructions.
Other inflater diagnostics and unsupported `Path.op` warnings remain present.

`inflater-trace-build.v` and `inflater-trace-framework.v` use corrected288's sealed
128-source framework snapshot and consumed build inputs, adding only the new
generator and its registration. Builds use the retained 109a compiler with
assertions, explicit VROOT, `-nocache`, `-cc cc` and `-O2`. Actual assembled DEX
comparison finds exactly LayoutInflater changed, VinixInflaterTrace added and no
classes removed. Native286 is reused without rebuilding. Independent read-back
verifies all 6,954 build-bundle files and the exact fileset; a wrong manifest pin
is rejected. The initial compiler attempt failed on unsupported Option syntax;
its evidence remains separate and was never launched.

Artifacts are retained under `/Users/alex/.local/state/vinix/android/`:

| Artifact | Location | SHA256 |
| --- | --- | --- |
| Framework290 bundle manifest | `inflater-trace290-build-2026-10-25/sha256.json` | `63050cca1e3b6c263e6cdb77774d517437dda869db7caa5bbfb71bbdc7292138` |
| Framework290 JAR | bundle `framework/api-impl.jar` | `50fe71a5719b74fb4fe0cfd0531213b216cad87ee87fc78e5cb348f38237b232` |
| Preserved failed compiler attempt | `inflater-trace290-failed-build-2026-10-25/sha256.json` | `58cd4c6b5b52ad20b0df7d5b6b4ea891018b0873f6197c3d519349253b0739ff` |
| Reused Native286 library | `input286-build-2026-10-25/native/libvinix-android-native.so` | `c46f56d775efef3807e34ece9c8bb5bdb949c47f6db54e59dee02e82cf60019a` |
| Three-variant fixture bundle manifest | `inflater-trace292-fixture-2026-10-25/sha256.json` | `6aad28bbd334fbaff5d07bd89f2b4cfb11f89c861e9a5abac86cb51ee967ef45` |
| Maps291 completed bundle manifest | `maps291-2026-10-25/sha256.json` | `b0db74c46c20fd955da17a610df5bfdcae5d9d46bd6e9dcb4b10c316e0c2f878` |
| Maps291 timing derivative manifest | `maps291-timing-2026-10-25/sha256.json` | `4bfe2d2c2292c062833b390125ea055f894c8ec9d52cd2d128e064ff72465107` |

The failed compiler attempt is now retained as the complete
`inflater-trace290-failed-build-2026-10-25.tar.gz` archive (SHA-256
`03e1870821cc12b3722bd79161aee1c9d9ad6fe2955ffd6809ae44fcdef15646`).
Restore it before using its unchanged complete checker; the qualified restore
and cleanup receipt are recorded in
[the storage report](../../docs/android-evidence-storage-2026-10-26.md#inflater290-failed-build-cold-preservation).

The same APK (`42ede5b22789c9fbdbedbec896511d4015c33c43b0f4b402ff2b3b2f9f6ae9d5`)
passed three actual guest runs:

| Framework/environment | Formatting callbacks | Semantic check | Raw outcome |
| --- | --- | --- | --- |
| Framework288, variable absent | Present | Pass | `window_observed` |
| Framework290, variable absent | Skipped | Pass | `window_observed` |
| Framework290, exact value `1` | Present | Pass | `window_observed` |

The fixture checks parent/result diagnostic counters, factory argument identity,
callback order/counts, result identity and exception cause identity. It also
checks the guest environment, warning/error markers and `BOOTSTRAP-READY`.
All variants share the frozen compiler, APK, suite and Native286 inputs. They
use the same qualified clean launcher; only the trace launcher adds the explicit
environment setter. The runner verifies consumed input hashes before and after
each run. Semantic receipts are `{old,new,trace}-guest-semantic-check.json`;
unaltered raw results are `run-{old,new,trace}-guest/results.json`.

The fixture sealer rejects nonregular entries, confirms all guest PIDs have
stopped, and reads back the exact file inventory and hashes. Independent
`build-bundle-check.v` verification passes all 941 files and the exact fileset;
an incorrect manifest pin is rejected. Its receipt is retained outside the
bundle at `inflater-trace292-fixture-check.json`. Failed preparation
attempts launched no guests and remain separately sealed. They exposed a changed
live compiler, missing historical cached objects, cache-prefix differences,
unfrozen helper inputs and missing helper headers. The final runner freezes the
actual compiler and helper closure, restores only qualified same-hash cached
objects and checks final consumed inputs. Their complete bundles have the
canonical fixture path suffixed `-prepare1` through `-prepare5`:

| Preparation | Manifest SHA256 |
| --- | --- |
| 1 | `5dcaeecef93bd891b79d2ac43a407ddf0953806c31001264b016eb437c99a74b` |
| 2 | `0d24d77e46d2a5cb6baa0b51cd36408d778d92402e2ece251f422996787718d9` |
| 3 | `2da49784ab749726bb16c94aaafa990eca8c0c94c6d732c9130c72c2dc65cbe7` |
| 4 | `600a3ea238a15da76e9be4054fdf2195d69754992740c0bc2472a18059cf3765` |
| 5 | `1ec40a296767b69e6e7414eb38129728edea6171462bea2aa3b884b5659d37a0` |

The scan source, analyzer binary and derived Maps287 reports are also retained
in the Maps291 bundle's `timing289/` directory. The original complete Maps287
bundle and its manifest remain unchanged.

Maps291 uses the same Native286, initial media, workload and unchanged raw
classifier as Maps287, with Framework290 substituted. Manual screenshots and
timestamped interaction commands establish this replay's UI results:

| Screenshot (UTC, 2026-10-25) | Observed state |
| --- | --- |
| `after-skip-early.png` (04:21:14) | Onboarding gone; North America tiles visible after Skip at 04:21:10–11 |
| `paris-suggestions-early.png` (04:23:08) | Live Paris suggestions after typing at 04:23:05 |
| `paris-details-second.png` (04:23:24) | Paris place card, map and Directions button |
| `directions-second.png` (04:23:43) | Starting-point search |
| `origin-suggestions-early.png` (04:23:59) | Eiffel Tower, Avenue Gustave Eiffel, Paris suggestion |
| `route-second.png` (04:24:16) | Eiffel Tower → Paris endpoints, drive estimate 15 min and Preview button |
| `preview-early.png` (04:24:31) | “Head toward Pont d'Iéna” |
| `preview-next-early.png` (04:24:41) | Next changes instruction to “Turn left onto Pont de l'Alma” |
| `preview-previous-early.png` (04:24:55) | Previous returns to the first instruction |

These are observed states at capture times, not exact presentation latency.
Earlier intermediate captures still show transitions. The route estimate and
preview instructions work; this does not qualify every drawing feature or
continuous navigation. Unsupported graphics warnings remain visible.

The full 600-second observation completed without process exit or classified
failure markers. The unmodified raw classifier reports `window_observed` and
`functional_passed: null`; the functional evidence above is manual screenshot
inspection. Completed bundle read-back verifies all 1,968 typed entries and
their contents; an incorrect manifest pin is rejected.

The final serial SHA256 is
`60a9e74bdecc618c6410800532602782e1262ae40d5980de4fc4853775f885f9`.
Its timing scan accepts 816 records, with no recovered prefixes or rejected
records. Maximum sampled looper, rendering, input and total-loop phases are
2,776, 1,558, 2,379 and 2,989 ms. These are thresholded phase samples; totals
overlap, and interaction timing differs from Maps287. They do not establish a
causal latency improvement or overall responsiveness percentile.

`maps291-timing-preserve.v` retains the committed scanner source, scanner binary,
exact serial snapshot and strict sealer in the derivative bundle. Replaying the
scan produces byte-identical JSON/text outputs without changing the originals.
Independent verification passes all 25 files and the exact fileset; its receipt
is `maps291-timing-check.json` outside the bundle.

Remaining graphics gaps include both unsupported `Path.op` overloads and six
worker-thread errors for absent `Bitmap.native_save_to_png` during route/preview
use. Preview remains usable. Most `Path.op` warnings precede route selection,
so these logs do not establish why the broad route polyline was not verified.
Caller evidence is needed before attributing that rendering gap to either API.
