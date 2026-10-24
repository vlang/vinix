Maps244 was interrupted after onboarding/Skip. Its serial stops at 15:34:30 UTC,
with no `ANDROID-WS-FAIL`, application exit marker, or final `results.json`.
The retained screenshots and logs do not establish a later map workflow or a
completed 900-second observation. Recovery also retains a later screenshot
request that failed with `Connection refused`.

Maps245 continues with the same prepared image. A read-only V preflight recorded
the full image SHA-256 and streamed its FAT runtime archive to compare seven
entries with the staged Maps244 module. The resumed suite trusts that hash and
checks image size/mtime plus staged file hashes; it does not hash the full image
again. APK inspection, QEMU arguments, observation timing and classification are
unchanged. Fifteen helper source, binary, configuration and input-tool identities
were frozen at 16:00:37 UTC before launch at 16:00:53 UTC. The actual QEMU command
and classification self-test are retained under `resume245/`.

The 113-source framework adds ActionProvider and its `framework_classes` hook
relative to Maps243. Native236 (83 sources), APKs and launcher remain unchanged.
Exact source archives, source deltas, seven original pre-run identities, seven
staged runtime hashes and the continuation's preflight identities are retained
separately. Original Maps244 helper/input capture finished during recovery;
those helper hashes are not asserted to be from before its launch.

Maps245 passed Skip, rendered the North America map, searched for Paris, and
opened the Paris place panel with photos and detailed map tiles. Entering
`Versailles, France` as the origin produced route estimates (drive 1 hr 4 min,
23 km; transit 25 min; walk 4 hr 25). Preview opened with detailed street tiles;
next and previous changed the instruction and map view. Back returned to the
Versailles-to-Paris route overview.

The Preview overflow now opens with All traffic, Satellite and Terrain. Selecting
Satellite or Terrain dismisses the menu, and the app remains responsive. The
post-selection screenshots still show vector road tiles, so they do not establish
that those map layers rendered. Icons and labels remain incomplete, and some
bottom details are clipped. Location, live navigation, route accuracy and
performance have not been verified.

Actual workflow observations and timestamps are recorded in `observations.json`.
Maps245 was also interrupted when the headless session ended. Its retained serial
has BEGIN and READY, with its last timestamp at 16:07:33 UTC; the last successful
screenshot at 19:07:34 UTC+3 shows the route overview. There is no application exit
or framework failure marker in that partial serial. No final `results.json`,
harness log or interaction log was written. `interruption245.json` records these
absences and the stopped processes observed at recovery. The configured
900-second observation did not complete, and no final raw classifier or stability
result is inferred from the completed UI actions.

Validate the retained inputs, artifacts and interruption record with:

```sh
/Users/alex/code/v/v_old run tests/android/results/2026-10-23/maps-action-provider/validate.v result
```
