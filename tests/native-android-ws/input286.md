# Input before drawing laid-out windows

Commit `e35062e62` dispatches queued input after the main Looper and before
frame callbacks/drawing when the published activity and dialog trees are
attached, have no pending layout, and match their expected dimensions. Input
can invalidate the frame drawn in that same iteration. First frames and changed
trees retain the layout-before-hit-testing path. Each iteration consumes at
most one input batch. Looper completion, input EOF and pending exceptions stop
the iteration before further frame work.

`input-frame-check.v` extracts the actual production loop and both readiness
helpers, then runs them with controlled JNI, layout, input and rendering stubs.
The fixed host build and run exited 0, emitting all 13 PASS markers across 28
modeled cases. The baseline built successfully and exited 1 at the intended
assertion: the frame presented version `[0]`, while queued input required `[1]`.

Coverage includes same-iteration presentation from dirty and idle windows,
first/replaced/dialog layout, unattached activity/dialog trees, all four
activity/dialog dimension mismatches, canceled first rendering, exceptions at
every readiness lookup and input dispatch, render exceptions, EOF, Looper
activity completion, balanced local frames and one input batch per iteration.
The simulated 500 ms drawing cost establishes ordering; it is not a measured
Maps response time.

The sealed host bundle is
`/Users/alex/.local/state/vinix/android/input-frame-host-2026-10-25`.
Independent readback verified all 35 manifest entries, the fixed PASS output
and the expected baseline assertion. Both earlier runs remain retained. The
bundle includes final checker source, both outer checker executables, generated
host programs, runtime snapshots, compiler executable, logs and receipts. Its
scope records that the first outer checker source was superseded and that the
host bundle does not retain the full V library/toolchain closure.

`input-frame-build.v` generated and cross-compiled the AArch64 native library
successfully. Its native source delta against qualified284 is only `runtime.v`.
The generator V source closure equals qualified284; consumed source and tool
closures were checked before and after compilation. Existing timing probes are
retained, with input timing around the branch that actually dispatches input.
Removing those probes reproduces the reviewed runtime exactly.

The complete native build evidence is retained at
`/Users/alex/.local/state/vinix/android/input286-build-2026-10-25`, including
the source delta, exact native sources, generated C, output library, consumed
inputs, compiler/closure snapshots, build argv, exits and logs. Builds use the
private retained109a compiler, explicit `VROOT`, `-nocache`, `-cc cc`,
`-cflags -O2` and assertions. This retains the consumed build inputs without
claiming a complete historical default toolchain closure.

| Artifact | SHA256 |
| --- | --- |
| Host bundle `sha256.json` | `224ec341a66e2ff4b0a747d33ab8765631165b838ae8beef6097028a75a8b9c7` |
| Native build `sha256.json` | `d7ce481cec4c1c687d6647ddded15f3dc61393ce91678767c2681b04cf9019f8` |
| Reviewed runtime | `84bc092d89e3baf6848ae3d4e650a0fdbcbba57054bb67d3ba51cb236b441bf5` |
| Host checker source | `62fc16f682582f0371222af26121714fc6ee94697036f9f7f8f0f8178bad988f` |
| Native library | `c46f56d775efef3807e34ece9c8bb5bdb949c47f6db54e59dee02e82cf60019a` |
| Retained V compiler | `109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e` |

## Maps286 replay

The fresh replay visibly reached onboarding, Skip, rendered map tiles and live
Paris suggestions. Selecting Paris then failed with
`NoSuchMethodError: Window.addOnFrameMetricsAvailableListener` from Maps' click
handler. The native runtime reported `ANDROID-WS-FAIL input` and the app exited
1. The unchanged classifier records `startup_failed`, with
`functional_passed: null`, after 121 seconds; suite exit 0 records harness
completion. Place details and route Preview were not reached in this run.

`maps286-run.v` retains preparation, compilation, launch and complete results.
Only the native library changes among 109 regular runtime files; the framework,
APKs and classifier remain unchanged. Staged runtime archive readback matched
its producer. The classifier self-test and launch gate passed; wrong launch and
completed-manifest pins were rejected. Independent completed readback passed
for all 1,904 typed entries.

The complete bundle is
`/Users/alex/.local/state/vinix/android/maps286-2026-10-25`, manifest SHA256
`a0fad1b4ad7e2eb27f1816cbeea570a7e7d93080256e189bc0d3b06a8007caa0`.
The failed replay remains evidence for the missing framework API. Neither this
run nor the modeled ordering check establishes a Maps latency improvement.
