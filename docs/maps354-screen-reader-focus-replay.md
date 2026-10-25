# Maps354 screen reader focus replay

Maps354 passes onboarding, searches Paris, renders streets and photos, and opens
the Tunnel des Tuileries result from Attractions. Its details show 4.4 stars,
338 reviews, opening hours, an address and loaded photos. Directions from Louvre
Museum render a 2-minute, 600-metre route and a 3-minute alternative. Route
preview displays the first instruction and advances to the next instruction.
The raw result completes the full 600-second observation with Maps still running.

The production fix is `2ee9c8d64dcb5fd9c93a1e4c3625606011c9cd47`.
Its [old/new native ART qualification](../tests/native-android-ws/screen-reader-focusable353.md)
proves the missing setter on the old framework and stateful getter/setter,
keyboard-focus independence, compiled XML and constructor style/theme dispatch
on the fixed framework. This replay exercises the details path that crashed
[Maps352](maps352-text-size-replay.md) on the missing
`View.setScreenReaderFocusable(Z)V` method. It retains Maps352's Native351 SO
and uses the qualified Framework353 JAR.

Relative to the authenticated [Maps350 runtime](maps350-media-exceptions-replay.md),
exactly the native SO and framework JAR change among 109 runtime files; the
other 107 entries match. Launcher334, the original Maps APK, identity256, the
600-second observation and classifier are unchanged. The five base boot members
(`vinix`, `initramfs.tar`, `qemu-runtime.tar`, `maps335-diagnostics.tar` and
`maps350-diagnostics.tar`) are unchanged. The final boot overlay contains exactly
the replacement SO and JAR. The reusable prelaunch checker, committed as
`d25f9cebb`, independently verifies both complete typed trees, runtime modes and
links, streamed FAT boot members, exact overlay and external APK inputs.

All artifact paths below are under `/Users/alex/.local/state/vinix/android/`.
Complete input builds remain at `text-size351-native-build-2026-10-25` and
`screen-reader-focusable353-framework-build-2026-10-25`; the original complete
353 qualification bundle is preserved. The generated source is
`maps354-generation-2026-10-25/maps354-run.v`.

| Qualified input or gate | SHA-256 |
| --- | --- |
| Native351 build manifest | `eb0dfe0dd87ea7f5972bddd06ae4c0c45ba8b9e5ad56a39c074142847f4bccd9` |
| Unchanged Native351 SO | `d3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1` |
| Framework353 build manifest | `22bc4e713113d41a7ab56a1809293fb9f3ccb11fd8cc8c8c589fc20afd19171f` |
| Framework353 JAR | `1e5467f57ac9a3a51a9f29f7c73bf4896b47dc1ea055f59d07db1e1d281cfa83` |
| Generated runner source | `7ef3931d3a3b6c1edd5f923f49b42bf37e46a257b1b0f73e2eda17733dd285ae` |
| Recorded runner | `ad62e51d55a245d0e0d00ca2b9cd9ff10c0adce779f45efc2ba23a039dc7fbf5` |
| Prepared launch pins | `55cc1747f96e281b1a877ee3276c0268845d84d897706a0d4fc8ef440a6e346d` |
| Prelaunch typed manifest | `d47cc48ba26c516fe430593fc929a01d4bba047c51969e619af01ab253323341` |
| Independent prelaunch receipt | `1e204b00b71024e89468a89520ec410957cb55e5c61935a441e330fc6fb64c54` |

The independent prelaunch receipt is
`maps354-prelaunch-peer-review-2026-10-25.json`. The reusable checker's complete
294-file build also passes root readback, retained in
`maps354-prelaunch-review-build-root-readback-2026-10-25.json`.
Preparation and the separate launch check exit 0, preserve their input pins and
leave no forbidden environment keys. Root's complete readbacks pass the 22-file
generation bundle and both 9-file receipts.

| Preserved evidence | Manifest SHA-256 |
| --- | --- |
| `maps354-generation-2026-10-25/sha256.json` | `da7b933d734760740f62acc72bf56765c01900a205b92e00f565041188500ab1` |
| `maps354-preparation-receipt-2026-10-25/sha256.json` | `d5757249feaba4c33dc6bbe740a0cb9c392904db70b7b2dbb3f661144b94c8de` |
| `maps354-check-receipt-2026-10-25/sha256.json` | `43327a49ba65cebcb38999fb3e95085624396f960ce20dfd797d095636498ac5` |
| `maps354-run-receipt-2026-10-25/sha256.json` | `f15a3e3567fbc0294fad1f92999d34f64bcd90fe0905640d55dd1505bfc3987c` |
| `maps354-2026-10-25/sha256.json` | `78326758e2dc9ddd9fdc9fc49bec0d9d335a780f812508cb4eac904a6bb516cf` |

