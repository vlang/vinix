# Preserve requests made during a layout traversal

Source baseline: `527785d36a3284b1c3b2bf47f3dd18e7c4c065cd`.
The checks below cover the request-layout changes relative to that baseline;
their retained inputs and source hashes identify the tested implementation.

The native WS renderer previously cleared `dirty` after attachment, measurement
and layout, losing a `requestLayout()` made by any of those callbacks. The new
native entry increments a request generation and marks the window dirty. Root
and dialog rendering snapshot that generation before attachment and retain a
changed generation when consuming layout's ordinary dirty mark. Dialog rendering
also retains the incoming root dirty state. Later observer and draw invalidations
remain pending. A subsequent traversal without another request becomes idle.
The counter uses the existing WS/UI-thread ownership; these checks do not test
concurrent callers.

The framework consumes `layoutRequested` before `onMeasure`, then preserves a
new request through size, layout and layout-listener callbacks. `requestLayout()`
marks every View ancestor even when the requesting child's flag was already set,
so a pending child can schedule its settled parent again. The generated startup
fixture covers those callbacks, the next measurement, stable measurement caches
and repeated pending-child propagation.

## Native host regression

`layout-request-host.v` extracts the selected production `ws_render`,
`ws_render_dialog`, request entry, traversal dispatch and WS structures, then
executes them with the controlled JNI/drawing stubs in
`layoutrequesthost/harness.v.txt`. The unchanged Native315 control sources are
from `maps327-2026-10-25/native-pinned-build/native/atlframework`, with bindings
from its sibling `bindings.txt`, under the external state root below.

All six independent old controls compile, publish the first frame and fail at
the intended retained-`ws.dirty` assertion. The current complete suite passes
requests from root/dialog attachment, measurement and layout; a next traversal
becoming idle; eight observer/draw invalidations; two pre-draw cancellations;
fourteen exception positions with identity, short-circuit and TLS checks; a busy
back buffer; and a null-WS native request. This executes host stubs, not ART.

Every bundle below is relative to
`/Users/alex/.local/state/vinix/android/`. Each run bundle has 17 payload files
and passed independent complete-file readback. Bundles retain production inputs,
extracted source, actual generated C, build/run logs, compiler pins and receipts.

| Bundle | Manifest SHA256 |
| --- | --- |
| `layout-request332-host-new-v4-2026-10-25` | `981da8bcb1a31d57434350b301531ff23943035251be254ad14a3c987b110341` |
| `layout-request332-host-old-root-attach-v4-2026-10-25` | `f0b870711ac6ceef1a6dc723506e9e5e5ef3a0bced1f325555e54a6c5e925723` |
| `layout-request332-host-old-root-v4-2026-10-25` (measure) | `3477af985d73da914821061798e6c1072fc50b591f7d424c527f25f423f649ff` |
| `layout-request332-host-old-root-layout-v4-2026-10-25` | `8b979b2ce7ce569d20088ab51649499f35106bdda47ba6c70b27ec6e35e82cec` |
| `layout-request332-host-old-dialog-attach-v4-2026-10-25` | `7feaed11ed0c4c96380fb4fd9d2875fec345bad3039b059b898c8557de086aa5` |
| `layout-request332-host-old-dialog-measure-v4-2026-10-25` | `b0f0ed3b5b75111f487c172bc1ad4c34d6debf3ffcb31e5406fd27b2312da1ca` |
| `layout-request332-host-old-dialog-v4-2026-10-25` (layout) | `0c397fa6be3dd13e756de02f223ec4e911e22bab7e2f67f34307575b62323609` |

The corresponding seven external receipts replace the bundle suffix
`-2026-10-25` with `-readback-2026-10-25.json`. They are also retained in
`layout-request332-host-tools-2026-10-25`, together with the final runner binary,
runner/harness source, sealer/checker source and binaries, and runner build logs.
That tool bundle passed independent readback of all 20 payload files; its
manifest SHA256 is
`10eee516b95e36c1cc06ba5db84f3ddbafd4aedfdf3a0609cf1dc1832c478303`.
Its external receipt is `layout-request332-host-tools-readback-2026-10-25.json`.

