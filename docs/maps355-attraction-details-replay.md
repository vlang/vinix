# Maps355 attraction details replay

Maps355 passes onboarding, searches Paris, renders the city map and opens
Oasis d'Aboukir from Attractions. The details show 4.6 stars, 98 reviews,
the tourist attraction category, accessibility icon and 24-hour opening.
The photo tiles remain pale placeholders. Clicking a tile, Photos and
Directions does not visibly leave that page before final collection.
Walking routes, transit and a separate photo viewer are not established.

This is a fresh replay of the qualified runtime used by
[Maps354](maps354-screen-reader-focus-replay.md). Native351, Framework353,
Launcher334, the original Maps APK, all runtime entries, base boot members,
the 600-second observation and classifier are unchanged. The earlier driving
route and route-preview evidence remains specific to Maps354.

The onboarding helper initially clicks to the right of the visible Skip label.
A manual click at `524,134` advances to the map. Commit `29c72fbab` updates
`tests/native-android-ws/maps-interact.v` to that label centre. The revised
helper compiles with V and its usage smoke check returns the expected exit 2.
The pinned helper used by this replay is unchanged; the corrected helper has
not been substituted into the recorded run.

All artifact paths below are under `/Users/alex/.local/state/vinix/android/`.
The complete Native351 and Framework353 builds and their qualifications are
retained at the paths recorded in the Maps354 report. The input JSON is
`maps355-pins-2026-10-25.json`; generated source is
`maps355-generation-2026-10-25/maps355-run.v`.

| Input or gate | SHA-256 |
| --- | --- |
| Input JSON | `52ed4cdb4458fc93fec8375511b9d9f973dacbbfc4fdcd50f0aaeaab1f494009` |
| Generated runner source | `6d26eb4727c43a3d4bd6f443628e48a7f3dadac0470a3aef897d7cf327dad786` |
| Recorded runner | `f57d558a9809448a569ca0caebb8dca779dd3e59acfce0ccd6826a84be3bfbad` |
| Prepared launch pins | `127d37b8d6dbad683032eea4347205749e0334fbf677db4ba19fd89b23eefbbf` |
| Prelaunch typed manifest | `7f4f8ca0888d6589fca422c987135f62bec777d147f6bf08168130f4742a98f1` |
| Independent prelaunch receipt | `ffd5b0d4747f49d686b1df88530b44a7d164dbb604fbe3a20e3954da03bc7df2` |

Root and owner complete readbacks pass the 22-file generation bundle and
both 9-file preparation/check receipts. Independent prelaunch review verifies
the complete typed trees, 109 runtime files, modes and links, exact two-member
overlay, five base boot members and external APK inputs. Preparation and check
record four environment entries, no forbidden keys, unchanged pins and exit 0.

| Preserved gate bundle | Manifest SHA-256 |
| --- | --- |
| `maps355-generation-2026-10-25/sha256.json` | `a78811541ca6c0b7c5eb23cdd812224bba68eea8da1f2962e4c50aa60127997e` |
| `maps355-preparation-receipt-2026-10-25/sha256.json` | `7912c8bb94343ed40cd4430e445de7e8710ea70ca29a90a24708d631baa778d1` |
| `maps355-check-receipt-2026-10-25/sha256.json` | `19bbae989dae7f8a65e27c4399925d2536b23365114a50acb5fdb20443a255c2` |

## Captured behavior

The interaction log retains each input/capture command and its unique stdout
and stderr files. The pinned helper is `maps-interact-unique258`, SHA-256
`abd2dfbb01fddc83ffffae481b5d1fcab35b9ebd279f3f47abae237b00134208`.
All manual commands finish by 21:49:24 UTC on 2026-10-25, before collection.
Screenshots below were visually reviewed. An input sent before the search
field attached was lost; the later focused input successfully searches Paris.

| Screenshot | Capture time (UTC) | Observation |
| --- | --- | --- |
| `onboarding.png` | 21:42:39 | Visible Skip label centred near 524,134 |
| `settled-home.png` | 21:43:44 | Map and search bar after manual Skip click |
| `search-result.png` | 21:46:41 | Paris suggestions, first result France |
| `paris-map.png` | 21:47:01 | Paris street map and category chips |
| `attraction-details.png` | 21:48:13 | Oasis details with photo placeholders |
| `photos-selected.png` | 21:48:55 | Details remain visible after photo/tab clicks |
| `google-maps-running.png` | 21:49:24 | Details remain after Directions click |
| `application.png` | 21:50:56 | Automatic final capture still shows details |

The complete serial records continued rendering through approximately 601
seconds of native runtime, without a VM-exit, missing-method, OOM or
segmentation-fault marker. Google Play Services finalizer exceptions report
`Lock wasn't released correctly`; Maps survives those exceptions. Continued
rendering does not prove the page handles input correctly.
The last thread sample precedes the details interaction: the existing
diagnostic worker takes ten samples at 30-second intervals. Transition queue
samples are also capped. The retained trace therefore cannot distinguish
later input interception, pending work or another cause of the missing response.

## Final observation

The raw result records `backend_ready`, `launcher_entered` and
`native_maps_observed` true, `observation_elapsed_seconds=600`,
`outcome="window_observed"`, `process_exited=false`,
`qemu_alive_before_capture=true` and `failure_markers=[]`.
`functional_passed=null` remains unchanged. The final PNG establishes that
Maps remains visible; the photo viewer and route-mode checks remain incomplete.

The run wrapper records 21:37:17–21:55:15 UTC, exit 0, four environment
entries, no forbidden keys and unchanged input pins. Root and independent
canonical readbacks both exit 0 with all 64,464 typed entries checked; the
manifest remains unchanged. The nine-file run receipt also passes complete
readback. Adjacent verification logs are
`maps355-root-canonical-readback-2026-10-25.log`,
`maps355-peer-canonical-readback-2026-10-25.log` and
`maps355-run-root-readback-2026-10-25.json`.

| Final evidence | SHA-256 |
| --- | --- |
| `maps355-2026-10-25/sha256.json` | `f310a86f1414760a33cec66602165af98211ee4b2176f2e4b7f54091f1bc5529` |
| `maps355-run-receipt-2026-10-25/sha256.json` | `bae74cd56745248ec69c57ad5425c4eee3ee6e2096c4526af3a037e4eec1ec98` |
| `paris-map.png` | `53e3275ebdec49df5e61c5343d0f8e7b66a8837be846f8b3230cc75e27368206` |
| `application.png` | `a03f23555d5b43f6091be3a0c001225c8aa59b2c38fd87c79995bc82bae93325` |
| `serial.log` | `7875bcd32cbb6096014ce702e5f504582bd5a1a70795b1dacc2dfa600e34ba8c` |
| `interaction.log` | `a7ef4ab265d6bf2ec7c0f527f4442e20e81dc4383d31d50fa5e229bcdaf94893` |

The four individual artifacts are under
`maps355-2026-10-25/results/attempt355/google-maps/` and compare byte-for-byte
with the live result directory. Repeat the complete typed readback with
`build/android-maps/maps355-run-recorded verify f310a86f1414760a33cec66602165af98211ee4b2176f2e4b7f54091f1bc5529`.
