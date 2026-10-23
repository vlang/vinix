# BlurMaskFilter enum regression

The identical signed APK fails on framework240 with the exact missing
`BlurMaskFilter.Blur.OUTER` field. On framework241 it checks all four styles,
prints `BOOTSTRAP-BLUR-STYLES-PASS`, reaches `ANDROID-WS-READY`, and remains
alive through the 120-second observation window. All 105 prior distinct
probes pass. Native235 and five other staged runtime files are identical;
the framework changes only `framework_blur_styles.v` and its startup hook.

The probe checks NORMAL/SOLID/OUTER/INNER names, order, ordinals and distinct
singleton identities; reflected final `native_int` values 0–3; typed and
generic Enum `valueOf` identity; fresh `values` arrays and mutation isolation;
and invalid-name/null `valueOf` exceptions. The outer BlurMaskFilter class is
byte-for-byte unchanged. No radius validation, constructor behavior, blur
pixel rendering or Maps route outcome is claimed.

The fixed harness's raw outcome remains `startup_failed`: native235 contains
inherited Maps-specific diagnostics that print and clear missing `nge`/`bB`
errors for this fixture. The validator requires exactly those two markers,
`backend_ready=true`, and `process_exited=false`. The probe assertions and ready
marker pass; the harness outcome is not presented as a clean boot.

Run from the repository root:

```sh
/Users/alex/code/v/v_old -nocache -cc cc run tests/android/results/2026-10-23/blur-styles/validate.v
```

`receipt.json` hashes the raw serial/results, six staged runtime identities,
actual signed APK and framework DEX excerpts, 109/110 exact framework sources,
83 native source files, frozen fixture sources, AOSP enum reference and actual
build helpers. The signed APK hash identifies the binary used for both runs.
The fixture build selected its frozen module with
`-path 'build/android-maps/blur241/source|@vlib|@vmodules'`. `retain.v` rebuilds
the receipt from the original local artifacts when those are present.
