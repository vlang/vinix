# Window frame metrics compatibility

Base source revision: `cf08445429444642c09a1152b8ca49b26b3e82ae`.
Implementation and test revision: `003d6c3ec98dcb5b6c14d1397c02c505c3a772c5`.
Maps286 reached live Paris suggestions, then selecting Paris failed in its
click handler with `NoSuchMethodError` for
`Window.addOnFrameMetricsAvailableListener`. See [input286.md](input286.md)
for the retained replay evidence.

`framework_frame_metrics.v`, registered by `framework_classes.v`, adds the
Window add/remove methods, completes the existing listener interface, and
supplies the missing FrameMetrics class. Subscriptions retain the listener and
Handler per decor View. Removal compares listener identity and removes one
registration, including duplicate registrations; an unknown listener throws
`IllegalArgumentException`. The Window methods preserve decor/listener checks,
and registration validates the Handler, Looper and message queue.
The View helpers use the same plain public declarations as AOSP; they introduce
no synchronization contract.

The display-list backend does not supply compositor frame timings. Registration
therefore emits no callbacks, and `FrameMetrics.getMetric` returns the public
unavailable value `-1`, including for unknown metric IDs. The class includes
metric constants 0–13 and the copy constructor's null check. Retaining
subscriptions on attached software views intentionally differs from AOSP's
software branch, which ignores new registrations: matching add/remove cleanup
must remain usable with this backend. This change does not advertise timing
measurements or establish a Maps latency improvement.

The API contract was checked against primary Android 14 sources:
[Window](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-14.0.0_r1/core/java/android/view/Window.java),
[View](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-14.0.0_r1/core/java/android/view/View.java),
[HardwareRendererObserver](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-14.0.0_r1/graphics/java/android/graphics/HardwareRendererObserver.java),
and [FrameMetrics](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-14.0.0_r1/core/java/android/view/FrameMetrics.java).

`frame-metrics-build.v` and `frame-metrics-framework.v` build an isolated
framework from the sealed282 generators, with only the new generator and its
registration changed. The corrected framework288 build exited 0. Disassembling
the actual JAR confirms the intended class delta is View, Window and the listener,
plus FrameMetrics as the only added class, with none removed. Native286 is reused.

The preliminary framework287 build is retained unchanged at
`/Users/alex/.local/state/vinix/android/frame-metrics287-build-2026-10-25`.
The seven closure/build/disassembly receipts exited 0. Builds used the retained
109a compiler with assertions, explicit VROOT, `-nocache`, `-cc cc` and `-O2`.
The original pinned Java launcher was selected from its Cellar installation
after the Homebrew `opt` link changed; both preparation failures are retained.
Review then caught `synchronized` access flags on the two nonnative View helpers.
Removing those flags matches AOSP and avoids DEX's native-only flag restriction.
The corrected framework288 was built in a fresh directory; preliminary287 is
excluded from final qualification. Reviewing the actual corrected JAR confirms
plain public helpers and valid control flow. Comparing both disassembled JARs
shows only View changed, with exactly the two access flags removed.
The corrected build bundle is retained at
`/Users/alex/.local/state/vinix/android/frame-metrics288-build-2026-10-25`.
Independent read-back verifies all 6,949 files and the exact fileset; a deliberately
wrong manifest pin is rejected. The read-back receipt is the sibling
`frame-metrics288-build-check.json`.

| Artifact | SHA256 |
| --- | --- |
| Preliminary287 build bundle `sha256.json` | `39f63782befd24554ee509501ea0252e27508af694c8792e223b8d041af555ff` |
| Preliminary287 JAR | `7605fc6e815c03330273dd6ea6602608bbf87dabd2c2d85012b5be740fa12b42` |
| Corrected288 build bundle `sha256.json` | `f52a1338edd143717a718e23cb1e2c7d4e3249a87f080fcfe8af8ff0bea2f27d` |
| Corrected288 JAR | `ed5ca2dc9946a5d33d458c85ef808212698cc5076fefa1fb97fd6032a851ebc5` |
| Corrected288 read-back receipt | `e56d734cec68c80b8af786fe7ff71a6bc9cbc9050784365b846fb9740c58cf55` |
| Reused Native286 library | `c46f56d775efef3807e34ece9c8bb5bdb949c47f6db54e59dee02e82cf60019a` |

