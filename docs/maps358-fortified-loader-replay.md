# Maps358 fortified-loader replay

Maps358 advances past Maps356's missing `__pwrite_chk`: Icing's native index
initializes, then Maps crashes after 73 seconds in Google Play Services permission
handling and service teardown. The original classifier reports `startup_failed`.
Individual fortified-wrapper calls and the runtime-loaded binary hash were not
traced; initialization progress does not prove a functional pass.

The fix is `e514fcc3c`; standalone builder `34dd0143c`, replay generator
`a3b91107a` and prelaunch checker `0ad482718` are committed. The
[host regression](pwrite-fortify357-host-regression.md) records ABI/write tests;
the [build report](pwrite357-loader-build.md) records source closure and exports.

Native351, Framework353, Launcher334, baseline350, APK identity and the original
600-second classifier retain their [Maps356 qualification](maps356-attraction-input-replay.md).
The 109-file runtime differs from baseline350 at exactly the native SO, framework
JAR and loader; 106 files are unchanged. The final overlay has those three members.
Five base boot members, modes/links and external APK inputs remain unchanged.
The loader overwrites the existing path
`opt/vinix-android-aarch64/usr/lib/art/native-ws/libdl_bio.so.0`, mode 0755.

All artifact paths below are under `/Users/alex/.local/state/vinix/android/`
unless explicitly marked as repository paths. The complete loader bundle is
`pwrite357-loader-build-2026-10-26`; payload `loader/libdl_bio.so.0` is 152,312
bytes. Root's complete readback passed all 2,440 files. The runner retains the
complete bundle and qualifies it at preparation, launch gate and post-run.

| Immutable evidence | SHA-256 |
| --- | --- |
| Loader build `sha256.json` | `1aa6d2ad417643229430e3b9b13333b5c0843ed1c81faccc41dde402c0b91561` |
| Loader payload | `42c7ac8a276a7eb72a3844e94e182aef8ad7df4c2f8f7313f7061527d077b908` |
| `maps358-generation-2026-10-25/sha256.json` | `162f542e44517b2a626a938b3bfca5d8dffbd881bafd1eef4d94f904551d5240` |
| Generated `maps358-run.v` | `9ec0bb2b3cdd870edbfdfae1505a01e5230d5570791ed1fd6365fedd15b6a7f7` |
| Repository `build/android-maps/maps358-run-recorded` | `12f803034d60071337d4caf3cba133ed5ccb5cfc5490a5ccbcea06ffcd68158b` |
| Repository `build/android-maps/maps358/launch-pins.json` | `c96bee6f0a53b1b22c571a440da145e5f8808cb1b42df093f476998f73c375a6` |
| `maps358-2026-10-25/prelaunch-sha256.json` | `cbd41915d8d0ee3607a5ad9b668c24fc054ffe22a1bb43e9480b39bf7c695de0` |
| `maps358-preparation-receipt-2026-10-25/sha256.json` | `775ab8a175c7970bedd7c65421058c59405421cb1dd4773253a56de6b0a56ccb` |
| `maps358-check-receipt-2026-10-25/sha256.json` | `cb83945a96a9ba9656f72a93730f0d263c7e82850890754a8f25ae76efa60956` |
| `maps358-prelaunch-peer-review-2026-10-26.json` | `9a911e46adb27f40f5daa300d8070c1cf78372588ada61d278d580f22f34c29c` |

Generation and runner compilation exited 0. Independent complete readbacks passed
the 21-file generation bundle and its runner-build clone; source guards are preserved.
Preparation ran 22:55:52–22:58:09 UTC on 2026-10-25, exit 0; check ran
22:58:37–22:59:46, exit 0. Root complete readbacks passed both nine-file receipt
envelopes. Their receipts record four clean environment entries, no forbidden
keys, unchanged input pins and an empty removed-environment list. Independent
prelaunch review exited 0 at 22:58:50 and checked the complete typed inventories,
109 runtime files, exact three-member overlay, boot members and preserved inputs.

## Captured failure

The raw result records backend, launcher and native Maps observed, but
`observation_elapsed_seconds=73`, `process_exited=true`, `functional_passed=null`
and `outcome="startup_failed"`. Its two markers are `ANDROID-WS-FAIL main looper`
and `APK-SUITE-EXIT id=google-maps code=1 native_observed=true gtk_x11_absent=true`.
Serial lines 11071/11077/11078 show native index initialization and `Init done`.
Line 11134 logs a null `PermissionInfo.protectionLevel` access; index-manager
initialization fails. Service `onDestroy` then throws `IllegalStateException`,
reaches the fatal main looper at 11208 and exits 1 at 11240. Two earlier GMS
finalizer exceptions at 3844/4468 also remain. The missing-symbol marker is absent.

Root owns all guest/QMP actions. Root and this reviewer visually checked
`oasis-search-result.png` (23:03:00 UTC): Oasis d'Aboukir, Paris, France. Root
selected it at 23:03:04. The automatic `application.png` at 23:03:12 says
“The Android APK has exited.” A later details capture failed after guest exit;
no details, directions, transit, photos or navigation success is established.
Screenshots and serial are retained in `maps358-2026-10-25/results/attempt358/google-maps/`.

The receipt332 wrapper ran 23:00:37–23:05:02 UTC on 2026-10-25, exit 0.
Collection and qualification passed; the application failed. Root checked the
complete nine-file run envelope. Root and independent original runner canonical
readbacks both exited 0, checked all 69,594 typed entries and
left the manifest unchanged. Logs are `maps358-root-canonical-readback-2026-10-26.log`
and `maps358-codec-peer-readback-2026-10-26.log`; the peer receipt is below.

| Final sealed evidence | SHA-256 |
| --- | --- |
| `maps358-2026-10-25/sha256.json` | `4f28d582546c63a2bef796ee01510b01659e6c74979ff30907bac37df14e1cfa` |
| `maps358-run-receipt-2026-10-25/sha256.json` | `06d4db2b88d64cae35ca8ad2716f527fb80f3b124c79e7a9d2b039e5f54cf821` |
| Root and peer canonical readback logs | `7aae88a14bc4b6616d0e6397eac3fec1a01721e75fc339415a709b532fb3267f` |
| `maps358-codec-peer-readback-2026-10-26.json` | `29becc99b148184502744e9366f2ee3900655036b8ada880b193f5d5f549ceb3` |
| Retained final `application.png` | `d5ec02aa64b85fd98f8576e78ce82e137c9dc02c6e3c79e70a07e416d44f0835` |
