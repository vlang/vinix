# Intent URI ART regression 371

Framework 371 makes `Intent.getDataString()` return null when no data URI is set,
fixing the [preserved 369 regression failure](intent-uri369-regression.md).
The [provider change](intent-uri371-provider.md) is `efac8e8a9dae0259caeb1fd735563485108b9d78`.
The fixture
remains unchanged at `cac9f6367c79fc7de92deb45809502798ddcb123`, source SHA-256
`c992874027c12aa7d7125246754a646749de01d7ea4034db0d7a3a150e27f36c`.

The fresh actual ART guest emitted `INTENT-URI-BEGIN`, all eight ordered phase
pass markers and `INTENT-URI-PASS`. The suite ran
04:16:50–04:17:54 UTC on 2026-10-26 and exited 0. Its raw result is `window_observed`,
35 seconds observed, `process_exited=false`, `qemu_alive_before_capture=true`
and no failure markers. The original `functional_passed=null` classifier is
preserved. The old367 result is retained evidence from 369, with its exact
direct static-method error and ordered application frames before guest exit 1.
The complete recorded new action, including the post-run input and semantic
checks, ran 04:13:46–04:22:00 UTC and exited 0.

The recorded seal ran 04:22:27–04:33:49 UTC and exited 0 after repeating both
semantic checks and matching the stable input map. The immutable 52,181-file bundle is
`/Users/alex/.local/state/vinix/android/intent-uri371-fixture-2026-10-26`,
manifest SHA-256
`114d7d29f0fa7126b5982870a321d349e87ee8d3e8d6737e6a65731320d49929`.
The actual prepare/new/seal commands, before receipts and output logs are
retained beside it under `intent-uri371-fixture-{prepare,new,seal}-2026-10-26`.

The sole independent final reader, committed at `b22ef7673`, exited 0. Its
pinned original290 checker verified all 52,181 files and their hashes at
04:34:09–04:40:36 UTC. The complete normalized runtime config, unchanged signed
APK, JAR-only native delta, verbatim semantic oracle, canonical retained-control
map and original historical paths all passed. It checked 683 closure entries
(270 fresh and 413 historical). The complete receipt is
`/Users/alex/.local/state/vinix/android/intent-uri371-art-peer-readback-2026-10-26/complete-receipt.json`,
SHA-256 `a210290f00446729ee9c62af46a2f927bed755e934cb1e997ea76a8792dfaa16`;
its actual `command.json` is
`2cd8a696e698e661cfda0b9b5dd74d17667f88c6fd1a1815507decebcde9f63b`.
The failed 369 root remains complete and unsealed; no new old guest was run.

Harness `6668c29e9e07d6ab89cc04fe58e8ab8a89ac4afa`, SHA-256
`e6de49d024b706ffc34f6169b3a1a31f725708d3bbfd7425657513d9c6d2e707`,
retains the original 369 old367 ART control and boots only new371. Its generator
asserts verbatim preservation of the direct linkage-error and complete phase
oracle. Local compilation and semantic self-tests exited 0; two bounded source
reviews passed before the frozen bootstrap. These checks do not establish a
guest outcome.

The original signed APK is copied without rebuilding or signing, SHA-256
`710eeaa6cc2b5f0d5ddd0fde5b3b62e71e844220c20584846f121dbbe13eec85`.
The selected historical control files have an exact canonical path/hash map;
every selected file is rehashed at its original location and retained copy.
The original old config, staged APK path, command argv, serial and semantic
receipt remain unchanged. The complete 52,112-file original root remains
required; its one full failure inventory pins the historical contents while
later checks compare its complete file set without repeating that full hash
pass. The old367 native closure must equal fresh371 native-old; all non-JAR
native files are independently compared with the complete qualified353 closure. The new JAR
must remain the sole native runtime difference.

Fresh old-control receipts explicitly say `retained-old-control-pass`; no new
old guest is claimed. Actual outer actions record their executable hashes,
argv, UTC times, output hashes and exit codes beside the fixture root. The new
guest must emit all nine pass markers in order and survive the entire 35-second
window under the unchanged nullable startup classifier. The
[600-second Maps replay](maps370-intent-uri-replay.md) is separate evidence.

Recorded preparation ran 04:04:30–04:13:23 UTC on 2026-10-26 and exited 0,
including the retained old-control oracle. The fresh checked runner is
`00c60580fbd151f9760dbf9b83604d469ebcf29093822aa38a73b518932c966b`;
`shared-inputs.json` is
`81c6c4915ce15be52471fed4ba3972f04d913ad88c7a77a59ccd79bb6e0b0dad`,
and `build-pins.json` is
`73e13c76dfb0e74245a3010723badc66549a2da68bcf3c1f665364b1f4b0847b`.
The bounded post-prepare pin capture also exited 0 and is retained at
`/Users/alex/.local/state/vinix/android/intent-uri371-preparation-pins-2026-10-26`.

The frozen runner bootstrap passed its own and sole independent readbacks:
655 files, the exact 270 V inputs, and all 13 recorded command argv/status
checks. Its external root is
`/Users/alex/.local/state/vinix/android/intent-uri371-run-bootstrap-build-2026-10-26`,
manifest `0056ca7608c43d61612f24caeb251c502e41c1f6b28db22ba249710084691421`,
runner `4c192b967eb30a27caa5fa08d5d5c0ff15e4136e89134390d91c7704ef4488b6`.
The independent receipt is
`intent-uri371-run-bootstrap-peer-readback-2026-10-26/complete-receipt.json`,
SHA-256 `c4aac06796ac5b1ac31a80fe2473548f5f891a824d118b3b4a71ad28dc46e1e1`.
The separately built action recorder passed its bounded independent check of
270 inputs and four actual build commands; receipt SHA-256
`95eb1d7041786b34827b70b238cc11cd4bddb00fed5a95d58f50e704a0d7569f` at
`intent-uri371-action-recorder-peer-readback-2026-10-26/receipt.json`.

Framework 371 is qualified by a sole full independent readback of all 50,901
files, 33 command records and 414 inputs, including the emitted DEX null branch.
Its root is
`/Users/alex/.local/state/vinix/android/intent-uri371-framework-build-2026-10-26`,
manifest `71e311764ece295185656854294a514a9c641419c567d5f96ac66f52f4b89750`,
JAR `3b345e1661ca9f5b616f5abe25c9f4abc1df383204d25333477dae69221a8d21`.
The independent receipt SHA-256 is
`cb6975730ffa6c9281ca725100d0bb41c841e0f02438c850cc228dc912df99a7`.
