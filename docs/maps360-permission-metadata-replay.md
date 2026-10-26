# Maps360 permission metadata replay

Maps360 reached the map screen and displayed an Oasis d'Aboukir search
suggestion, then exited after 92 seconds with a new Parcelable class-loader
failure. The [permission metadata fix359](permission-info359-regression.md)
removed the previously observed permission exception. This replay uses
Framework359 with Native351 and the fortified Loader357 from
[Maps358](maps358-fortified-loader-replay.md). The separate service teardown
correction is not included.

The permission fix is `2390bacfe`; the replay generator is `d0cbc0110`, independent
prelaunch checker `b5fba8669` and dedicated receipt wrapper `3626a9254`.
The historical receipt332 wrapper remains unchanged. The new wrapper checks the
exact six qualified Native351/Framework359 identities before creating a prepare
receipt, retains environment filtering and records the actual child exit code.
Its recorded build and rejection tests passed complete bundle readbacks.

## Preserved inputs and preparation

The runner retains and qualifies the complete Framework359 bundle, including
its Framework353 baseline. Framework359 changes only PackageManager among 2,073
classes and adds or removes no classes. Native351, Loader357, Launcher334, Maps
and companion APK identities remain pinned. Against baseline350, the runtime has
109 regular files with exactly the native SO, framework JAR and loader changed;
106 files are unchanged. The final overlay contains exactly these three files.
Typed modes and links, all five base boot members and the original classifier's
600-second observation setting remain unchanged.

All evidence paths below are under `/Users/alex/.local/state/vinix/android/`
unless marked as repository paths. Generated results, screenshots and complete
inventories are retained outside Git.

| Prepared input | SHA-256 |
| --- | --- |
| Framework359 complete build manifest | `7a2ae7763e71f702ccc1a50b3b63cf444a0e37d8b6a800e77c80866d3ba9dccc` |
| Framework359 JAR | `88fdf06964bfbd3815d824ab5ff5517887e58de3eb3eb47986d99806fbe6c2fc` |
| Native351 SO | `d3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1` |
| Loader357 | `42c7ac8a276a7eb72a3844e94e182aef8ad7df4c2f8f7313f7061527d077b908` |
| `maps360-generation-2026-10-25/sha256.json` | `5ff5ebd831a7c79b85162e523e71e86a1004215b3c9ea1c93686c36332da2196` |
| Generated `maps360-run.v` | `411459a52088d35632c5ac9a0ca72e31e518c355ab3a4b9cf060287cf13a957f` |
| Repository `build/android-maps/maps360-run-recorded` | `16632425ff6f75eed95758cb7135fe5882da8bcb5d57897308d22723d7b0a2fc` |
| Repository `build/android-maps/maps360/launch-pins.json` | `6a2cec5db005590a0ff972898749497faa7f5a7068fcd9a954cf6f3fd7c4af9a` |
| `maps360-2026-10-25/prelaunch-sha256.json` | `fad4136ab6e3613d4d25c2d5ceb49201369ff05ad9899e4bba976208753236b6` |
| `maps360-prepare-receipt-2026-10-26/sha256.json` | `c8f6fc222c250dad329ae6a2c64ccb496a28fbeecc671d20c9e56410d72b941b` |
| `maps360-check-receipt-2026-10-26/sha256.json` | `98ad77201808d861720937b01da2d0b1cb69b36e4620cd42e54e627b2d540dd6` |
| `maps360-prelaunch-peer-review-2026-10-26.json` | `7365064e48b7920dad697659eabfca3e35687efe3948f9c3cd861cda29546366` |

Generation and runner compilation exited 0. Root and independent complete
readbacks passed the 21-file generation bundle and its runner-build clone.
Preparation ran 00:11:21–00:13:08 UTC on 2026-10-26 and exited 0. Root's complete
readback passed all nine files in the sealed receipt. The receipt records
unchanged input pins, four clean environment entries, no forbidden keys and an
empty removed-environment list.

The runner's launch check ran 00:13:23–00:14:11 UTC and exited 0 with the same
receipt invariants. An independent complete readback passed its nine-file sealed
receipt, `maps360-check-receipt-report-peer-readback-2026-10-26.json`.

The independent prelaunch review completed at 00:13:33 UTC, exit 0. Its receipt
`maps360-prelaunch-peer-review-2026-10-26.json` confirms exact typed inventories,
the runtime and overlay constraints above, boot member hashes, unchanged APK
inputs and the unchanged classifier and observation duration.

## Application observation