## Captured behavior

The retained interaction log records all manual input and screenshot commands
through pinned `maps-interact-unique258`, SHA-256
`abd2dfbb01fddc83ffffae481b5d1fcab35b9ebd279f3f47abae237b00134208`.
Commands finish by 20:09:02 UTC, before automatic collection. The screenshots
below were visually reviewed; their times are the recorded command times on
2026-10-25. The 600-metre distance is fully visible in `route-returned.png`.
Screenshots and raw logs are retained under
`maps354-2026-10-25/results/attempt354/google-maps/`; the raw result is
`maps354-2026-10-25/results/attempt354/results.json`.

| Screenshot | Capture time (UTC) | Observation |
| --- | --- | --- |
| `attraction-details.png` | 20:04:33 | Tunnel des Tuileries details and photos |
| `google-maps-running.png` | 20:07:51 | Louvre Museum to Tunnel des Tuileries route, 2 and 3 minutes |
| `route-preview.png` | 20:08:15 | Head southwest on Pl. du Carrousel |
| `route-preview-next.png` | 20:08:50 | 120 m; Slight right to stay on Pl. du Carrousel |
| `route-returned.png` | 20:09:02 | Returned route overview, 2 min (600 m), alternate 3 min |
| `application.png` | 20:12:33 | Automatic final capture preserves the route overview |

| Retained raw evidence | SHA-256 |
| --- | --- |
| `attraction-details.png` | `10392c2ad244c20c8273264c4a340c7f90dfc18cb10243aa66650217e3c2d33e` |
| `google-maps-running.png` | `6f594752b81c1c739a1e943e21df5d781b3416143d510cb9b0147904bbabdf5c` |
| `route-preview.png` | `e02c8779cb4cc648edfc47e0f30864a77a62a049b7bff359e76ee6737c711eab` |
| `route-preview-next.png` | `31680dc9ca1143a6ffddbd6cbb0f9c03423d71b3ffc096745cd570e423ae08db` |
| `route-returned.png` | `c2b708660ffb9eb78d9720b36b2a171a8acf71bb74ab8ea2c67b198ac4c18e49` |
| `application.png` | `51fc51e225877d74585d871e4b1c3ea8da2b4b53f241fc13a3a44e4a7a2cdc86` |
| `serial.log` | `7ad93bc663bd97b6440703dd4de5430b3db649d289aee54f4f70ac6688ea051e` |

## Final observation

The recorded wrapper runs from 20:01:42 to 20:13:55 UTC and exits 0; the suite
runs from 20:02:15 to 20:12:34 and exits 0. The final raw result reports
`backend_ready`, `launcher_entered` and `native_maps_observed` true;
`observation_elapsed_seconds=600`, `outcome="window_observed"`,
`process_exited=false`, `qemu_alive_before_capture=true` and
`failure_markers=[]`. The automatic final screenshot still shows the 2-minute,
600-metre route and 3-minute alternative. The complete serial has no recorded
framework-linkage, Android startup or fatal exception markers.

`functional_passed=null` remains unchanged. The captured route preview does not
establish live GPS navigation or media playback.

The sealed launch envelope passes root's complete 9-file readback, retained as
`maps354-run-root-readback-2026-10-25.json`. It records 50 clean environment
entries, no forbidden keys, unchanged input/program pins and exit 0. The live
and collected primary PNG, final PNG and complete serial match exactly. No
socket entries are omitted, and all interactions finish before collection;
no post-run supplement is needed. Root and independent peer complete canonical
readbacks pass all 64,408 typed entries, including file hashes, directory/link
entries and modes. The manifest is unchanged after verification. Their adjacent
logs are `maps354-root-canonical-readback-2026-10-25.log` and
`maps354-peer-canonical-readback-2026-10-25.log`.

The retained runner repeats complete canonical verification:

```sh
build/android-maps/maps354-run-recorded verify 78326758e2dc9ddd9fdc9fc49bec0d9d335a780f812508cb4eac904a6bb516cf
```
