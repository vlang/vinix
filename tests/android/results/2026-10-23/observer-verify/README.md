# Detached view observers

The native framework now keeps a detached view's floating `ViewTreeObserver`
until attachment and transfers its draw listeners into the window observer.
The attachment token gates window observer lookup because the native backend
already knows the activity window before individual views attach.

The final comparison uses the same signed fixture APK and native204 library:

| Run | Framework | Result |
| --- | --- | --- |
| `baseline2` | framework211 | Fails: `global layout must see attached, laid-out views` |
| `fixed2` | framework217-observer2 | Two traversal probes pass; all 92 earlier fixture pass markers remain |

Each probe registers global-layout, pre-draw and draw listeners before
attachment, checks repeated observer identity and liveness, then checks that
attachment kills the floating observer and exposes the parent's observer.
The two probes exercise merging into both empty and existing draw listener
lists. They also check layout before pre-draw, cancellation of the first frame,
draw callback ordering and a second frame requested by invalidation. The fixed
serial log reports native WS with GTK/X11 absent and no assertion or WS failure.

The earlier `baseline` and `fixed` exploratory runs use a separate one-probe
APK. The first observer fix exposed the missing draw-listener merge; its
`view draw ran before observer or despite cancellation` failure is retained.
Their artifact hashes are separate from the final comparison in `receipt.json`.

`validation.log` records the assertions in `validate.v`. The receipt includes
source and artifact hashes; the final runs also retain hashes of the actual
staged framework, native library and launchers. Generated fixture and framework
Smali, the framework manifest, build logs, runner, harness, launcher and final
configurations are retained. Large APK/runtime/VM images stay under
`build/android-maps`; `run.v` documents the private VM setup and guest commands.

This verifies the framework regression in the native guest. It does not establish
that Google Maps has advanced beyond onboarding.