`frame-metrics-fixture.v` exercises duplicate removal, identity versus `equals`,
window isolation, absent/null removal, null listener/Handler, absent decor,
metric constants/unavailable values/copying, and the callback descriptor.
Its attached Activity registers and removes across pre-draws while requiring
zero synthetic callbacks. `frame-metrics-run.v` runs the same APK and Native286
against framework282 and corrected framework288. Fixture evidence is retained at
`/Users/alex/.local/state/vinix/android/frame-metrics287-fixture-2026-10-25`.
The baseline run fails with the expected `NoSuchMethodError` for Window's
registration method at `MetricsProbe.nullListener`, with no READY marker.
The old-suite receipt and semantic check both exit 0; `startup_failed` is expected
for this baseline. The serial log is
`run-old-guest/bootstrap-fixture/serial.log` within the fixture bundle.
The corrected288 guest completes all four DETACHED, VALUES, SIGNATURE and
ATTACHED PASS markers and BOOTSTRAP-READY exactly once. Its semantic check passes
with no `ANDROID-WS-FAIL`. The reused Maps suite still classifies this small
fixture as `startup_failed`: Native286's Maps-specific transition diagnostic
looks for `bootstrap.Main.bB:Lnge;` and logs a `NoSuchFieldError`. The runtime clears
that diagnostic exception; ATTACHED and READY follow. This classifier limitation
does not invalidate the explicit fixture assertions. Both expected-result
semantic checks pass. The completed 634-file fixture bundle was checked after
sealing; its `sha256.json` is
`d6dd37f7ef69fbe66d8100da066dd2e2b41bfc75850596d4d2d75d8272bc6ca3`.
An independent read-back verifies all 634 files and the exact fileset. Its sibling
`frame-metrics287-fixture-independent-check.json` receipt has SHA256
`99226387b1ca087c4956c4f3565dc5bb3671bd2521c8e5037c66cd69a28ac819`.

`maps287-run.v` prepares a fresh Maps replay with the same Native286 and the
corrected framework288 JAR. Replay evidence is retained at
`/Users/alex/.local/state/vinix/android/maps287-2026-10-25`.
The actual replay passes onboarding and renders map tiles. At 03:58:54 UTC the
runner selected the live Paris suggestion. The retained
`paris-details-ready.png` at 03:59:49 shows the Paris, France card, map boundary
and Directions/Share/Save/More actions. Directions opens origin search. The
`eiffel-suggestions.png` capture at 04:01:21 shows the complete `Eiffel Tower`
input and the matching Avenue Gustave Eiffel, Paris suggestion, selected at
04:01:27. `route-overview.png` at 04:02:02 shows Eiffel Tower → Paris with drive,
transit and walking estimates. `route-preview.png` at 04:02:43 shows Route preview,
“Head toward Pont d'Iéna”, the direction arrow and the map at the bridge.
`route-next.png` at 04:03:26 advances to “750 m Turn left onto Pont de l'Alma”
with changed arrows and map camera. `route-previous.png` at 04:04:14 restores
“Head toward Pont d'Iéna” and the original camera and position arrow.
The full observed UI flow passes: onboarding → map → live Paris search → details
→ Directions → Eiffel Tower origin → route → Preview → Next → Previous.
The frame-metrics linkage failure is resolved for this path. Visible updates
still needed roughly 20–50 seconds of waiting; this run establishes no latency
gain. The observed UI result is separate from the suite's raw classifier.
The 600-second replay completes naturally with launch and runner exit 0
(03:54:16–04:05:53 UTC). Raw results report `window_observed`, backend ready and
native execution observed, with `process_exited=false` and QEMU alive before
capture. `failure_markers` is empty, the serial log has no classifier failure or
APK exit, and no socket entries are omitted from the inventory.
`functional_passed` remains null, so the claim above rests on the
explicit retained UI observations. The completed replay `sha256.json` is
`6988daeab8abad17b6d2a7b326ae5739c15bf56324089a43348217ada9060146`.
Independent verification exits 0 for the exact typed inventory of 2,006 entries;
a deliberately wrong manifest pin is rejected with exit 1.
