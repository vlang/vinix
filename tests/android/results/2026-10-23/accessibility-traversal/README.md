The same signed APK runs on framework234 and framework235 with the identical
native233 library. It checks the View accessibility traversal IDs across all
four constructors, default NO_ID values, independent before/after and per-view
state, repeated assignments, replacement/reset, unresolved integer IDs, and
inflation of real aapt-compiled XML attributes.

This APK derives from the frozen startup fixture and excludes the separate
InterpolatorProbe invocation, whose native path precision regression is retained
under `../interpolators`. The original interpolator APK is unchanged. All other
startup checks remain enabled. This focused regression does not establish Maps
functional behavior; raw suite outcomes and inherited diagnostic failures are
retained with the logs.

The fixed run prints the traversal PASS marker, all prior startup probe markers
and READY, and the app stays alive. The harness still labels it `startup_failed`
because native233 contains an inherited Maps-only diagnostic that prints and
clears a missing `nge`/`bB` field error against the fixture Main class. Its two
exact failure markers are retained; there is no application `ANDROID-WS-FAIL`.

The receipt includes the exact APK/runtime identities, both complete framework
source archives, the frozen fixture sources, actual generated DEX, compiled XML
dump, configurations, build helpers and logs. Validate from the repository root:

```
/Users/alex/code/v/v_old -nocache -cc cc run tests/android/results/2026-10-23/accessibility-traversal/validate.v
```
