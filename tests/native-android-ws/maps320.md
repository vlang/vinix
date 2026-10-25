# Maps replay after TtsSpan support

Replay320 launched after commit
`cf0c329a83f251d63aa77f8cdd942d61d9ce1f14`, using Framework318-v2 and
Native315. The TtsSpan failure from [replay317](maps317.md) is cleared:
Skip opens the base map, Paris search suggestions and its place card render,
and manual Eiffel Tower origin selection produces driving and walking routes.
The framework contracts are qualified separately by [regression319](tts-span319.md).

The unchanged historical classifier records `window_observed`, 600 seconds
observed, backend/launcher/native maps observed, `process_exited=false` and
`failure_markers=[]`. Its `functional_passed` remains null. The recording
command ran 2026-10-25 10:30:30–10:40:48 UTC and exited 0; that outer exit denotes
successful recording. Manual screenshot review qualifies these specific flows:

| Flow | Retained evidence and result |
| --- | --- |
| Onboarding and search | `map-after-skip.png`, `paris-suggestions.png`, `paris-card.png`; map labels, photos and Directions visible |
| Driving switches | `options-initial.png`, `options-{tolls,highways,ferries}-{on,off}.png`; each avoid option changes grey track/left thumb → cyan track/right thumb → grey/left |
| Toll prices | `options-toll-prices-{off,on}.png`; initial cyan/right changes grey/left and returns cyan/right |
| Walking switches | `walking-options-initial.png`, `walking-options-{wheelchair,ferries}-{on,off}.png`; each changes grey/left → cyan/right → grey/left |
| Driving route | `driving-overview-final.png` and final `application.png`; selected blue/purple line, grey alternative, map labels and 20 min/6.1 km card visible |
| Walking route | `walking-route-settled.png`; selected blue dotted path, grey alternative and 1 hr 3 min/1 hr 5 min labels visible |
| Driving preview | `driving-preview-{settled,next,previous}.png`; Next changes Pont d’Iéna instruction/camera to the left turn at Pont de l’Alma; Previous restores the first step and camera |
| Walking preview | `walking-preview-{settled,next,previous}.png`; Next changes Head northwest to the 50 m slight right toward Rue de l’Université and moves the camera; Previous restores both |

Each switch capture follows a 2.2-second settle. Root and an independent agent
reviewed the actual screenshots, including each switch returning to its initial
state and the unchanged other rows. These are visual per-control state
results; screenshots do not identify the runtime drawable class. The initial
`driving-route-settled.png` temporarily
lacks the route line; the final overview after returning from walking and the
automatic final capture show it. `driving-overview-return.png` records an
intermediate origin editor and is not route evidence. All captures remain in
their original interaction chronology.

Routes use a manually entered Eiffel Tower origin. This replay does not
qualify live GPS, active navigation, spoken directions, sign-in or persistence
after restarting. The last interactive capture completed at 10:38:40 UTC;
there were no input or capture commands after the timed shutdown or sealing.

The clean283 launcher, original APKs, 109-file runtime comparison, default
5,120 MiB disk gate and 600-second observation logic are unchanged. Maps APK
SHA256 is `6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2`;
Play Services SHA256 is
`a34d6a3ccea3ceba491369517e8f12e11df3791e86fec38b1cdf693785e35707`.
The exact six replacement pins are retained in
`runner-build/generation/replacement-build-pins.json`:

| Artifact | External build directory | Manifest SHA256 | Payload SHA256 |
| --- | --- | --- | --- |
| Native315 | `/Users/alex/.local/state/vinix/android/nine-patch-tint315-native-build-2026-10-25` | `09c2c82ff7feb169733c7f77fc11683f409b2114e409fe9e70a8346c277d5aee` | `54a2fd873abd6be543b236b7c123a052e456ec7b8c823f9063751b880d9127ab` |
| Framework318-v2 | `/Users/alex/.local/state/vinix/android/tts-span318-v2-framework-build-2026-10-25` | `869d22f75a01c7ffd88604a04a73b67cc012daca9651a571e5eab30aafd0594c` | `6b826b2b7c37eb6b101d2627854064d1d06988f7c8bbdf1b94c1dea012e86b5d` |

