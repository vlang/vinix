# Maps352 text size replay

Maps352 passes onboarding, searches Paris, and renders streets and photos.
Attractions shows a `Tunnel des Tuileries` result. Opening that result crashes
Maps with `NoSuchMethodError: View.setScreenReaderFocusable(Z)V`. The retained
screenshots show these stages and the final `The Android APK has exited.` screen.

The production fix is `3ec341752382f5cdfd2138d8b606e9b47836df18`.
Its [old/new native ART qualification](../tests/native-android-ws/text-size351.md)
checks SP dispatch, all six size units, retained Paint/native pixel agreement,
measurement growth, layout/invalidation, exposed-Paint repair, five widget
subclasses and compiled XML dimensions. Maps352 replays that qualified native SO
and framework JAR against the authenticated
[Maps350 runtime](maps350-media-exceptions-replay.md).

Reusable replay generation is committed as `c14368bd4`. Its historical no-argument
mode remains byte-identical to the recorded Maps350 source, verified by the
generator self-test. The new `replay NUMBER PINS_JSON PINS_SHA` mode accepts exact
complete native/framework build pins, retains both replacement builds and the
complete baseline builds, and preserves historical qualification checks.
New generator build/readback inventories include hidden entries and reject
symlinks, nonregular entries and directory-read failures. Independent source
review found no remaining issues.

Maps352 changes exactly the native SO and framework JAR among the 109 runtime
files; the remaining 107 entries match Maps350. The diagnostic launcher334,
original Maps APK, identity256, 600-second observation and classifier are
unchanged. The five Maps350 base boot members (`vinix`, `initramfs.tar`,
`qemu-runtime.tar`, `maps335-diagnostics.tar`, `maps350-diagnostics.tar`) are
unchanged. A final boot module contains exactly the replacement SO and JAR.
Generation retains the existing 1536 MiB free-space policy.

All artifact paths below are under `/Users/alex/.local/state/vinix/android/`.
The original complete framework351 bundle is `text-size351-2026-10-25`.
The receipt wrapper requires the canonical framework-build suffix, so a fresh
complete APFS clone is retained as `text-size351-framework-build-2026-10-25`.
Both complete readbacks passed all 10,336 files against the same manifest;
the original is unchanged. Clone provenance and both readback hashes are in
`maps352-framework-clone-provenance-2026-10-25.json`.

| Qualified input or executable | SHA-256 |
| --- | --- |
| Native351 manifest | `eb0dfe0dd87ea7f5972bddd06ae4c0c45ba8b9e5ad56a39c074142847f4bccd9` |
| Native351 SO | `d3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1` |
| Framework351 manifest | `c11c55d6204acc7af998e5e52fcc8c66e8af698b61d01928483005f59fd47654` |
| Framework351 JAR | `91c5c7da4f3460fa899ee06134fa1e380643eb176ce3f2fe887769f113fd5428` |
| Authenticated Maps350 runner source | `b2d08a2974764b9925d311a7a025fd10eb339fac30c58aa1e48380cce3835d93` |
| Authenticated Maps350 prelaunch manifest | `dc30058a943aea4babe5451df20eb0a967262a09caf7df8aed0c88917e987a2c` |
| Original Maps APK | `6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2` |
| Reusable generator source | `5a0fc62f94bd28b88f19b3116c4b5ad0776fd333a7cc1ca2f605ef0fca6c79db` |
| Recorded reusable generator | `8015d46041e305e5b381837ebd7cf9658978ad2642a2792f4be2aa8b1b218d31` |
| Generated Maps352 runner source | `11b78fd88907583aea3e3ca634f976b15d5f1c018402e3854da11964c83da627` |
| Recorded Maps352 runner | `cc67be9549b68490ec844ee22f6cf5728ff3e5dc90853364c9b08a1689851ff2` |
| Replacement input pins | `2086ff83bb145731e1d9a91809d733c2931063a376084daaa54e2bd9b236ba86` |
| Prepared launch pins | `71fab541215181be4457817dae61259def31dc559f37b5f3768e96a95303a4d5` |
| Prelaunch typed manifest | `84dd8e0ae4aef6e655760606fce8bd909892d3fc1cfcb752a58d7e88ee7c53f5` |

The complete generator build freezes the source/compiler closure, compiler and
C compiler identities, generated C, commands and receipts. The generated runner
build retains its complete generation inputs and equivalent build evidence.
Preparation ran through the unchanged recorded receipt332 wrapper, exited 0,
retained the input/program pins and recorded 50 clean environment entries with
no forbidden trace/location keys. Complete generator-build, generation and
preparation readbacks passed 293, 22 and 9 files respectively; root independently
repeated all three. The separate recorded launch gate also passed its complete
9-file receipt readback. Independent prelaunch review compared both complete
typed trees and streamed both FAT images, confirming the 109-file runtime,
two replacements, exact overlay, unchanged base boot members, APK inputs and
600-second classifier. Its adjacent receipt is
`maps352-prelaunch-peer-review-2026-10-25.json`, SHA-256
`9597eca1e2c00b703c9ab6be19a85e3c32979dc0c4dd0842e3ea158ce78a888f`.

