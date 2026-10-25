# Maps283: Paris details and route overview within 420 seconds

On 2026-10-25 UTC, Maps283 completed a natural 420-second observation without
an app fatal marker. Root's retained frames show onboarding Skip, loaded map
tiles, Paris search/details/photos, Eiffel Tower origin selection and an
18-minute drive overview with Preview available. The Preview transition was
not established before the observation ended.

| UTC | Frame | Root's observation |
| --- | --- | --- |
| 01:02:14 | `map-after-skip.png` | Main view with North America tiles and bottom tabs |
| 01:03:15 | `paris-suggestions.png` | Nine readable Paris rows; pin holes and pale gray circular backgrounds visible |
| 01:03:56 | `paris-details-loaded.png` | Paris details, Directions/Share/Save/More and loaded photos; map beige |
| 01:04:56 | `eiffel-suggestions.png` | Nine origin results for Eiffel Tower |
| 01:05:36 | `route-loaded.png` | Eiffel Tower to Paris, loaded streets/river, 18-minute drive and 33-minute transit |
| 01:05:50 | `route-ready.png` | Street map and Preview/Add stops/Share controls; no blue route geometry established |
| 01:05:59 | `application.png` | Final overview controls with beige map after the single Preview click |

UI updates still took tens of seconds; several intermediate frames show the
previous screen. Root used single clicks and did not repeat them for stale
frames. The first onboarding helper expired its 600-second wait without input;
its replacement recognized onboarding and clicked Skip once. A later
`route-preview` capture failed after natural QEMU shutdown, so no successful
Preview capture is claimed. All early frames and failed command streams remain.
One retained timing sample (loop 455) records 23,808 ms in the looper and
5,200 ms rendering, for 29,010 ms total. This supports sluggish responsiveness;
it does not isolate its cause.

The start receipt records 00:57:41 UTC before QEMU launch. The raw observation
records exactly 420 seconds,
backend and native Maps readiness, `process_exited:false` and QEMU alive before
capture. The unchanged classifier reports `window_observed`,
`failure_markers:[]` and `functional_passed:null`. No `NoSuchMethodError`,
`FATAL EXCEPTION`, `APK-SUITE-EXIT` or `ANDROID-WS-FAIL` marker was found.
This is not a general automated functional pass. Preview/Next, blue route
geometry, Restaurants and the granted-location blue/white glyph remain
unvalidated. The lower-right gray control has segmented artwork matching Maps'
`location_not_granted` resource (`res/TF3.xml`), as confirmed by independent
source comparison. Its selected runtime state was not sampled; the artwork
does not itself establish a rendering bug or validate the granted-location
fixture. GPS, compass fidelity, sign-in, voice guidance and endurance beyond
this observation were not established.

The suite ran without stdout/stderr redirection. The supplemental harness log
contains explicitly labelled tool-response excerpts saved after completion,
not a directly captured complete process stream. The raw observation, start
receipt, serial log and interaction command streams are retained separately.
Both the as-collected notes and root's later timestamp clarification are
retained with hashes and revision provenance; the clarified notes were copied
before sealing, without changing raw run evidence.

Preparation changes exactly three files in the 109-file Maps256 runtime:

| Overlay | SHA-256 |
| --- | --- |
| Framework282 JAR | `92b069b1dbb31b08960d00d4f33f84b068a3adf53af9339f2ef3c1a6478f0618` |
| Qualified276 native library | `5fe27a87c179b97121c368f417936ceebb75752c4a4204b937312ee28da531ca` |
| Newly built clean launcher | `406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0` |

The signed Maps256 APKs and original observation classifier remain pinned.
The launcher is a fresh build of maintained source derived from retained
historical source by removing exactly ten diagnostic setters. Its child
arguments and other environment assignments match that source. The retained
framework/native sources, four actual framework/fixture build receipts for
build 282, the sealed native276 reference, clean-launcher build closure and
fresh suite build receipt establish
the three inputs separately. No fresh native build is claimed.

Preparation recorded revision `1ed005eb5f6855ab9cddb87b6f0027ec27db34b7`;
the staging and collector tools are committed at `474a23bcd`, and clean-launcher
tooling at `9b54136ed`. The fresh suite binary is
`e42851131391598e1dccf1590ae0876f358dd514f65f813fcb51829e3dab6dbc`.

The complete 2,810-entry prelaunch check passed at
`/Users/alex/.local/state/vinix/android/maps283-2026-10-25-prelaunch`, manifest
`d1f632b3f0d645aec89dab756e0a52b8a4a30e11a7d8917ffa89fd71faef98ae`.
The adjacent preparation workflow has manifest
`b420d03b76352eb9ec8e97e6d4e23b77e79266e97de72226b5f82f370dc3b136`.
The retained build 282 prelaunch reference has manifest
`2d9a307a57f3ffd5f07170a61cb6fb42361cc65ab260e78c158be2c9b05edefc`.
Its [paired tooltip regression](tooltip282.md) records the separate API checks.
The independent [clean-launcher build](maps-clean-launcher283.md) has manifest
`9e8256b31be97aa97c7bf8b4b353624514ea9cd7d9acfb7f7315d24c26670f10`.

The assertion-enabled frozen collector passed compilation, self-tests and its
expected failing assertion probe. Its exact reviewed source remains unchanged
at handoff. Workflow:
`/Users/alex/.local/state/vinix/android/maps283-collector-workflow-2026-10-25`,
manifest `baf2803152222553361d3f2bc2042b5f7e9337cce57b6fc3ffed4c41626f4ca3`.

The complete retained-bundle check passed with 2,988 entries and exit zero at
`/Users/alex/.local/state/vinix/android/maps283-2026-10-25`, manifest
`643adb9d5c778a1f388e9334aebebd7955d1efb02e29f9e332fcb4d25aebf43a`.
The frozen Maps279 collector rejected the actual third launcher overlay;
a wrong complete-bundle pin was also rejected, both with exit one. Actual
commands, before/after receipts and logs are retained at
`/Users/alex/.local/state/vinix/android/maps283-postrun-2026-10-25`, manifest
`d9d1df986465fcd3e5e7af26735b13fee88dde503768f2873bde3c4fda79859e`.

Reproduce the complete check from the checkout with the retained collector:

```sh
/Users/alex/.local/state/vinix/android/maps283-collector-workflow-2026-10-25/maps-replay-evidence check \
  /Users/alex/.local/state/vinix/android/maps283-2026-10-25 \
  643adb9d5c778a1f388e9334aebebd7955d1efb02e29f9e332fcb4d25aebf43a
```
