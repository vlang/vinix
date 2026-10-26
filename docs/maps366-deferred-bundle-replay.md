# Maps366 deferred Bundle replay

Maps366 reached a tiled map and displayed an Oasis d'Aboukir search suggestion,
then failed after 83 observation seconds because `android.util.TimingLogger`
is missing. Generation, compilation, preparation and independent prelaunch
checks passed. The full 600-second observation and place-details flow did not
complete.

This replay replaces Maps360's Framework359 with
[Framework365](bundle-parcel365-regression.md), which defers Bundle decoding
until access and preserves local Binder references. It targets the application
Parcelable loader failure observed after selecting a search suggestion in
[Maps360](maps360-permission-metadata-replay.md). Framework365 includes the
qualified service361 correction and its complete359 and353 baseline chain.
Native351 and the fortified Loader357 remain pinned.
The separate same-APK Framework365 ART comparison passed its original semantic
checks: old361 reproduced the expected loader exception and new365 emitted all
six markers during its complete 35-second observation. That fixture result
does not establish Maps success.

The generator is `80abf5711`, dedicated receipt wrapper `6aa53f759` and
independent prelaunch checker `981cee168`. The generated source derives from
the authenticated Maps360 runner. Its contract retains the same Maps and
companion APKs, diagnostic launcher, base boot media, callback behavior,
classifier and 600-second observation period. Against baseline350, the runtime
has 109 regular files, with exactly the native SO, framework JAR and loader
changed; the final overlay contains only those three files. The independent
prelaunch comparison confirmed these constraints in the actual prepared tree,
including typed modes and links and all five original base boot members.

All evidence paths below are under
`/Users/alex/.local/state/vinix/android/` unless marked as repository paths.
Generated source, complete inventories and results remain outside Git.

| Host input or result | SHA-256 |
| --- | --- |
| `bundle-parcel365-framework-build-2026-10-26/sha256.json` | `b07a32393f8a3e546819b5053516d3cce8c68238ad9ed27f0ce789e76a6d2d99` |
| Framework365 JAR | `b8b9351c39e28566ba5856bd3b71268e621587c866020d245cd2d738683668aa` |
| Native351 SO | `d3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1` |
| Loader357 | `42c7ac8a276a7eb72a3844e94e182aef8ad7df4c2f8f7313f7061527d077b908` |
| `maps366-generation-2026-10-26/sha256.json` | `4d6f66f506225c2dcee279d82421ba769315c8a25bc453e20d0ded92cad9d7b1` |
| Generated `maps366-run.v` | `fa542ebfe4dd8cf644a5c57dd2349fb9775a3c299830f1aed1813cd4fcf3ee65` |
| Repository `build/android-maps/maps366-run-recorded` | `fdcc5aef72202c1cb62b394ab1db73167c771e08f2ed06445ad6b2a0f5b504cf` |
| `maps366-replacement-pins-2026-10-26.json` | `06fc4455b4a0e2f5f467d6056d354cb0282c9c76bb500b42dd99c8de2625faa7` |
| `maps366-recorded-build-peer-audit-2026-10-26.json` | `214d755212268e424973798c27260015a68c668c6845a26f113d940f2bb2dc7a` |
| Repository `build/android-maps/maps366/launch-pins.json` | `b043cbcd53d8fc218944c0f4ee72215cd5ffdae39a13e5614d26aec2dc688363` |
| `maps366-2026-10-26/prelaunch-sha256.json` | `75b43e3d53c539a233cf8cc17b4cd09b793e97f83b4af804504697f418b75c13` |
| `maps366-prepare-retry1-receipt-2026-10-26/sha256.json` | `576f110d94126538f682d9f85124e3367233fd0276d7edbe58d22e114f02df78` |
| `maps366-check-receipt-2026-10-26/sha256.json` | `5a7bd849771c7df46f55ae7a77141ab11f1df95cb1bb43162d2d8e7825392d7f` |
| `maps366-independent-prelaunch-review-2026-10-26.json` | `4403b9a78b90df4f1bc9192cfc96ed22b6c912116eb8151bc9d15f986ec454c8` |

Generation recorded complete qualification of 32,872 Framework365 files and
2,440 Loader357 files. Framework365 changes exactly four existing source and
DEX classes and adds `android/os/VinixBundleCreator`: 2,074 classes become
2,075, with no removals. Its qualified baseline chain remains complete.