| Preserved evidence | Manifest SHA-256 |
| --- | --- |
| `maps352-generator-build-r2-2026-10-25/sha256.json` | `ab363ce2f9e815519bda5cd5b761ae397738e68ac5e0aeeebd7e207c113825ad` |
| `maps352-generation-2026-10-25/sha256.json` | `8eab224599c074591ed367477e1e7630d68b7eca6cc9e4975b6376062f39ae09` |
| `maps352-preparation-receipt-2026-10-25/sha256.json` | `e38a6cfa2561613f910e9c77752a0c3cbea59422ad3f9a5df0d1f8cde3934f57` |
| `maps352-check-receipt-2026-10-25/sha256.json` | `32d4f39aab1af46378db40da0ecd3c64b4f79bafab03cae1a49c5e24dcf10b8f` |
| `maps352-run-receipt-2026-10-25/sha256.json` | `cb947930d5d1fd2dab4c9dbfd3bf453c4308c0cbf6089a96ac10ba990147220c` |
| `maps352-2026-10-25/sha256.json` | `e39f99459a6ee90b8a0d8f9602b3a9719e70f68cdc3589b46dd183053e7f6fda` |
| `maps352-postrun-interactions-r3-2026-10-25/sha256.json` | `85f2e98414e8961335d0409c790c2904a0bfff9992d86caf62aa1b92513282e8` |

## Outcome

The recorded wrapper ran from 19:32:52 to 19:36:11 UTC on 2026-10-25 and exited 0,
successfully preserving the failed application evidence. The application exited
with code 1. The raw result reports `backend_ready`, `launcher_entered` and
`native_maps_observed` true; `observation_elapsed_seconds=92`,
`outcome="startup_failed"`, `process_exited=true` and `functional_passed=null`.
The configured 600-second observation ended early because of the crash.

All screenshots and raw logs below are retained under
`maps352-2026-10-25/results/attempt352/google-maps/`; the complete raw result is
`maps352-2026-10-25/results/attempt352/results.json`.

| Visually reviewed screenshot | Recorded capture time (UTC) | Observation |
| --- | --- | --- |
| `paris-streets.png` | 19:34:44 | Paris streets and loaded photos |
| `attractions-loaded.png` | 19:34:59 | Attractions map and Tunnel des Tuileries result |
| `application.png` | 19:35:12 | Application exited after opening that result |

The pinned interaction driver records the result click at 19:35:07 UTC in
`interaction.log`. The complete `serial.log` records the missing virtual method
at line 15763, called through `hm$$ExternalSyntheticApiModelOutline0.m`, `geh.e`,
`gdv.b` and `gea.e`. This is a newly exercised place-details path; Maps350's
recorded place was Pinky Tour - Paris. The evidence does not establish that the
text-size change caused the missing-method failure. Directions, route preview
and the complete observation window remain unqualified for Maps352.

| Retained raw evidence | SHA-256 |
| --- | --- |
| `paris-streets.png` | `083439468eac96d404a2cda3dbdae45273facb6d5bef92eb7b78743119f038a0` |
| `attractions-loaded.png` | `49556048d845a6947845127d14b47a40d9081fbcf66b01dc3609956696d15646` |
| `application.png` | `13478c11701c36a8bf9f6fc826f31891f9da9a30669a1588819e02ba48ebd39a` |
| `serial.log` | `fbd99daabe6e4bddd53076b84edf099f37deea27f9bfb8fdd549725fae380ca4` |

The launch envelope's complete readback passes all 9 files, with unchanged
input/program pins and no forbidden environment keys. Complete canonical typed
readback passes all 69,490 entries, including file hashes, directory/link entries
and modes. Verification output and the launch readback receipt remain adjacent
to the sealed bundles as `maps352-report-canonical-readback-2026-10-25.log` and
`maps352-report-run-readback-2026-10-25.json`.

A screenshot command completed after automatic collection at 19:35:13 UTC,
exiting 1 with `No such file or directory`; it produced no `attraction-details.png`.
The separate post-run supplement retains the complete working attempt, exact
canonical interaction prefix, two appended interaction lines and both late
command logs. Its complete typed readback passes all 804 entries, with no socket
omissions. It includes the recorded preserver build and provenance; the canonical
bundle remains unchanged and this failed capture qualifies no additional behavior.

The retained runner repeats complete canonical verification:

```sh
build/android-maps/maps352-run-recorded verify e39f99459a6ee90b8a0d8f9602b3a9719e70f68cdc3589b46dd183053e7f6fda
```
