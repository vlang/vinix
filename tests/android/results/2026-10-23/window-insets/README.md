# WindowInsets Builder and value regression

The same signed startup APK runs on framework236 and framework239 with identical native235 binaries. The first operation in the new probe allocates `WindowInsets.Builder`, matching Maps' missing-class failure. All prior probes remain enabled.

The probe checks all five legacy setters/getters and eight scalar edges, typed component maxima, visibility, copies and build isolation, equality/hash, consume and replacement behavior, both inset overloads, zero clamping and negative arguments. It follows the retained AOSP source for gesture-only consumed-map discard and the mixed IME maximum edge case. The expanded cases preserve negative single-type values and negative component maxima, ignore absent selected entries, and include type512 system overlays in current/stable legacy values and all scalar edges.

Baseline236 fails at the first Builder allocation. Fixed239 prints `BOOTSTRAP-WINDOW-INSETS-PASS` and `ANDROID-WS-READY`, retaining all previous distinct startup PASS markers. Exact source comparison includes the Insets implementation, startup changes and the independently verified default-off lookup logging gate from [lookup-trace](../lookup-trace/README.md). The original narrower framework238 pair is preserved separately in [window-insets-238](../window-insets-238/README.md); its earlier pass did not cover signed values or overlays.

The receipt retains actual DEX, exact framework/fixture/native source archives, staged runtime hashes, raw results, serial logs, screenshots, AOSP reference and build helpers. Run from the repository root:

```sh
/Users/alex/code/v/v_old -nocache -cc cc run tests/android/results/2026-10-23/window-insets/validate.v
```

The raw fixed harness result remains `startup_failed`: native235's inherited Maps diagnostic prints and clears a missing `nge` field/class while inspecting the fixture's Main. Validation requires exactly those two diagnostic markers, a ready backend, no process exit and no application assertion or `ANDROID-WS-FAIL`. It preserves the raw result. This fixture does not establish a Maps functional outcome.