| Tool/input | SHA256 |
| --- | --- |
| Runner source | `c0c003a768c5199dd02239e7634d562435c9f9006c1ba6281a20d49a09189ebf` |
| Harness source | `96c744c22fd28b87805b01d6ae625c98c0b4cba0f976b6bce4efcd5b31ffabe8` |
| Final `runner-v4` binary | `0b7a0d5d3aa80709d5e8e684ee0dcef96c19cdcbf60e22d2574561951b6acfdd` |
| V compiler, `build/android-maps/queue284-tools/v_old276` | `109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e` |

## Framework generation and DEX checks

The public framework transformation ran against the sealed Framework329 View
input (baseline manifest
`4f526669c32b91db3da92d3508b6aa97297d8a8b48b89fef29f6cd3f1f64559e`).
Before/after View DEX assembly and disassembly passed: only `requestLayout()V`
and `vinixPerformLayout(IIII)V` changed among 429 methods; 427 remain identical.
Eleven malformed or already-patched inputs were rejected. The public targeted
fixture installer emitted exactly three classes, whose probe DEX also assembled
and disassembled successfully. The probe was not executed.

The following bundles use the same external state root as the host evidence.
Both passed independent exact-file/hash readback. The build retains 631 consumed
V inputs, equal before/after compile pins, generated C and C compiler logs.
It uses the original VROOT; system SDK/dynamic libraries and non-adjacent native
inputs remain environmental dependencies.

| Bundle | Payloads | Manifest SHA256 |
| --- | --- | --- |
| `layout-request332-framework-build-v1-2026-10-25` | 694 | `aa98f0c6edcbf186799005ec46e8a1f60093ec8b743573acae743ffc0ae7c291` |
| `layout-request332-framework-check-v1-2026-10-25` | 52 | `ed6e2f0f8b8138be94b25691362c81307fe62d6e27438843178453d24ef73b5e` |

Readback receipts are the sibling files
`layout-request332-framework-build-v1-readback-2026-10-25.json` and
`layout-request332-framework-check-v1-readback-2026-10-25.json`.

## Full framework build

`layout-request-framework-build.v` built the complete Framework332 JAR from the
sealed Framework329 snapshot and the two committed `13fe935f4` generator changes.
The frozen snapshot has 139 sources. The actual output DEX retains 2,068 classes:
2,067 are identical and only View changed. Its method comparison again finds
429 methods, with only `requestLayout()` and `vinixPerformLayout()` changed.
This comparison covers method declarations and bodies; it does not independently
compare View's remaining directives.

The complete bundle `layout-request332-framework-build-2026-10-25` has 7,061
payload files and manifest SHA256
`6f3d2a9ebcffa24cb61b4a765abb866d90914e96363af241e7cd67a5387d20cf`.
Its `framework/api-impl.jar` SHA256 is
`0229315058b2d24f1f84d886fc47b3fab6fd3b0b7cc7c32f0b9771908276d9ca`.
Both the builder and an independent root readback verified the complete bundle;
the latter receipt is the sibling
`layout-request332-framework-root-readback-2026-10-25.json`.

The bundle retains 550 framework and 288 runner V inputs, equal before/after
closure checks, two actual generated C files, commands and compiler pins.
Unchanged dependencies match the sealed Framework329 inputs. The original VROOT,
system SDK, dynamic libraries and non-adjacent native inputs remain environmental
dependencies. Building and comparing this JAR alone does not qualify ART or Maps.

## Full native build

`layout-request-native-build.v` built Native332 from the sealed Native315
snapshot. Exactly four of its 85 source files changed: the request generation
field, root and dialog retention, and the existing generated request-layout
binding. The binding list changes one row; all 607 JNI exports are identical.
The tool proves that each bounded production transformation also reproduces
the committed `13fe935f4` parent-to-commit change. It preserves Native315's
historical timing instrumentation, so these frozen sources differ from the
current checkout beyond the layout change only where the baseline already did.

The complete bundle `layout-request332-native-build-2026-10-25` has 2,418 payload
files and manifest SHA256
`40b1099c58abe7fb3729ee2b48fd13d171f9ebaf70d1b83e26b5ad9f93aac163`.
Its `native/libvinix-android-native.so` SHA256 is
`2231ee3def626a72119cd80d646966ec5ba2fa6cd7dd74a790fe9bcb9db5869b`.
The independent complete readback receipt is the sibling
`layout-request332-native-root-readback-2026-10-25.json`.

