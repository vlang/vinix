# Maps327: native map, Paris details and denied location

Replay327 used qualified Framework325 and Native315 from source revision
`de79af74280f6c5c0b8341953f4c5f4e522e3c55`. Google Maps rendered its native
map, searched Paris, displayed the Paris place card and handled denied
location with its own Back/OK explanation. A later Attractions search left
an empty lower sheet: dragging the sheet worked, but repeated close/search
clicks did not visibly recover that flow. Directions, route preview,
current-location routing and active navigation remain unqualified.

The unchanged classifier records `window_observed`, 600 observed seconds,
`backend_ready=true`, `launcher_entered=true`, `native_maps_observed=true`,
`process_exited=false`, `qemu_alive_before_capture=true`,
`failure_markers=[]` and `functional_passed=null`. The 600-second timeout and
default 5,120 MiB disk gate were unchanged. The launch receipt records
2026-10-25 11:32:51–11:43:05 UTC and outer exit 0; that exit records completed
evidence collection, not full application functionality.

All evidence paths below are relative to
`results/attempt327/google-maps/` in the retained bundle.

| Tested flow | Actual retained evidence and result |
| --- | --- |
| Map after onboarding | `map-after-skip.png` at 11:33:44 UTC shows the native map, search bar and bottom navigation after Skip |
| Map and Paris search | `paris-place-settled.png` at 11:36:19 UTC shows the Paris map, place card, photos and Directions/Share/Save/More buttons; the search field already says Attractions |
| My Location | Click `(560,426)` at 11:33:57; `my-location-first.png` at 11:34:02 shows Maps' location-denial explanation with Back/OK |
| Denial recovery | OK `(453,460)` at 11:34:14; `permission-denied-ok.png` at 11:34:20 shows the map again; another My Location click repeats the denial |
| Unresolved Attractions flow | `directions-editor-settled.png`, `search-field-recovery.png` and later captures show Attractions with a blank/loading lower sheet, not a directions editor |
| Gesture response | Drag `(360,410)` to `(360,680)` at 11:39:48; `panel-recovery.png` at 11:40:07 shows the sheet lowered and more map exposed; `recovery-final.png` retains this state |
| End of observation | Automatic `application.png` at 11:43:04 still shows the native map and unresolved Attractions sheet |

Capture names retain their original chronology. In particular,
`my-location-settings-prompt.png` shows another denial explanation, not
location settings, and the two `directions-editor-*` captures show Attractions,
not directions. Serial lines 7694–7698 directly show Maps'
`neg.onRequestPermissionsResult` called through `VinixPermissionResult.run`,
`Handler` and `Looper`. This confirms callback delivery alongside the denial
UI. No permission grant, location provider, injected coordinates, blue
current-location dot or account was established.

The complete serial log contains no `ANDROID-WS-FAIL`, `APK-SUITE-EXIT`,
`NoSuchMethodError`, missing `getChildDrawingOrder(II)I`, or former
`requestPermissions(...): not handled` marker. This does not qualify the old
route-layout path, which was not reached. A Play Services finalizer reports
`IllegalStateException: Lock wasn't released correctly` at lines 4154–4160;
line 10091 records unknown settings key `location_mode`. Maps continues
after both. Lines 7670–7702 also contain a caught APK-signature verification
`NullPointerException` while `ATLLoadedApp.getSystemApplication` creates the
denial dialog. The retained Framework325 disassembly shows that this
resource-only system package has a null archive path, passed to the verifier's
`String.concat`. System application creation and the denial dialog continue;
this stack does not establish the cause of the later Attractions stall.
Native loop counters advance through the final observation, and additional
RecyclerView inflations appear at lines 11980, 12366 and 13060, so the
unresolved sheet is not evidence of a permanently blocked main loop. Thread,
view-tree and transition snapshots were not enabled; its cause remains
undetermined. A fresh route replay should select Paris once, wait for the
settled place card before pressing Directions, and test a manual origin
before exercising My Location.

The requested real PNG is retained at
`/Users/alex/.local/state/vinix/android/maps327-2026-10-25/results/attempt327/google-maps/map-after-skip.png`,
SHA256 `c944a448aac680fe880d6fbf810205dd73a9dfb23ce29fe56e0c9a9a313dfce4`.
It is a framebuffer capture of Maps on the Vinix desktop, not a generated
illustration.

| Qualified overlay | Manifest SHA256 | Payload SHA256 |
| --- | --- | --- |
| Framework325 (`maps-runtime325-framework-build-2026-10-25`) | `17df965baca0c030e1111a9b974410e9594b6e9ccfb814d371df6a53b0ead682` | `181743124944671e934bc6003f6915511f3b43aabd060842e793309b8d988cfa` |
| Native315 (`nine-patch-tint315-native-build-2026-10-25`) | `09c2c82ff7feb169733c7f77fc11683f409b2114e409fe9e70a8346c277d5aee` | `54a2fd873abd6be543b236b7c123a052e456ec7b8c823f9063751b880d9127ab` |

Both overlay directories are under `/Users/alex/.local/state/vinix/android/`.
Framework325's paired ABI and permission regression is documented in
[child-permissions326.md](child-permissions326.md). The original Maps APK
SHA256 remains
`6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2`;
Play Services SHA256 remains
`a34d6a3ccea3ceba491369517e8f12e11df3791e86fec38b1cdf693785e35707`.
The clean283 launcher, 109-file runtime comparison and classifier are unchanged.

The complete stopped-guest bundle is
`/Users/alex/.local/state/vinix/android/maps327-2026-10-25`, typed manifest
SHA256 `4a61c46fbc4e71e4dd27ec4021bbed7923a62951d4617d434ab0fdedcef89ce1`.
Independent full typed readback passed all 22,916 entries, including payloads,
directories, symlinks and modes:

```
build/android-maps/maps327-run-recorded verify 4a61c46fbc4e71e4dd27ec4021bbed7923a62951d4617d434ab0fdedcef89ce1
```

Generated runner source SHA256 is
`f9ef40c61903b1e33fc3263efe7eb3a88714564722cf1e86f0d4044c5a287700`;
recorded runner binary SHA256 is
`f251df1bdaf05516fc93f40154c3d7802f545cf711c6cd5f08ec3bc52e8ba310`.
The launch pin is
`d9a4277470140e2c59b8b8fff1e8d52ad5fba963f155d210c73e0b16acad610f`;
prelaunch typed-manifest SHA256 is
`2e5611f120db7eeacb98aa5d2a5fc022daf5c857e761c06e88c4339ae75ac76e`.
Consumed source closures, compiler commands, build receipts, prelaunch inputs
and complete results remain in the bundle.

| Evidence | SHA256 |
| --- | --- |
| `serial.log` | `0364a7afbf81e7f54e51a14cdbd5ab97e37f6f89cc28409dee94f58d7380f700` |
| `interaction.log` | `79d58385287722e4e82ce0b32a23abf5cf37c6b51ccc63d5310e3897dd3c7d44` |
| `paris-place-settled.png` | `254dc804cab90c0e1a9376fe74da20a01bafc49e837c2e2c5a36d0afaaa4fb32` |
| `my-location-first.png` | `73a29c3def4885fa7501876884c3e868d87c36dc1df55197dd0511424a6a7c65` |
| `application.png` | `5aa5fb146ca413f653888eec8c063b31d7f00062624d876ad699cf268ebfabea` |
