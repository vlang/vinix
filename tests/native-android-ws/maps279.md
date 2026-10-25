# Maps279: Skip and Paris suggestions, then a tooltip API crash

On 2026-10-24 UTC, Google Maps 26.42.01.997557324 completed onboarding Skip
and displayed nine readable Paris suggestions on framework278. It then exited
with a main-looper `NoSuchMethodError` for `View.getTooltipText()` through
Material `ExtendedFloatingActionButton.setText`, followed by
`APK-SUITE-EXIT id=google-maps code=1`. This run predates the tooltip API fix280.

Root-authored review of the retained frames records:

| UTC | Frame | Observation |
| --- | --- | --- |
| 23:32:15 | `after-auto-skip.png` | Main view, search bar and bottom navigation; map area beige |
| 23:33:11 | `search-retry.png` | Paris text and nine readable suggestions |
| 23:33:33 / 23:33:46 | `paris-details.png` / `paris-details-retry.png` | Suggestions still presented after two selection clicks |
| 23:34:17 | `paris-selection-wait.png` | Restaurants search/chips and blank results |

Serial records a 26,746 ms frame, including 16,606 ms of looper work.
Delayed presentation plausibly let the repeated selection reach the Restaurants
chip after the first selection advanced logical state; no intervening Paris
details frame was captured, so that explanation is an inference. These records
do not establish a stale-coordinate cause or kernel input defect. Paris detail
rendering, routes, Preview, Next and the location glyph in the real Maps UI
were not validated.

The configured observation was 420 seconds; the recorded window ended at 280
seconds with the app process exited. Backend readiness and native Maps were
observed, `process_exited` was true, and QEMU was alive before final capture.
The original classifier remains unchanged and reports `startup_failed` with
`functional_passed: null`, preserving
both the existing gRPC markers and this additional fatal tooltip exception.
No manual VM termination preceded the app exit.

Preparation recorded revision `dc29d5d1d1598a5c2907c4eb0ec219a50b682c58`.
The signed Maps256 APKs and 109-file runtime base are unchanged except for the
paired278 framework JAR and qualified276 native library. The archive retains
their source snapshots, four actual278 framework/fixture build receipts,
references to the independently sealed276 native qualification, and the fresh
suite build and launch receipts. No fresh native build is claimed.

| Input | SHA-256 |
| --- | --- |
| Framework JAR | `a1b839c77a575a40ddab8d6e264e92c9abcc9de54ae6c3dcefcc0e725c938eba` |
| Native library | `5fe27a87c179b97121c368f417936ceebb75752c4a4204b937312ee28da531ca` |
| Signed Maps APK | `6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2` |

The independent 2,530-entry prelaunch check passed at
`/Users/alex/.local/state/vinix/android/maps279-2026-10-25-prelaunch`, manifest
`83b93892776ae62f6fa75d60dba935326d183574c601683dd1e11fa0f0a12ed3`.
The completed bundle is
`/Users/alex/.local/state/vinix/android/maps279-2026-10-25`, manifest
`901b7553f117b368fc6b992ea9c9190589f86e0937568787215a054b392fd374`.
It retains raw results, all 15 PNGs, serial bytes and gzip,
packet capture, command streams, supplemental logs, root visual notes and
independent prelaunch/postrun media. Seal and the complete 2,680-entry check
passed. The prior collector and wrong-pin negative checks both rejected with
exit 1 at their expected gates.

The assertion-enabled collector source, binary, build/self-test receipts and
prior collector provenance are retained in `audit/`. Commit `511d8f992` adds
only the exact run279/build278/280-second failed case, with both serial and
result-array exception/exit markers required. The prior frozen collector's
rejection and wrong-pin negative have separate before/done receipts at
`/Users/alex/.local/state/vinix/android/maps279-postrun-2026-10-25`, manifest
`d0b86277d807a6fe3b30e2a8b66b90b0e4e6ed92a9958cd95ad748a6fc69df2e`.
The frozen collector workflow has manifest
`e958ae2fad566e5f1742f2464876b043bf3e7a5713c9db2e13c7318daf4864d2`.
Historical bundles and frozen checkers remain unchanged.

Recheck with the retained frozen collector:

```sh
/Users/alex/.local/state/vinix/android/maps279-collector-workflow-2026-10-25/maps-replay-evidence check /Users/alex/.local/state/vinix/android/maps279-2026-10-25 901b7553f117b368fc6b992ea9c9190589f86e0937568787215a054b392fd374
```