Frozen, before-build, after-generation and after-build checks passed. The bundle
retains the exact source closure, source diffs, emitted native C, commands,
compiler pins, cross-compiler specifications and consumed runtime inputs. The
native generator's V closure matches Native315. Host-tool generated C was not
retained; the actual emitted Android native C was retained. Original toolchain
paths, system SDK and dynamic libraries remain environmental dependencies.

The first freeze rejected Native315's historical timing instrumentation before
compilation. Its complete 89-file partial bundle remains at
`layout-request332-native-freeze1-rejected-2026-10-25`, manifest SHA256
`39410504cea43cd8c888381268e83fccc7eaaf9942c84a18b51523bcfd567d1e`;
independent full readback passed. The successful builder above applies the
bounded committed delta while preserving that instrumentation.

## ART guest qualification

`layout-request-run.v` ran three ART variants with the same signed APK, clean283
launcher, shared runtime files and independently cloned pristine media. Only
the framework JAR and native SO vary. Each guest verified that all
`VINIX_ANDROID_TRACE_*` keys and `ATL_UGLY_ENABLE_LOCATION` were absent, including
empty-valued keys. The existing 1536 MiB preparation and 1024 MiB guest disk
gates passed; the framework and native inputs match the sealed builds above.

The detached startup probe qualifies callback flags, cached measurements and
pending-child propagation in ART. The subsequent attached checks wait for a
nonzero draw baseline and two stable 200 ms samples before arming a one-shot
request from root `onMeasure` or dialog `onLayout`. Each phase requires at least
two measure/layout/draw callbacks, no pending request and unchanged counters
over the next 200 ms. The draw counter observes native traversals despite Java
measurement/layout caching. This proves that sampled quiet interval; the host
suite covers the other native callback positions separately.

| Framework / native | Exact observed outcome |
| --- | --- |
| 329 / 315 | `AssertionError: callback request lost, extra traversal or cached measurement not consumed`, native stage `start activity`, controlled exit 1 |
| 332 / 315 | Manual probe PASS, then `AssertionError: root callback request did not schedule the next measurement`, native stage `main looper`, controlled exit 1 |
| 332 / 332 | Manual, root-next, root-idle, dialog-next and dialog-idle PASS; `BOOTSTRAP-READY`; live window through the 45-second observation, no failure markers |

Both negative checks require exactly the intended assertion and two ordered raw
failure markers: the exact native stage followed by the controlled exit. All
three semantic checks passed; raw startup classifications remain separate.

The complete 877-file bundle `layout-request332-guest-v2-2026-10-25` has manifest
SHA256 `d57b396f526b6d40c6f611a43afbaf3c247d55036658e464caa4c720934d7b01`.
Its independent full readback receipt is the sibling
`layout-request332-guest-v2-readback-2026-10-25.json`. It retains frozen sources,
consumed V inputs, generated C, tool pins, signed APK, actual signed-DEX
disassembly, before/after input checks and complete guest evidence.
Runner source SHA256:
`b364f43f4b71af3ef0177ddb37d60ea4d983e73d34f3fbe11a98fceb407c6a0c`.
Signed APK SHA256:
`94d6f8716b89619a103002f7d6eddeff32d8c352a4f48d5ae2b42fdc0b3879d7`.

The first run reached the intended old-framework assertion but its checker
incorrectly expected only one raw failure marker. That rejected 723-file bundle
remains at `layout-request332-guest-v1-2026-10-25`, manifest SHA256
`654c871bdbad1be214f81266492df6b7fe62fb56f85ba693c452ed4969e7b5de`;
its independent full receipt is `layout-request332-guest-v1-readback-2026-10-25.json`.
The corrected v2 checker requires the exact stage-specific pair and reran all
three variants. The attached probe emitter is unchanged.

## Qualification limits

These scoped host, build and ART checks do not prove that this defect causes
Maps' Attractions loading sheet. [Maps332](maps332.md) subsequently completed a
600-second application replay with both full updated payloads: map display,
Paris search, driving and walking routes, preview advancement and a Trip options
toggle were observed. The prior baseline [Maps331](maps331.md) used Native315
and Framework329, before this layout fix. The application replay does not
establish causality for the preview change or qualify live GPS navigation.
