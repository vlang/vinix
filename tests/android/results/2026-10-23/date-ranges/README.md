# DateUtils range formatter regression

The identical signed APK fails on framework239 with the exact missing full
`DateUtils.formatDateRange(Context, Formatter, long, long, int, String)` API.
On framework240 it passes literal numerical/date range checks, prints
`BOOTSTRAP-DATE-RANGES-PASS`, reaches `ANDROID-WS-READY`, and remains alive
through the 120-second observation window. All 104 prior distinct probes pass.
Native235 and five other staged runtime files are identical across both runs;
the framework changes only `framework_date_ranges.v` and its startup hook.

The probe checks formatter identity and repeated appends to a percent-containing
prefix; explicit 12/24-hour flags and the current framework's 24-hour preference;
UTC, null/default and explicit non-UTC zones; point and multi-day ranges; String
wrapper agreement; closed formatter errors and the original IOException cause.
It uses a US default locale with a French Formatter to distinguish the ICU
default locale from the formatter locale. It restores the general locale, both
locale categories and the timezone on success and failure. Whitespace and the
range separator are normalized; calendar values and times are independently
specified. UTC-flag precedence follows the retained actual libcore bytecode.

The fixed harness's raw outcome remains `startup_failed`: native235 contains
inherited Maps-specific diagnostics that print and clear missing `nge`/`bB`
errors for this fixture. The validator requires exactly those two markers,
`backend_ready=true`, and `process_exited=false`. The probe assertions and ready
marker pass; the harness outcome is not presented as a clean boot. This proof
does not claim a Maps Directions outcome.

Run from the repository root:

```sh
/Users/alex/code/v/v_old -nocache -cc cc run tests/android/results/2026-10-23/date-ranges/validate.v
```

`receipt.json` hashes all retained evidence, including raw serial and results,
six staged runtime identities, actual signed APK and framework DEX excerpts,
the 108/109 framework source snapshots, all 83 native source files, complete
frozen fixture sources, the AOSP wrapper reference and actual build helpers.
The signed APK hash identifies the exact binary used for both runs. `retain.v`
rebuilds the receipt from the original local artifacts when those are present.
