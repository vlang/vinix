# Maps current-location and navigation baseline

Replay321 used the same Framework318-v2 and Native315 as
[replay320](maps320.md), launched from source revision
`baa804bcbd9c519f63dc7fd99ad46e732fe10312`. My Location exposed an unhandled
permission request; choosing Your location twice left the route origin empty.
Manual Eiffel Tower entry recovered a driving result card, but Maps then
exited during route layout with missing `getChildDrawingOrder(II)I`.
Current-location routing and active navigation remain unqualified.

The unchanged classifier records `startup_failed`, 264 observed seconds,
`backend_ready=true`, `launcher_entered=true`, `native_maps_observed=true`,
`process_exited=true` and `functional_passed=null`. Its three failure markers
are `ANDROID-WS-FAIL input or render`, the exact NoSuchMethodError below, and
`APK-SUITE-EXIT id=google-maps code=1 native_observed=true gtk_x11_absent=true`.
The 600-second timeout was unchanged. The recording command ran
2026-10-25 10:52:34–10:57:24 UTC and exited 0; that outer exit records successful
evidence collection, not a passing application.

| Tested flow | Actual retained evidence and result |
| --- | --- |
| Onboarding and Paris search | `my-location-first.png` shows the base map after Skip; `paris-card.png` shows Paris and Directions |
| My Location | Click `(560,483)` at 10:54:33 UTC; `my-location-prompt.png` and `my-location-settled.png` show no permission dialog or blue location dot |
| Current-location origin | `current-origin-directions.png` shows Your location and Choose on map; selecting Your location twice returns to empty Choose start location with Paris destination, including `current-origin-settled.png` and `your-location-retry-settled.png` |
| Manual recovery | `manual-eiffel-suggestions.png` shows the full Eiffel Tower query and matching first suggestion; `manual-route-recovered.png` shows Eiffel Tower → Paris, Drive 20 min and Preview/Add stops/Share |
| Failure | Automatic final `application.png` visibly says The Android APK has exited |

Serial line 7568 records
`requestPermissions([android.permission.ACCESS_FINE_LOCATION]): not handled`.
Line 9022 records unknown settings key `location_mode`. No permission or
location-settings prompt appeared during these tested actions. No provider was
enabled, coordinates injected, or account used. The manual result capture has
no visible route line or Start button; it establishes recovery to a result
card, not navigation. Preview and turn-by-turn operation were not exercised in
this replay.

Serial lines 14266–14287 record the fatal layout path:

```
ANDROID-WS-FAIL input or render
java.lang.NoSuchMethodError: No virtual method getChildDrawingOrder(II)I in class Lbgfu; or its super classes (declaration of 'bgfu' appears in /opt/android-test/application.apk!classes7.dex)
  at bgfu.uB(:com.google.android.apps.maps@1068832648@26.42.01.997557324:1)
  at bgfu.D(:com.google.android.apps.maps@1068832648@26.42.01.997557324:15)
  at bgfu.onLayout(:com.google.android.apps.maps@1068832648@26.42.01.997557324:49)
  at android.view.View.vinixPerformLayout(Unknown Source:55)
  at android.view.View.native_layout(Native Method)
  at android.view.View.layout(Unknown Source:7)
  at android.view.ViewGroup.layout(Unknown Source:8)
  ...
  at android.support.v7.widget.RecyclerView.onMeasure(:com.google.android.apps.maps@1068832648@26.42.01.997557324:63)
```

The fatal sequence follows the 10:57:20 UTC serial entries. A last manual
My Location click `(560,500)` began at 10:57:21 and ended at 10:57:22 while
the application was failing. The pre-input guard checked the socket and exit
marker, but the marker had not appeared yet. This timing does not establish
that the click caused the failure. The guard blocked the following requested
`route-my-location-result` capture; no such file exists. The suite itself
captured final `application.png` at 10:57:24. No further manual input, capture
or bundle modification followed detection of the exit.

All captures retain their original chronology and names. In particular,
`map-after-skip.png` still shows the pending onboarding transition, and
`paris-suggestions.png` shows the initially empty search editor. Neither is
used as proof of its filename's implied state.

The clean283 launcher, original APKs, 109-file runtime comparison, default
5,120 MiB disk gate and classifier are unchanged. Maps APK SHA256 is
`6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2`;
Play Services SHA256 is
`a34d6a3ccea3ceba491369517e8f12e11df3791e86fec38b1cdf693785e35707`.
The fresh six-pin JSON SHA256 is
`de77c8480aae4b31cd0b706c5edd11ee2df6b5b806583dde8cf84a8ef83a6c24`;
the sealed copy is `runner-build/generation/replacement-build-pins.json`.