The raw result records backend, launcher and native Maps observed, with
`observation_elapsed_seconds=92`, `process_exited=true`, `functional_passed=null`
and `outcome="startup_failed"`. The 600-second limit was unchanged; process exit
ended observation early. Serial line 12535 reports
`ClassNotFoundException: com.google.firebase.appindexing.internal.Thing` on the
`GoogleApiHandler` thread. Its DexPathList contains only `api-impl.jar` and
`framework-res.apk`; `Parcel.readParcelable`, `readValue` and `readBundle` appear
in the stack. GMS subsequently calls `Process.killProcess` on itself. The final
marker at 13893 is `APK-SUITE-EXIT id=google-maps code=0 native_observed=true
gtk_x11_absent=true`. That exit code does not establish application success.

The previous `PermissionInfo.protectionLevel` exception and fatal service
teardown exception are absent. `IndexWorkerService onDestroy` runs on `main`
at line 12562 in this replay; it does not exercise the earlier failing teardown
thread path or establish that its separate defect is fixed.

Root owns all guest/QMP actions. Root and this reviewer visually checked
`google-maps-running.png`, captured at 00:15:53 UTC on 2026-10-26: the live Maps
window displays North America, search and map controls. At 00:16:36,
`oasis-search-typed.png` shows the query `Oasis d'Aboukir Paris` and the suggestion
`Oasis d'Aboukir`, `Rue d'Aboukir, Paris, France`. Root selected the suggestion
at 00:16:44. The automatic `application.png` at 00:16:52 says
“The Android APK has exited.” No place details, directions or navigation success
is established. The earlier `oasis-search-result.png` shows an empty search
screen despite its filename.

Screenshots, interaction log, serial and raw result are retained under
`maps360-2026-10-25/results/attempt360/`. The wrapper ran
00:14:27–00:18:13 UTC and exited 0 with unchanged pins and the same environment
invariants as preparation. Root's complete readback passed its nine-file run
envelope. Collection and qualification passed; the application failed.

Root and independent original runner readbacks both exited 0 and checked all
84,812 typed entries. The independent readback preserved the runner and manifest
identities before and after; its adjacent log and receipt are
`maps360-report-peer-readback-2026-10-26.log` and
`maps360-report-peer-readback-2026-10-26.json`. The run envelope's complete
readback receipt is `maps360-run-receipt-root-readback-2026-10-26.json`.

| Final sealed evidence | SHA-256 |
| --- | --- |
| `maps360-2026-10-25/sha256.json` | `591cdedd2514425b7f53e565d1550d3d261a66aeef92792eda3028d44b2b7068` |
| `maps360-run-receipt-2026-10-26/sha256.json` | `d297b9d53cbf1228d7f4755669e8839e3c5923708eb9b3b494fa49efd0c2ce48` |
| Independent canonical readback log | `e6c5ced78870aa22b27ae07321324a29e5b82defb2cd21d42c260a646a022390` |
| Independent canonical readback receipt | `86db30f0d4f996e3852ffc74018281a90d8522bc53c2e9fec213273f64f2baa4` |
| Retained `google-maps-running.png` | `6e238a803cf85f7b811f1e42421a4f3406b01b23144a52c05d76c801de27f6a9` |
| Retained `oasis-search-typed.png` | `1ad9ace6e266b449708eabc95283300a85e5ef30890a075f5b234c99bf03ed21` |
| Retained serial | `92a2ecce1fc9040588997c4cceef6563f92073e1c6224aac9f22a234861d74ef` |
| Retained final `application.png` | `20ad6ca8e995bf15ed0c2b650ed1b6e5e072a7eabc0492cb7782121a6eb0dc36` |

## Redundant working copy cleanup

`tests/native-android-ws/maps360-working-cleanup.v` removed only the repository's
`build/android-maps/maps360` and `attempt360` working directories on 2026-10-26.
It first revalidated all 84,812 canonical typed entries and their pinned manifest,
then compared the working copies twice: 390 typed entries for Maps360 using the
authenticated postrun VM, and 84 for attempt360. The latter includes three exact
late failed-details-capture files retained separately: the updated interaction
log and command64536 stdout/stderr. No historical checker or canonical seal was
changed. Its hash/type/mode/file-set rejection test passed; a production build
refused execution before inspecting or removing any tree.

Consumed V source, executable, late files, qualification and completion receipts
are retained in `maps360-working-cleanup-2026-10-26`. The tool sealed and read back
that complete sidecar; manifest SHA-256 is
`4e40636f7d03425100700f431346dcb3723f88949927307dbf2a895f122de3f8`.
The original canonical manifest remained `591cdedd…2b7068`. Cleanup ran
00:30:31–00:31:18 UTC, exit 0. Available space was 1,167,256 KiB before and
1,138,016 KiB after; removing cloned working copies did not establish physical
space recovery amid concurrent work.