The generated runner's bootstrap compilation ran 01:25:18–01:25:22 UTC on
2026-10-26, exit 0. Root and independent complete readbacks passed all 21 files
in the generation bundle; the retained generation copy also passed complete
readback. The recorded build is retained in
`maps366-run-build-c-2026-10-26`. Its independent audit at 01:28:47–01:28:48 UTC
checked the exact 272-input live and retained compiler closure, source, compiler,
C compiler and recorded binary identities. Discovery, bootstrap and recorded
compilation exited 0, with unchanged input identities. This audit does not claim
an outer build-directory seal or an ART or Maps runtime pass.

The dedicated wrapper accepts only the six exact Native351/Framework365
replacement identities. It filters the same forbidden trace and location
environment keys and records the actual child exit, separately from evidence
collection. Initial preparation exited 1 at 01:34:16 UTC before mutation because
the unchanged 1,536 MiB capacity gate was unmet. Its complete receipt remains at
`maps366-prepare-receipt-2026-10-26`, manifest
`31c8885921dc7ec4d7424206cc8b583ea3df4d8cf35b4e149afcec7f6d1de0d1`.
After separate byte-preserving APK clone consolidation recovered capacity,
fresh preparation ran 01:39:19–01:40:52, exit 0. The launch check ran
01:41:03–01:41:55, exit 0. Both receipts record unchanged input pins, 50 clean
environment entries and no forbidden keys.

Independent prelaunch review ran 01:41:11–01:41:53, exit 0. It requalified the
complete Framework365/361/359/353 chain and Native351/Loader357 builds and
confirmed unchanged APK identities, classifier and 600-second setting.

## Application observation

Root owns all guest/QMP actions. The genuine `google-maps-running.png`, captured
at 01:43:24 UTC, shows tiled North America with search, map controls and Explore
UI. Root and this reviewer visually checked it. At 01:44:06,
`oasis-search-typed.png` shows the query `Oasis d Aboukir Paris` and the suggestion
`Oasis d'Aboukir`, `Rue d'Aboukir, Paris, France`; this reviewer also visually
checked it. Root selected the suggestion at 01:44:21. A subsequent result
capture failed after the QMP socket disappeared. No place details, directions
or navigation success is established.

Serial line 12499 reports `ANDROID-WS-FAIL main looper`. At 12509,
`NoClassDefFoundError` identifies `android.util.TimingLogger`, with GMS frames
`cqmw.v`, `craa.a`, `craa.k` and `cqzx.run`; line 12522 gives the nested
`ClassNotFoundException`. Line 12524 records
`APK-SUITE-EXIT id=google-maps code=1 native_observed=true gtk_x11_absent=true`.
The previous exact Thing class-loader exception and permission-field exception
are absent in this run; this does not prove the complete Maps Bundle flow.

The raw result records `backend_ready=true`, `native_maps_observed=true`,
`observation_elapsed_seconds=83`, `process_exited=true`,
`functional_passed=null` and `outcome="startup_failed"`. The classifier and
600-second limit remained unchanged; process failure ended observation early.
The wrapper ran 01:42:09–01:45:27 UTC and exited 0 with unchanged input pins,
50 clean environment entries and no forbidden keys. Collection succeeded;
the application failed.

Screenshots, interaction log, serial and raw results are retained under
`maps366-2026-10-26/results/attempt366/`. The independent original runner
readback ran 01:49:34–01:50:10 UTC, exit 0, and checked all 124,092 typed
entries. Repository tool `tests/native-android-ws/maps366-completed-readback.v`
retains its source, binary, exact argv, actual status and stdout under
`maps366-report-peer-readback-2026-10-26`. Original runner, source and canonical
manifest hashes were unchanged before and after verification.

| Final retained evidence | SHA-256 |
| --- | --- |
| `maps366-2026-10-26/sha256.json` | `06275b99ad6cb5581800de65ed9604ac7677f7890f872cb41c7bce70a24552c0` |
| `maps366-run-receipt-2026-10-26/sha256.json` | `86d9008f3cd14574e0679f43250ac8e603761badc1e7113811d17af4ed3d7a5d` |
| Retained `google-maps-running.png` | `74cde2a772100f012dbcf68e421bc1f16cfda8f9263ecae6105a376edbbe82c5` |
| Retained `oasis-search-typed.png` | `7eacfe8311dcd979ee9fccb5f61f8e704ecfa7316de91a1c82a86665486cb81a` |
| Retained serial | `2a591e28c91d5405ea811aa3c9b6a80e983cbe31177b21bc04ef5bf689b4d3d4` |
| `maps366-report-peer-readback-2026-10-26/receipt.json` | `b3037911a68bc24c4a57e2168faf8eaf57fbf9155c7e33ab666192809ef0a4fe` |
