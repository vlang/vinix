# Widget geometry paired regression

Compound266 passes the paired guest geometry regression. Baseline262 fails
`relative padding measured width` at actual14 versus expected54 before
its first PASS marker. Fixed266 logs `BOOTSTRAP-PADDING-RELATIVE-PASS`,
`BOOTSTRAP-CHIP-GEOMETRY-PASS`, `BOOTSTRAP-TEXT-MINHEIGHT-PASS`,
`BOOTSTRAP-WIDGET-GEOMETRY-PASS` and `BOOTSTRAP-READY`, then remains alive
for the full 30-second observation without an assertion failure or exit.

Both original suite rows retain `startup_failed` and
`functional_passed: null`. Fixed266 has `backend_ready: true` and
`process_exited: false`; its only failure markers are the existing
`Main.bB`/`Lnge;` `NoSuchFieldError` and `ClassNotFoundException: nge`.
The checker accepts only their two complete observed lines and preserves
the original classifier. Guest assertion success is reported separately.

The fixture checks measured text width and Canvas offsets, inherited and
explicit RTL, absolute-padding override, neutral styled button geometry,
pixel-versus-line height modes, independent View minimum height and
measure-spec clamps. It does not replace the sealed262 styled-button test.

The complete bundle is independently retained outside Git at
`/Users/alex/.local/state/vinix/android/compound266-2026-10-24`, with
independent prelaunch and completed trees, raw streams, screenshots,
private media, exact source/tool closures and actual build/run receipts.
Complete inventory SHA-256:
`78172b16a4fb4e2630e15d66bc4e46b3b9bf19e879a19bb1891fc36ba05b3f56`.
The earlier frozen264 framework build failed with `unexpected View
measurement padding entry`, before native/APK compilation or any VM run.
Its entire build/input tree and actual exit-1 receipt are independently
retained at `compound264-2026-10-24/failed-build` under the same external
parent, with `failed-build-sha256.json` inventory
`b16e238d9d436883d368d8d333d51e3ff97e4c416aa4c77db23e203e6101b1fe`.
This is build-failure evidence with no passing semantic seal.
The baseline for the fresh266 pair is `baced0adb`, framework
`a37ffeceffd29e7bd5db825e079949f5a6e3f71dd04edba8c61239bd1971b71c`
and native
`3bbc2d9439961be351f18e391f305ded393d7a10b67f1cf2e80adad2a6569b80`.

Fixed source revision: `ad65b2828e495fb33c0faf682c9e0d155f9dadce`
(`Android: resolve relative padding and text minimum height`). Both runs
use the actual signed APK
`0c4e769f017557a34b8c57568d6b52e416cb0a59d1137b6368f3c2bdcc3f69e7`.
Fixed266 uses framework
`69f560aef5965acd2e4c1eba35a545dae5c8e48708695b0c747a1267d75643c3`
and native
`0a9928b59585bc7e1d6518c22a9a388f5bb99e4f43f3c0838d6c1c47588fb680`.

The new checker requires complete 125-file framework and 83-file native
maps and exact texts. Framework changes are bounded to
`framework_view_geometry`, `framework_view_canvas` and
`framework_text_widgets`. Native changes are bounded to `WsView`,
`ws_measure` and four exact TextView binding rows; existing generated JNI
wrapper names and signatures remain fixed. The native library is rebuilt.
All common native files and initial boot/EFI media match within the
pair. Full staged host module files are checked; no paired FAT or guest
memory readback is claimed.

The auditor source is
`e866b38512a8bc294edd62ab09bb5810a5e4189d6756e115b6533d9f9326c3e6`,
binary `5bd1e77d488e733a9cbdb53a7b93db971aa77bfa579a92d8cc0ab3058f61335f`.
Its actual compilation receipt and compiler are frozen inside `audit/`
before sealing. Strict semantic sealing, the independent pinned full
recheck of 6975 entries, authentic partial-bundle and wrong-pin rejection,
and the final `-prod` refusal passed.
Historical checkers and sealed262 evidence remain unchanged.

Recheck the complete bundle with its retained executable:

```sh
/Users/alex/.local/state/vinix/android/compound266-2026-10-24/audit/compound-geometry-evidence check \
  /Users/alex/.local/state/vinix/android/compound266-2026-10-24 \
  78172b16a4fb4e2630e15d66bc4e46b3b9bf19e879a19bb1891fc36ba05b3f56
```
