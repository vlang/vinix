# Canvas six-argument saveLayer regression

The identical signed APK fails on framework241 with the exact missing
`Canvas.saveLayer(float, float, float, float, Paint, int)` overload. On
framework242 it prints `BOOTSTRAP-CANVAS-SAVE-FLAGS-PASS`, reaches
`ANDROID-WS-READY`, and remains alive through the 120-second observation
window. All 106 prior distinct probes pass. Native235 and five other staged
runtime files are identical; the framework changes only
`framework_canvas_save_flags.v` and its startup hook.

A subclass overriding the five-argument method verifies virtual forwarding,
unchanged raw float bits (including signed zero and a NaN payload), Paint and
null identity, and three returned values. Flags 0, 31 and -1 document the
wrapper's current ignored-flags behavior, rather than Android flag validation.
All drawing tests use flags 31. They check nested save counts, returned counts,
transform and clip restoration, and 192 exact pixels across bitmap Canvas,
Picture recording/playback and inherited RecordingCanvas playback. This does
not establish offscreen compositing, layer Paint application or blur rendering.

The fixed harness's raw outcome remains `startup_failed`: native235 contains
inherited Maps-specific diagnostics that print and clear missing `nge`/`bB`
errors for this fixture. The validator requires exactly those two markers,
`backend_ready=true`, and `process_exited=false`. The probe assertions and ready
marker pass; the harness outcome is not presented as a clean boot.

Run from the repository root:

```sh
/Users/alex/code/v/v_old -nocache -cc cc run tests/android/results/2026-10-23/canvas-save-flags/validate.v
```

`receipt.json` hashes the raw serial/results, six staged runtime identities,
actual signed APK and framework DEX excerpts (including recorded command 54),
110/111 exact framework sources, 83 native source files, frozen fixture sources
and actual build helpers. The signed APK hash identifies the binary used for
both runs. The fixture build selected its frozen module with
`-path 'build/android-maps/canvas242/source|@vlib|@vmodules'`. `retain.v` rebuilds
the receipt from the original local artifacts when those are present.