The unchanged maintained generator is
`tests/native-android-ws/maps-replay-generate.v`, SHA256
`39b9d763de6c5685021731ec877a276d2110f8cd457c4ff6bcf8bc1e399b6d84`;
its reused binary SHA256 is
`75b69d07fdf23401b07ee8cad36d7ba2a47dfd5e48c13660c4307f91e882b453`.
The original `maps298-run.v` input SHA256 is
`5d220b06590bc0823f12c6d5071dc60af51a9dc284a383afb77cb907c1f17ed1`.
It generated `maps320-run.v`, SHA256
`c33ff8fd47aef98ae35bb571d637958142aa7f00ecd65e08fe266baeb8669bef`.
The recorded runner SHA256 is
`8b63617d65a99b86e1d104b8a085c0b67dbc2ca74493d41b0185739113215364`;
compiler `build/android-maps/queue284-tools/v_old276` SHA256 is
`109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e`.
The complete consumed V sources, matching before/after closure maps, compiler,
build commands and receipts are retained under `runner-build/` and
`prelaunch/`. In particular, `runner-build/build-receipt.json` records the
exact compiler command. Generation, preparation and launch commands were:

```
build/android-maps/maps-replay-generate314 320 /Users/alex/.local/state/vinix/android/maps320-replacement-build-pins-2026-10-25.json
build/android-maps/maps320-run-recorded prepare \
  /Users/alex/.local/state/vinix/android/nine-patch-tint315-native-build-2026-10-25 \
  09c2c82ff7feb169733c7f77fc11683f409b2114e409fe9e70a8346c277d5aee \
  54a2fd873abd6be543b236b7c123a052e456ec7b8c823f9063751b880d9127ab \
  /Users/alex/.local/state/vinix/android/tts-span318-v2-framework-build-2026-10-25 \
  869d22f75a01c7ffd88604a04a73b67cc012daca9651a571e5eab30aafd0594c \
  6b826b2b7c37eb6b101d2627854064d1d06988f7c8bbdf1b94c1dea012e86b5d
build/android-maps/maps320-run-recorded run 36e26a249af7ee3d41448ecb2e937c94bb95f3695696d13dc498f816df66829a 30fafc093bdcef3b971816c0d14f4d5609a93dfb2315435c53559822f0e846e5
```

The complete stopped-guest bundle is
`/Users/alex/.local/state/vinix/android/maps320-2026-10-25`, typed manifest
SHA256 `4f01dee905fbe0f6230a8fa79be5754122871184b3b2beb7e07cbf4682d23aff`.
The runner and independent root readback passed all 23,150 typed entries,
including files, directories, symlinks and modes:

```
build/android-maps/maps320-run-recorded verify 4f01dee905fbe0f6230a8fa79be5754122871184b3b2beb7e07cbf4682d23aff
```

Paths below are relative to `results/attempt320/google-maps/` in that bundle:

| Evidence | SHA256 |
| --- | --- |
| `serial.log` | `7bffa0a4c0c3781aefbb526362e44216abf0ca3f838f114be395a3bb577e405f` |
| `interaction.log` | `73f7973d45cbb434a6981188a5198ed7454f78a655b35773ef027516850ea52c` |
| `application.png` | `0dbb163767fa10d84f382e42c6c9fae8cc1e0c7614640a3469754152cdb80f7f` |
| `options-initial.png` | `d002a077a000f9c03754bdfc812d04a3d0f499b2144e39dbb8aa4f75b9b2f3a6` |
| `options-tolls-on.png` | `d3fd0cbd48b93387716fdffea08c38cca5feff8de7716d458193076cfa933fbf` |
| `options-tolls-off.png` | `cc3dbc20cf3e58c5d9854ef8db7012264c717136508486fb3a5b276643b0888d` |
| `driving-overview-final.png` | `ac236a5487c4096ecb8c0b2a00e276f7012879f18f33d91f592c1dabf7dd2024` |
| `walking-preview-next.png` | `13b8d229ec7ad3500b35a16c0954b308386f3c3cc341d45f3292cda175caadf7` |
