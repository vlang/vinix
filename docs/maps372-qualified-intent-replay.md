# Maps372 qualified Intent replay

Maps372 ran Google Maps for the full 600-second observation and rendered Paris
place search, driving and walking routes, and successive route-preview turns.
It integrates the final [Framework371](intent-uri371-framework-build.md),
including its null-safe `Intent.getDataString()` repair. The unchanged Intent
ART fixture already passed against this framework; see
[Intent371 regression](intent-uri371-regression.md).

This is a fresh replay following [Maps370](maps370-intent-uri-replay.md).
Its complete evidence is retained outside Git under
`/Users/alex/.local/state/vinix/android/`; earlier sealed bundles are unchanged.
The runtime bundle records source revision
`12b23c4165c267eab7326d265901f5371ffd6da2` in `references.json`.
The Maps APK, companion APKs, Native351, Loader357, launcher, classifier and
600-second observation contract remain pinned. All 106 unchanged runtime files
and the five original base boot members remain subject to the inherited checks.

The generator composer is commit `ff410a929`; runtime receipt tooling is
`6ca5cadba`. Both derive from exact pinned Maps370 sources. The generator adds
an exact source and DEX check for the final getter and seven mutation checks.
The receipt wrapper retains its compiler-closure, environment filtering,
replacement identity and nonzero child-status checks, and rejects old replay
numbers 370 and 371.
The independent comparator and completed-bundle reader compositions are
retained in commits `f2ab7c78e` and `12b23c416`; the independent generator
bootstrap checker is retained in `2b6073cf6`.

| Input or host result | SHA-256 |
| --- | --- |
| Framework371 build manifest | `71e311764ece295185656854294a514a9c641419c567d5f96ac66f52f4b89750` |
| Framework371 JAR | `3b345e1661ca9f5b616f5abe25c9f4abc1df383204d25333477dae69221a8d21` |
| Native351 SO | `d3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1` |
| Loader357 SO | `42c7ac8a276a7eb72a3844e94e182aef8ad7df4c2f8f7313f7061527d077b908` |
| `maps372-generator-composition-b-2026-10-26/sha256.json` | `85d116049a447d635a98dce50b07061701800744d3bc073fa82952a7c9a134d1` |
| `maps372-generator-build-2026-10-26/sha256.json` | `21393930e1c5e1d81f3fa4f6993b604223d9bd11cd329631c4eb310abbf63911` |
| `maps372-generator-peer-readback-2026-10-26.json` | `56b8f4024a9f8fae585951d0cae41e3bbf0e4015fb8f95c355b3ccfb3b743fbb` |
| `maps372-runtime-tools-2026-10-26/sha256.json` | `008c4b490feec17e05eeb44acdf4d6fb6e9bdb92e34bc9d57cdabc844c71a6a4` |
| `maps372-replay-receipt-build-2026-10-26/sha256.json` | `33c3786b02c8d675b49ca51f4e085307378138db8214c9843b157d0beb8a6324` |
| `maps372-replacement-pins-2026-10-26.json` | `25602c7c45d1605df1b5ebfa5582392c7878f3fc4d97a54b5a45d5b102c5013d` |
| `maps372-generation-2026-10-26/sha256.json` | `ea8a788c9d5fe1e074b15e9e3b301e346fa6a7509a2eb2878a61299d09786ffb` |
| Generated `maps372-run.v` | `07fc948c5affd1142f2b86c50024278e719d3f68339f4697864a16103fa36d67` |
| `build/android-maps/maps372-run-recorded` | `741952dfd7bed0f1408e16a7b966771cbe556f69ed3954fe4672f270f2a3787d` |
| `maps372-prepare-receipt-2026-10-26/sha256.json` | `a02deae7f5e5fc9a9e39d77ba1ff6f8c0c05237752a544bdf1a58deef2fd87db` |
| `build/android-maps/maps372/launch-pins.json` | `8bc0e35995fe4f4f579f08e5a9a751c4a03ab86d52a18b1d45d1e39fc7b6c223` |
| `maps372-2026-10-26/prelaunch-sha256.json` | `233a5539b7179b5bbba9a3e21b5b1abc7fd309115cdc5af16bca0e4f5f77c568` |

The independent generator build check passed with actual exit 0: the original
complete290 checker verified all 297 files and the exact 272 live and retained
compiler inputs. Generated sources, binaries, command receipts and logs remain
in their complete external bundles.

Preparation ran 05:03:27–05:08:16 UTC on 2026-10-26, actual exit 0, with
unchanged inputs, 50 clean environment entries and no forbidden keys.
The recorded launch check ran 05:10:41–05:14:57 UTC, actual exit 0.
Its receipt manifest is
`c0860aec4d165db1065edc4aa2638b6b1cea04d69dcab634c3626d3b71bace31`.
The original complete290 checker independently passed all nine preparation
wrapper files and all nine launch-check wrapper files, actual exit 0.
Their peer receipts are `maps372-prepare-receipt-peer-readback-2026-10-26.json`
(`899ad06923732b74dae641ba52e6ceaf12a1a278062e19592c0791f3774a2230`)
and `maps372-check-receipt-peer-readback-2026-10-26.json`
(`873afe5a166f38508b95fe54603b3f4a0304d9318b2aee46a3204211de35d9fa`).