| Artifact | External build directory | Manifest SHA256 | Payload SHA256 |
| --- | --- | --- | --- |
| Native315 | `/Users/alex/.local/state/vinix/android/nine-patch-tint315-native-build-2026-10-25` | `09c2c82ff7feb169733c7f77fc11683f409b2114e409fe9e70a8346c277d5aee` | `54a2fd873abd6be543b236b7c123a052e456ec7b8c823f9063751b880d9127ab` |
| Framework318-v2 | `/Users/alex/.local/state/vinix/android/tts-span318-v2-framework-build-2026-10-25` | `869d22f75a01c7ffd88604a04a73b67cc012daca9651a571e5eab30aafd0594c` | `6b826b2b7c37eb6b101d2627854064d1d06988f7c8bbdf1b94c1dea012e86b5d` |

The maintained generator `tests/native-android-ws/maps-replay-generate.v`
SHA256 remains `39b9d763de6c5685021731ec877a276d2110f8cd457c4ff6bcf8bc1e399b6d84`;
the reused generator binary SHA256 is
`75b69d07fdf23401b07ee8cad36d7ba2a47dfd5e48c13660c4307f91e882b453`.
Its original `maps298-run.v` input SHA256 is
`5d220b06590bc0823f12c6d5071dc60af51a9dc284a383afb77cb907c1f17ed1`.
Generated `maps321-run.v` SHA256 is
`633ba0b738e6178c5aad547b7593df4fdc9b0b534866a820e66307713f97f8b0`;
the recorded runner SHA256 is
`e11ce63cd646dc285a2b816ef77bbb8bbb06c4ec1aa277607d7cd6fcf7412419`.
Compiler `build/android-maps/queue284-tools/v_old276` SHA256 remains
`109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e`.
Complete consumed sources, before/after closure maps and exact compiler
commands/receipts are sealed under `runner-build/` and `prelaunch/`.
Generation, preparation and launch commands were:

```
build/android-maps/maps-replay-generate314 321 /Users/alex/.local/state/vinix/android/maps321-replacement-build-pins-2026-10-25.json
build/android-maps/maps321-run-recorded prepare \
  /Users/alex/.local/state/vinix/android/nine-patch-tint315-native-build-2026-10-25 \
  09c2c82ff7feb169733c7f77fc11683f409b2114e409fe9e70a8346c277d5aee \
  54a2fd873abd6be543b236b7c123a052e456ec7b8c823f9063751b880d9127ab \
  /Users/alex/.local/state/vinix/android/tts-span318-v2-framework-build-2026-10-25 \
  869d22f75a01c7ffd88604a04a73b67cc012daca9651a571e5eab30aafd0594c \
  6b826b2b7c37eb6b101d2627854064d1d06988f7c8bbdf1b94c1dea012e86b5d
build/android-maps/maps321-run-recorded run 53de492209bf74c17a3606cc2c554aa1d2b8a4d38b06e595a708e698aa80e3f9 ba7054740d31816fc7be94d2fb5877792a4960642be17bf7c934e903eed0d362
```

The complete stopped-guest bundle is
`/Users/alex/.local/state/vinix/android/maps321-2026-10-25`, typed manifest
SHA256 `dce30287216ca82512255309f440b37cf3fbfdbee3a1aad9df0147431d53d2b6`.
Full typed readback passed all 22,890 entries, including files, directories,
symlinks and modes:

```
build/android-maps/maps321-run-recorded verify dce30287216ca82512255309f440b37cf3fbfdbee3a1aad9df0147431d53d2b6
```

Paths below are relative to `results/attempt321/google-maps/` in that bundle:

| Evidence | SHA256 |
| --- | --- |
| `serial.log` | `7e199253a5bd138998d619c40cfee7f7cb43415efcbb3616afa1695e99e0a48f` |
| `interaction.log` | `d4ab5cf133e95c1668d70d25b38462f2908b0fe2d104b1564983c38f4e5ff939` |
| `observation-before-capture.json` | `92bf1c952d3aa7ebc42674e7fda0571d3653f9ef480c86ea21059f8c009b9373` |
| `application.png` | `f12b1b5bb8f521d8da468ad108949eb7db54e35789246b3200f8f4e1569a1ac4` |
| `my-location-prompt.png` | `8b6c3cdb16abee732391535ce1920a78d4ae49ec25ff3b35cf91d5e700461b6b` |
| `my-location-settled.png` | `acf988562d03c82b83fbf2758bb23405403ced88efb324fc3c5cd5678dbf1495` |
| `paris-card.png` | `1cc27f2a544a6b9c7f553baf65bf057bce39bd04f4787f0e4481d841606721f1` |
| `current-origin-directions.png` | `c4e93a7e2970733ec0e311b84f97b840c9e80231287d9725d82021942b5bb754` |
| `current-origin-settled.png` | `30aa933511e5bbd5dbbcfb5e1572ebf546f90a2d2ae8fb3e9231b862b0b38426` |
| `your-location-retry-settled.png` | `58b9e24bbadd125ce25b51470a95ccdb7223084ff0a2b43ac8f2ed0b3ab01c68` |
| `manual-eiffel-suggestions.png` | `4d267035cd1d12675f68142529876f0438a1d431fc77cb8c6770669a8c887045` |
| `manual-route-recovered.png` | `085db1ac2aad53c2d8ff6c64ec7f2752aac1325c5c54f472f6dac0b4b6ef65bc` |
