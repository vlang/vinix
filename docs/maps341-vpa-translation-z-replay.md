# Maps341 ViewPropertyAnimator translationZ replay

Maps341 passed onboarding, rendered the map, opened Paris with a loaded photo,
and displayed Attractions filters and the Jardin d’Acclimatation result. Selecting
that result exited Maps with a missing `android.text.style.LocaleSpan` class.
The category transition now completes; this replay does not establish complete
Maps compatibility.

The qualified framework source is
`7818102b4221a68c3a32fb4983300936ee9ad7d8`
(`Android: animate View translationZ for Maps transitions`). Its JAR SHA256 is
`df8601f61867c276559c1799957865ef51a65b4cb8b343b848f2fca6370f16a7`.
Derivation tooling is committed at
`b6ae57b2eb6f18d43e268afb24ee977ab6ca4f8f`; generated-runner and wrapper tooling
is committed at `2544083cf62a60e27e4931eba62f6b9e333cacb5`. The prepared source
revision is the framework revision above, distinct from these tooling commits.
The JAR is the sole changed entry among the authenticated Maps335 prelaunch
runtime's 109 files. The other 108 files, native332 payload, diagnostic launcher,
kernel, base media and original classifier remain unchanged.

All times are UTC on 2026-10-25. The recorded envelope ran 17:00:57–17:04:01
and started QEMU at 17:01:24. It exited 0 and records unchanged input pins,
50 clean environment entries and no forbidden environment keys. The requested
observation limit remains **600 seconds**; the unchanged classifier records
**118 seconds observed**, `startup_failed`, `process_exited=true`,
`backend_ready=true`, `native_maps_observed=true`,
`qemu_alive_before_capture=true` and `functional_passed=null`. Maps exited 1
after the row selection. Successful evidence collection is separate from this
functional failure.

Paths below are relative to `/Users/alex/.local/state/vinix/android/`.
Actual QMP PNGs, input receipts and logs are retained under
`maps341-2026-10-25/results/attempt341/google-maps/`:

| Time | Observation | PNG | SHA256 |
| --- | --- | --- | --- |
| 17:01:46 | Rendered map after Skip | `map-probe.png` | `3051d023801436668300f6952155b929b136227284345fc47021b1430894a53e` |
| 17:02:28 | Paris map, place sheet and loaded photo | `paris-place.png` | `42fb659e9a87f942501633eed0556087de1b6d27d6b27701c107f668d93df298` |
| 17:03:21 | Attractions filters and Jardin d’Acclimatation result | `attractions-loaded.png` | `219d48e4011a3c9751d754fab4963f5378efacfcd1ce5703a30fac47e0d691bf` |
| 17:03:29 | Launcher reports that the Android APK exited | `application.png` | `59729b9258d4ff8929335ce9f7ef06cf74174ed343ee5f611012815451dcb31b` |

`interaction.log` records Skip at 17:01:40, Paris suggestion selection at
17:02:05–06, the Attractions click at 17:02:32 and the result-row click at
17:03:26–27. `attractions-early.png` already shows category content at 17:02:40.
The transition Future records `done=1` at serial lines 13638 and 14648 without
the Maps339 missing-method failure. Serial lines 15968–16105 instead show
`ANDROID-WS-FAIL input`, `NoClassDefFoundError` for `LocaleSpan` and its
`ClassNotFoundException` cause. The screenshots were visually reviewed.

The root's later 17:03:48 screenshot request failed with exit 1 after automatic
collection had copied the results; it produced no `attraction-place.png`.
The separate `maps341-postrun-interactions-2026-10-25` supplement preserves the
complete live `interaction.log` and the late
`command-31697-1792947828378140000-15208.{stdout,stderr}.log` pair. Its scope
records exactly those three file differences and the two appended interaction
lines. The original canonical bundle and launch envelope were not altered.

| Retained artifact | SHA256 |
| --- | --- |
| Qualified `vpa-translation-z338-2026-10-25/sha256.json` | `c8e780dfd7439d8f85a3f8abd70a43f78a53652128d489adbfec5e5079aeaaf2` |
| Generated `maps341-generation-2026-10-25/maps341-run.v` | `a700ff1314b76ef2810bd6ca553a90db728868e7df1e44963e6ab3f8cb921d54` |
| Recorded `build/android-maps/maps341-run-recorded` runner | `510307806f3453ec28fff359343da2fa1a871ea427406f8c8442840a807fee69` |
| Launch pins | `875da3de5e2ed5a1b1a091f9d517a7299e594f9a73f38f4aa72217ac0756d30d` |
| Prelaunch typed manifest | `fb0acd58db4ba7d29ca473d9d28269c42059531ea268c64a52870bf029597160` |
| Preparation envelope manifest | `19b11af20d452d04e211a29a60a34c313a740599a65ea670a3250135f9898d9f` |
| Run envelope manifest | `3481188c5ea7eb2fdc666fdaeebe7acc11b7e1b310ca207e19e9e8726895f852` |
| Canonical `maps341-2026-10-25/sha256.json` | `a94fe6dcf84d7104ad767e5173b183629519a9b271a7bc6a94209b9e58a724bb` |
| Late-interaction supplement manifest | `9c7210cd5cc7b630b60e5c691c300692870c2dfa9e179aa4ee6b14ece9b0fc9b` |
| `maps341-interactions-preserve-build-2026-10-25/sha256.json` | `1887b90efc9aca47be61d2f71529d9cd9a55dfe136be9e76b51a211f7a6a6a59` |

The complete canonical bundle retains source/compiler closures, generated C,
original inputs, command receipts, runtime logs, PCAP, PNGs and postrun media.
The recorded runner's complete typed readback passed all 43,194 entries; its
output is retained in the supplement's `canonical-readback.log`. An independent
peer passed the same inventory, retaining
`maps341-completed-peer-readback-2026-10-25.log`. The unchanged completechecker290
passed all nine run-envelope files, all 293 preservation-build files and all
303 supplement files. External receipts are
`maps341-launch-child-readback-2026-10-25.json`,
`maps341-interactions-build-child-readback-2026-10-25.json` and
`maps341-postrun-interactions-child-readback-2026-10-25.json`.

The tracked `tests/native-android-ws/maps341-interactions-preserve.v` tool
authenticates the original canonical and envelope pins before preservation,
requires the exact three-file delta and checks live and captured files again
after copying. Its recorded build retains the pinned compiler, complete source
closure before and after compilation, generated C, C compiler pin, command
arguments and timestamps. That recorded build precedes preservation; the
separate bootstrap compile only invoked its build mode. A copy of the complete
build bundle is retained inside the sealed supplement.

Reproduce canonical readback from the repository root with:

```sh
build/android-maps/maps341-run-recorded verify a94fe6dcf84d7104ad767e5173b183629519a9b271a7bc6a94209b9e58a724bb
```