Independent typed prelaunch review ran 05:11:27–05:14:54 UTC, actual exit 0.
It checked all 50,901 Framework371 build files and its complete historical
baseline chain, 2,404 Native351 files and 2,440 Loader357 files. The final
getter passed exact source and DEX checks. Both complete typed prelaunch
inventories, the 109/106/3 runtime-file contract, APKs, classifier, observation
setting, base media and final overlay passed. Its receipt
`maps372-independent-prelaunch-review-2026-10-26.json` has SHA-256
`951dc3f97d3f5d9442872f71595e04c727f3e1bc8956f78be3c477c7cf8b6eaa`;
the adjacent command receipt has SHA-256
`774aab68fb983601920429a0c9a84847bc219ab8d69119e9ee398d482f714868`.

The fresh guest passed onboarding: Skip was sent at 05:21:06 UTC and the map
probe matched at 05:21:42. Visual review confirmed map tiles and the search bar
in `google-maps-running.png`. The first text injection did not populate the
search field; `paris-search.png` preserves that empty state. Repeating
the input after the view settled produced the complete `Oasis dAboukir Paris`
query and the correct Paris suggestion in `paris-search-results.png`.

Selecting it rendered Oasis d'Aboukir place details, rating, opening hours,
photos and Paris tiles in `paris-place.png`. Directions accepted the complete
`Palais Royal Paris` query and the Palais-Royal, Paris suggestion. The loaded
driving route showed four minutes, with a sixteen-minute walking alternative.
An attempted location-button action displayed Maps' location-denial message;
it was dismissed. Selecting the walking alternative on the map and Preview
opened route preview. `paris-route-preview-ready.png` shows “Head toward Rue
Thérèse”; Next advanced to “Turn right onto Rue des Petits Champs” at 200 m in
`paris-route-next-instruction.png`. Each input and capture has its actual
command status and stdout/stderr retained in `interaction.log` and companion
logs. Intermediate screenshots retain their original capture names, including
`paris-walking-route.png`, which records the location-denial dialog rather than
the subsequently selected walking route.

This validates anonymous map rendering, place search, place details, driving
and walking route selection, and advancing route preview. Live GPS navigation
and Google account sign-in were not tested.

The full observation completed with `observation_elapsed_seconds=600`,
`outcome=window_observed`, `backend_ready=true`, `native_maps_observed=true`,
`process_exited=false`, `qemu_alive_before_capture=true` and no failure markers.
The inherited generic classifier leaves `functional_passed=null`; the workflow
claims above come from the recorded interactions and visual review. The final
serial log contains no `FATAL EXCEPTION`, `NoSuchMethodError`, `ANDROID-WS-FAIL`
or `APK-SUITE-EXIT` markers. Its SHA-256 is
`71ceb9f551d9befe4a0d5804bdf1bc18cd64168264d8f25093dab6bc5aedf251`.

Screenshots reside under
`maps372-2026-10-26/results/attempt372/google-maps/` in the external state root.

| PNG | SHA-256 |
| --- | --- |
| `google-maps-running.png` | `e85bbac56604d502b2a530cbbcc3934bd4446c109c51ba10b382f8a2000cfe8d` |
| `paris-place.png` | `83309e0f9b433d39a38e1373d08c5886320e49362ec694a22658192fa1d10cf5` |
| `paris-driving-route-loaded.png` | `311f5c8f75832741979ccee935894914fb1c2c9ac63deb29946587078128b9ec` |
| `paris-route-selected.png` | `83c7482daf440fef07bff8e323734929028bcdf2f000ff9161378db266aabbca` |
| `paris-route-preview-ready.png` | `c34c842749ab5789bbb7df5fc5ff9479181b04ee7c70ba8750763b57b0d62e29` |
| `paris-route-next-instruction.png` | `923b1884d1479a3309e1aff56f65966dcaf8e984263f51dcf45f0005977f9b80` |
| `application.png` | `1ee6cd52940e7dc7bb3bb5dca960ea553a8b8df64e050aea725c822a596d5560` |

The recorded run command completed 05:16:13–05:35:57 UTC, actual exit 0,
with all input pins unchanged, 50 clean environment entries and no forbidden
keys. The wrapper receipt bundle is
`maps372-run-receipt-2026-10-26/sha256.json`, SHA-256
`747dfff998adbe46ef58561212d05af36614d238198ae88f6a9d62a55d51ae71`.
The completed canonical bundle is `maps372-2026-10-26/sha256.json`, SHA-256
`ff24014c3372e93923d1d399bbd80328bee9e0c605c33b1a0b785f6eb0b0f202`.
Its manifest covers the original complete historical bundles and the fresh
results; no earlier evidence was replaced.

The sole independent run-wrapper readback passed at 05:37:20 UTC, actual exit
0: the original complete290 checker verified all nine files, the exact file
set and every hash. The checker, recorder source/binary and manifest identities
remained unchanged. Its receipt
`maps372-run-receipt-peer-readback-2026-10-26.json` has SHA-256
`92cabbf39edc8c5ceb01a141981d7dbb1a4df83eb28b295801bf1a8a8cfbe67f`;
the adjacent command receipt has SHA-256
`62896d0138e5faecb5f4517060c99ba1fed65e4d7c421e2d6617674bc623bfa1`.

The sole independent completed-bundle readback passed 05:42:46–05:44:10 UTC,
actual exit 0, verifying all 163,524 manifest entries and the complete typed
runtime contract. Canonical manifest, generated source, runner and retained
reader identities remained unchanged. Its recorded argv invokes the unchanged
runner with `verify` and the exact completed-manifest hash above.
The receipt is `maps372-report-peer-readback-2026-10-26/receipt.json`, SHA-256
`74fd8ca1189e6fd362ab8cbe8462d9fc5fe4a90dba6665602a5776a7ad5832bf`.
Its stdout has SHA-256
`c79771b09271b503f172fdb8a4da233fcf131cd58fff7152e9b5913d6bfe81a3`.
