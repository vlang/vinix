# Maps345 touch-delegate replay

Maps345 passed onboarding, rendered the map, opened Paris with two loaded
photos, displayed Attractions results and opened Jardin d’Acclimatation details.
The place sheet shows its French name, 4.3 stars (20,717 reviews), category and
opening hours; its large image area remains blank. A later render exited Maps
with missing `android.text.style.SuperscriptSpan`. The previous
`View.getTouchDelegate()` failure does not recur. This is progress through the
place layout path, not a complete Maps compatibility result.

The qualified framework source is
`4daf1e4fb6005a820bb34a0ab47276dfbfb291db`
(`Android: implement touch delegates for Maps controls`). Its JAR SHA256 is
`12c5d03030f5f081415bda5c51e32279e70a17aead822c06925512ed6226ef8f`.
Derivation tooling is committed at
`3e8a2e5ac4cde0068f05b87c18eedf976ea3483d`; generated-runner and wrapper tooling
is committed at `290ea78adaebec7c01151b9ffc2c901057b27698`.
The JAR is the sole changed entry among the authenticated Maps335 prelaunch
runtime's 109 files. The other 108 files, native332 payload, diagnostic launcher,
kernel, base media and original classifier remain unchanged.

All times are UTC on 2026-10-25. The recorded envelope ran 17:47:49–17:51:12
and started QEMU at 17:48:15. It exited 0 and records unchanged input pins,
50 clean environment entries and no forbidden environment keys. The requested
observation limit remains **600 seconds**; the unchanged classifier records
**125 seconds observed**, `startup_failed`, `process_exited=true`,
`backend_ready=true`, `native_maps_observed=true`,
`qemu_alive_before_capture=true` and `functional_passed=null`. Maps exited 1.
Successful evidence collection does not change that functional failure.

Paths below are relative to `/Users/alex/.local/state/vinix/android/`.
Actual QMP PNGs, input receipts and logs are retained under
`maps345-2026-10-25/results/attempt345/google-maps/`:

| Time | Observation | PNG | SHA256 |
| --- | --- | --- | --- |
| 17:48:50 | Rendered map after Skip | `map-probe.png` | `a74d903e1528c7374f32f5eb0630b1b129bc32192d3660bd270fa27522189d9e` |
| 17:49:29 | Paris map, place sheet and two loaded photos | `paris-place.png` | `b3ca08cbf159191731a3bad7b05913fa7d4eb99dcbb051c52b86a42beb546ee0` |
| 17:49:50 | Attractions filters and Jardin d’Acclimatation result | `attractions-loaded.png` | `85276467a6275eea536cb8aef06c6f0cad7d25b163c7e8109dd20e9209d28d58` |
| 17:50:14 | Jardin d’Acclimatation details; blank image area | `attraction-place.png` | `35f3b45f7649dbfb296c99b63d4055a51822dc38980ca996d73ba41aad828ab7` |
| 17:50:28 | Launcher reports that the Android APK exited | `application.png` | `b0d0b74dcb2930a5b49aa39bd6e514c9318e3757bf45ab68f73c2764fb7c468a` |

`interaction.log` records Skip at 17:48:35–36, Paris suggestion selection at
17:49:13, the Attractions click at 17:49:32 and the result-row click at
17:49:54. All five PNGs above were visually reviewed. Serial lines
232230–232237 show `ANDROID-WS-FAIL input or render`, the `SuperscriptSpan`
`NoClassDefFoundError` at `ashh.<clinit> → ashh.a → atze.a → bgzb.h`, a JNI
warning timestamped 17:50:26 and the APK exit. No successful Directions result
was established.

| Retained artifact | SHA256 |
| --- | --- |
| Qualified `touch-delegate344-2026-10-25/sha256.json` | `f900b1506d71bb6d6560a6729031b3965274d5c5a50d3b2cab753c5d110b4501` |
| Generated `maps345-generation-2026-10-25/maps345-run.v` | `bc3114a6707e7e7ea7bf9049143c18cc9cb09917f6b38f045fb6a20f82c2a9a8` |
| Recorded `build/android-maps/maps345-run-recorded` runner | `9084d8c5d67dd2143cb27570ca811aaf1dcae9f3aa641dd5a928232511ac49e9` |
| Launch pins | `4b1434e069fbd80282d2e688eab8708455a54f18c963911365947765cd738d4f` |
| Prelaunch typed manifest | `dc00867ec4b2dc69291196faf439e776daa288d054d60bb339434729c23202cf` |
| Preparation envelope manifest | `f6756ce44351a3e0a380ffc99880502930306518fc871d276c6ca94bfc45b7bc` |
| Run envelope manifest | `ee04d21b2397313c6d8eb56e7116ca53e87e69d69abd1d60582de1e8b597338f` |
| Canonical `maps345-2026-10-25/sha256.json` | `68fd3029c52f90e4ad3616084bb827225db5ab8fe595736bde5c61d898fdae57` |
| `maps345-results-compare-build-2026-10-25/sha256.json` | `ddabc55b5f5af6160a9ea41028e4b6d38807c03fd7dfbe192b70f9a7634a67cb` |
| `maps345-results-comparison-2026-10-25/sha256.json` | `9f58f60463a9f76bf6053bed8653e4e20fd58769b11e0745c8ea0fac1f58ae86` |

The canonical bundle retains source/compiler closures, generated C, original
inputs, command receipts, runtime logs, PCAP, PNGs and postrun media. Complete
typed readback passed all 43,316 entries; output is retained in
`maps345-results-comparison-2026-10-25/canonical-readback.log`. The unchanged
completechecker290 passed all nine run-envelope files, all 293 comparison-build
files and all 299 comparison-evidence files. External receipts are
`maps345-launch-child-readback-2026-10-25.json`,
`maps345-results-compare-build-child-readback-2026-10-25.json` and
`maps345-results-comparison-child-readback-2026-10-25.json`.

The tracked `tests/native-android-ws/maps345-results-compare.v` tool
authenticates the original canonical, envelope and runner pins. It compares the
complete live and captured application trees twice, including file hashes,
directory entries, modes and symlink targets. All 94 typed entries agree, with
no sockets or differences. Therefore no late interaction supplement is needed.
Its separate evidence bundle records both inventories and retains the complete
recorded build: pinned compiler, source closure before and after compilation,
generated C, C compiler pin, command arguments and timestamps. That build
precedes comparison; a separate bootstrap compile only invoked build mode.
The original canonical, envelope and live paths remain unchanged.

Reproduce canonical readback from the repository root with:

```sh
build/android-maps/maps345-run-recorded verify 68fd3029c52f90e4ad3616084bb827225db5ab8fe595736bde5c61d898fdae57
```
