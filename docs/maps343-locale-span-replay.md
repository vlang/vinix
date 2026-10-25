# Maps343 LocaleSpan replay

Maps343 passed onboarding, rendered the map, opened Paris with two loaded
photos, and displayed Attractions filters and the Jardin d’Acclimatation result.
Selecting that result passed the previous LocaleSpan resolution failure, then
exited Maps during layout with a missing `View.getTouchDelegate()` method.
This replay does not establish complete Maps compatibility.

The qualified framework source is
`b37f14933ea6fa12c911b9820b212bf6d965426c`
(`Android: implement LocaleSpan for Maps place names`). Its JAR SHA256 is
`79023bd51618bc54f069fe6fd85c812679a81f6db70268f78bca38053b2d1972`.
Derivation tooling is committed at
`9c60d1254a20b373700c255f81696bcb4f94a19c`; generated-runner and wrapper tooling
is committed at `2547b0edf1949d7cb597b9e4c96ca71e7d92ba5c`.
The JAR is the sole changed entry among the authenticated Maps335 prelaunch
runtime's 109 files. The other 108 files, native332 payload, diagnostic launcher,
kernel, base media and original classifier remain unchanged.

All times are UTC on 2026-10-25. The recorded envelope ran 17:22:56–17:25:41
and started QEMU at 17:23:25. It exited 0 and records unchanged input pins,
50 clean environment entries and no forbidden environment keys. The requested
observation limit remains **600 seconds**; the unchanged classifier records
**95 seconds observed**, `startup_failed`, `process_exited=true`,
`backend_ready=true`, `native_maps_observed=true`,
`qemu_alive_before_capture=true` and `functional_passed=null`. Maps exited 1
after the row selection. Successful collection is separate from this functional
failure.

Paths below are relative to `/Users/alex/.local/state/vinix/android/`.
Actual QMP PNGs, input receipts and logs are retained under
`maps343-2026-10-25/results/attempt343/google-maps/`:

| Time | Observation | PNG | SHA256 |
| --- | --- | --- | --- |
| 17:23:54 | Rendered map after Skip | `map-probe.png` | `7f110ac9533b22232a9876ddc4c5092dea02645718e34b3e712abc5cf93f6681` |
| 17:24:31 | Paris map, place sheet and two loaded photos | `paris-place.png` | `5298a371b5df5e978b28adcf29e9fdd4a854293fde6fce6bfe7205e797de318a` |
| 17:24:57 | Attractions filters and Jardin d’Acclimatation result | `attractions-loaded.png` | `743e862db3289624638c1c37527b5aa8b03d5606b426122ed77b7b30992641ed` |
| 17:25:07 | Launcher reports that the Android APK exited | `application.png` | `e8826c8b3a90fea57bc2ff1be862a71e290cf299c51dc51cc4b7cb6bae0b570c` |

`interaction.log` records Skip at 17:23:43–44, Paris suggestion selection at
17:24:16, the Attractions click at 17:24:36 and the result-row click at
17:25:04–05. The transition Future records `done=1` at serial line 13399.
Serial lines 15237–15373 show `ANDROID-WS-FAIL input or render`, the
`getTouchDelegate()` `NoSuchMethodError` in `bgdt.a` called from
`ndt.onSizeChanged`, and the APK exit. The earlier LocaleSpan resolution error
does not recur. The four PNGs above were visually reviewed.

The later 17:25:19 screenshot request failed with exit 1 after automatic
collection had copied the results; it produced no `attraction-place.png`.
The separate `maps343-postrun-interactions-2026-10-25` supplement preserves the
complete live `interaction.log` and the late
`command-58284-1792949119405703000-17625.{stdout,stderr}.log` pair. Its scope
records exactly those three file differences and the two appended interaction
lines. The original canonical bundle and launch envelope were not altered.

| Retained artifact | SHA256 |
| --- | --- |
| Qualified `locale-span342-2026-10-25/sha256.json` | `a48ee29feb4c34adfc1558117cf3c3db4ce1d3cb95d5f22f1a5c0e13cdeaaf9a` |
| Generated `maps343-generation-2026-10-25/maps343-run.v` | `46333d01c6f9a42896eeea82f03f575294ebc27e503de6c915d5e4f69a1a8037` |
| Recorded `build/android-maps/maps343-run-recorded` runner | `cd2b620516e4b1d727824610e88d1c47a6f4448dc244ed0a4c171003393d070f` |
| Launch pins | `1abde731fa3ff166cb31daadcdcdbe725910523b80e7bb388f84ab766b9ce478` |
| Prelaunch typed manifest | `1a65d24f140d40028a7cabb2863375b3c8175e3ee147d1ca45e49b36059b4a8a` |
| Preparation envelope manifest | `2473e3eb8d08a297aaafa1d92fc4e407331bc9533bff734673923858448b49c9` |
| Run envelope manifest | `a759c9c5bc1d0feef2b171f3fb941336821b4d854ac6c67f18406f1319a300e3` |
| Canonical `maps343-2026-10-25/sha256.json` | `de5e38aa37b28ba99db661d82cf50e20600319c00b6ff735d4e68cf3724a3d3b` |
| Late-interaction supplement manifest | `f50431a70886139f2ad9b40c587931683c022954b94c8e5b233953099a03d445` |
| `maps343-interactions-preserve-build-2026-10-25/sha256.json` | `05791f2a4033423de2359198b52caf68eba77cdf73c34a13eb3b8c7757d9c549` |

The canonical bundle retains source/compiler closures, generated C, original
inputs, command receipts, runtime logs, PCAP, PNGs and postrun media. Complete
typed readback passed all 43,292 entries; output is retained in the supplement's
`canonical-readback.log`. Root and parent independently passed the same
inventory; the parent's output is
`maps343-completed-own-readback-2026-10-25.log`. The unchanged completechecker290
passed all nine run-envelope files, all 293 preservation-build files and all
303 supplement files. External child receipts are
`maps343-launch-child-readback-2026-10-25.json`,
`maps343-interactions-build-child-readback-2026-10-25.json` and
`maps343-postrun-interactions-child-readback-2026-10-25.json`. An independent
peer passed all supplement files, retaining
`maps343-postrun-interactions-peer-readback-2026-10-25.json`.

The tracked `tests/native-android-ws/maps343-interactions-preserve.v` tool
authenticates the original pins, requires the exact three-file delta and checks
the live and captured files again after copying. Its recorded build retains
the pinned compiler, complete source closure before and after compilation,
generated C, C compiler pin, command arguments and timestamps. That build
precedes preservation; a separate bootstrap compile only invoked build mode.
The complete build bundle is also retained inside the sealed supplement.

Reproduce canonical readback from the repository root with:

```sh
build/android-maps/maps343-run-recorded verify de5e38aa37b28ba99db661d82cf50e20600319c00b6ff735d4e68cf3724a3d3b
```
