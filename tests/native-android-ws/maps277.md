# Maps277: Paris search and missing tooltip API

On 2026-10-24 UTC, Maps277 reached the main map through onboarding Skip,
returned nine Paris search suggestions, and loaded Paris streets, boundary,
actions and photos. It then exited while loading restaurant results because
`View.getTooltipText()Ljava/lang/CharSequence;` was missing. The call came from
Material's `ExtendedFloatingActionButton.A`/`setText` during results layout.

This run uses the old274 framework with the qualified276 native rectangle
correction. It does not validate the newer278 vector fill-rule change.

| UTC | Frame | Observation |
| --- | --- | --- |
| 23:10:19 | `after-skip-retry` | Main world map, search bar and bottom navigation |
| 23:10:56 | `paris-suggestions-loaded` | Nine readable pins; Paris, France first |
| 23:13:17 | `paris-result-retry` | Paris streets, boundary, actions and photos |
| 23:13:28 | `directions` | Restaurants search and blank results area |

The last frame's name records the intended action, not its outcome. The
intended Directions action resulted in the Restaurants screen.
Several initial clicks or text inputs also did not produce their intended
screen; all early frames and unique command streams remain. Routing, Preview,
Next and location-glyph correctness were not established in 277. Input ordering
was reviewed but no cause was proved or input code changed. A later 279 trace
demonstrated multi-second input, looper and rendering phases, which can leave
the displayed screen behind the application's current state.

The raw run records `backend_ready:true`, `native_maps_observed:true`,
`process_exited:true`, `observation_elapsed_seconds:262` and QEMU alive before
capture. It ended without manual termination before the configured 420 seconds.
`ANDROID-WS-FAIL main looper`, the tooltip `NoSuchMethodError`, and
`APK-SUITE-EXIT ... code=1` remain in the serial log and failure markers.
The unchanged classifier reports `startup_failed`/`functional_passed:null`.

The recorded prelaunch check passed with manifest
`769def18f13251d41878d327288e3569ebec75ca90e03305aa7c0e5a2ec14cb5`
at `/Users/alex/.local/state/vinix/android/maps277-2026-10-25-retry1-prelaunch`.
Preparation receipts are in the adjacent `-retry1-preparation` directory,
manifest `3e4566aa8e172466030f05b0435baeb0a1dcdf22216876f036e54fe27d617683`.
The earlier interrupted, unlaunched preparation remains separately retained.

The complete failed-run bundle is
`/Users/alex/.local/state/vinix/android/maps277-2026-10-25`, manifest
`e3ade26f6a35b07d5b87e8a743cff07b8987951334b8cfddaa8971fded04d8b3`.
Collector commit `ad3a565ff` adds an explicit failure case requiring this run's
262-second observation, tooltip exception and process exit. It leaves the
historical positive-run requirements intact. The preserved older collector
rejects this bundle at its original 420-second assertion.

The complete 437-entry check passed; the wrong-pin check and older collector
both rejected with exit 1. Actual before/done receipts and logs are in
`/Users/alex/.local/state/vinix/android/maps277-postrun-2026-10-25`, manifest
`f3201ab43fc9df3e69ce496b9a35c73e0a37a23f6034a6809fca4e6deff014f6`.
The frozen collector workflow has manifest
`7a5d794e2e44062e03cd0e9d7d6070e16dc393e05014d1226a5dcc93fb8eeef8`.

Recheck the original bundle with its frozen collector:

```sh
/Users/alex/.local/state/vinix/android/maps277-collector-workflow-2026-10-25/maps-replay-evidence check /Users/alex/.local/state/vinix/android/maps277-2026-10-25 e3ade26f6a35b07d5b87e8a743cff07b8987951334b8cfddaa8971fded04d8b3
```
