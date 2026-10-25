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

## Qualification limits

The updated native library has not been built, the generated regression has not
run in an ART guest, and Maps332 has not run. These source/host checks do not
prove that this defect causes Maps' Attractions loading sheet or that the
Maps route flow succeeds. The latest qualified Maps screenshot and application
observations remain those recorded in [maps327.md](maps327.md).
