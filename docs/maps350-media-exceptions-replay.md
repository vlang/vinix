# Maps350 media exception replay

Maps350 passes onboarding, searches Paris, renders streets and photos, opens
Attractions and Pinky Tour - Paris details, and displays a driving route from
Louvre Museum to Pinky Tour - Paris. The selected route is 21 minutes / 6.2 km;
an alternate route is 24 minutes. Route preview opens and advances to
`120 m / Slight right to stay on Pl. du Carrousel`. These observations come
from actual QMP screenshots, visually reviewed during the run.

The framework fix is `732d7150e6d63b12e551ad1885d7f5185a5aca9d`.
Its [old/new native ART regression](../tests/native-android-ws/media-codec-exceptions349.md)
reproduces the original `hqa.V` verifier failure with framework346 and verifies
both original Maps classes `hqa` and `hwv` with framework349. The same fixture
also checks the three media exception contracts and remains alive for 35 seconds.
This does not establish media decoding, DRM or video playback.

Replay source commits are `084488d78` (deriver), `9c809cdbd` (generators) and
`bd3741de7` (preparation wrapper). The qualified349 JAR is the sole changed
entry among the authenticated335 prelaunch runtime's 109 files. Native332,
diagnostic launcher334, kernel, base boot media, original Maps APK and the
600-second observation/classifier remain unchanged. The JAR overlay is a
separate boot module. Independent review of the Maps347-to-Maps350 generator
diffs found only new labels and qualified349 framework pins.

All artifact paths below are under `/Users/alex/.local/state/vinix/android/`.
The canonical run directory is `maps350-2026-10-25`; screenshots and raw logs
are in `results/attempt350/google-maps/`.

| Visually reviewed screenshot | Observation |
| --- | --- |
| `paris-loaded.png` | Paris streets and two loaded photos |
| `attraction-details.png` | Pinky Tour rating, hours, Eiffel Tower/car photos and booking options |
| `google-maps-running.png` | Loaded Paris map, selected driving route, 21 min / 6.2 km and Preview |
| `route-preview.png` | First route instruction and route map |
| `route-preview-next-recorded.png` | Next instruction and changed map position |

Initial manual input and captures used the pinned `build/android-run` directly;
they have no driver command receipts. From 18:56:42 UTC, input and captures use
the pinned `maps-interact-unique258` driver, whose `interaction.log` records
command boundaries and separate stdout/stderr. `google-maps-running.png` was
captured through that driver at 18:57:31 UTC. No earlier receipts were recreated.

| Qualified input | SHA-256 |
| --- | --- |
| Framework349 manifest | `0700318453dfb6373ea07587c3f42b09fbdb65930dffd35eda0664deddde8f88` |
| Framework349 JAR | `95aabc17c85a5cda0d643dfa5ef9e618955d422d960ffb3bbc2db74c86a9c37d` |
| Original Maps APK | `6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2` |
| Recorded runner | `5ace42c31e1997ef3a8ff0e193fc0f90702c6ae61ce67509814baea1c3ad7405` |
| Generated runner source | `b2d08a2974764b9925d311a7a025fd10eb339fac30c58aa1e48380cce3835d93` |
| Launch pins | `8f015ff9167c4d1d52ef2156062edb2c6bd48b0d7dabe33f4887e8d7f696b038` |
| Prelaunch typed manifest | `dc30058a943aea4babe5451df20eb0a967262a09caf7df8aed0c88917e987a2c` |

Preparation completed with unchanged input pins, 50 clean environment entries
and no forbidden trace/location keys. Complete generation and preparation
readbacks passed 22 and 9 files respectively, independently checked by root.
The recorded runner build pins equal before/after source/compiler closures
(`0bc7ab8110cc770acfd21baa472a187a1533a6fdbde849b1a4457a3ac6863086`),
compiler and C compiler, generated C and command receipts.

The replay wrapper ran from 18:52:43 to 19:03:56 UTC on 2026-10-25, exited 0
and retained unchanged input/program pins with no forbidden environment keys.
The canonical raw result reports `backend_ready`, `launcher_entered` and
`native_maps_observed` true, `observation_elapsed_seconds=600`,
`outcome="window_observed"`, `process_exited=false`,
`qemu_alive_before_capture=true` and no failure markers. `functional_passed`
remains null: the UI observations above were manually exercised and reviewed.
The final automatic `application.png` capture at 19:03:19 UTC still shows
the loaded Paris driving route.

The complete serial has no `VerifyError`, media exception linkage failures or
missing class/method/field/native-link failures. Existing Google Play Services
NullBinder/Chimera/Phenotype warnings and finalizer lock-release warnings remain.
This run establishes the observed search, place details, directions and route
preview behavior; live GPS navigation and video playback remain unqualified.

| Preserved evidence | SHA-256 |
| --- | --- |
| `maps350-2026-10-25/sha256.json` | `ad752e92934ac158478510b93ab867a72c195bf40c4c6b0af7efa903ea1c36f0` |
| `maps350-launch-receipt-2026-10-25/sha256.json` | `f5f3e00da67b80cb56c7bb6ddf41ff4c507f2309e64a2043802e57e42c53757f` |
| `maps350-generation-2026-10-25/sha256.json` | `4fd3b7b6a5a089289d64e7bb8e0b86241ec68764b3b811968f0d2e3cb8c1c9c2` |
| `maps350-prepare-receipt-2026-10-25/sha256.json` | `f62eed6141e0bf3602dd55c4297120e1cd2e28e189e495e09cec14abb566842c` |
| `google-maps-running.png` | `e25ae88c14e0ab9cb32e5387df54f2e2d659f13ecfe21c4dcd1b825985f05cad` |
| Final `application.png` | `0724c7cfda72a91392aa7e5c111fe8fad2bee92d85c973641b29a64b5b985a14` |
| Complete `serial.log` | `d74eb1d7ae2df1b58fc34ddc778553af8fa9959087d053cca3dc6d145ce2d455` |

Root and an independent reviewer completed the canonical typed readback of all
41,954 entries. Root also compared the live and collected primary/final PNGs
and serial hashes; each pair matches. The launch envelope's complete readback
passes all 9 files. Root verification output is preserved outside the sealed
bundles as `maps350-root-readback-2026-10-25.log` and
`maps350-launch-root-readback-2026-10-25.json`.

The retained runner can repeat the complete canonical verification:

```sh
build/android-maps/maps350-run-recorded verify ad752e92934ac158478510b93ab867a72c195bf40c4c6b0af7efa903ea1c36f0
```
