# Compound text268 failed smokes

The frozen268 build passed, but its fixed-only smoke failed in fixture
setup. `XmlBlock$Parser.nextTag` rejected the initial START_DOCUMENT event
with `XmlPullParserException: expected start or end tag`, through
`LabelButton.<init>` and `TextProbe.dispatch`, before any assertion or PASS
marker. A separate retry corrected only fixture parser setup, then failed
the unchanged assertion `CompoundButton getText retains Spanned identity
actual=0 expected=1` at `TextProbe.dispatch`. The later
`framework_check_widgets` writer had restored the native getter over the
earlier forwarding method. Both raw rows remain `startup_failed`,
`functional_passed: null`, `backend_ready: false` and
`process_exited: true`. No full paired run or semantic seal was performed.

The failed smoke is independently retained at
`/Users/alex/.local/state/vinix/android/compound268-smoke-2026-10-24`,
with `smoke-completed-sha256.json` pin
`6f190ebb1f5b59e9c223275c7cf3f2df81f6a562aed343269d2163604f46a0d3`.
It retains exact source maps/texts, runtime/config/APK/tool inputs, initial
private media clones with source-hash mappings, raw completed streams,
screenshot and actual receipts. This limited smoke inventory does not
claim complete post-run media hashes or semantic PASS.

The separate corrected-fixture retry is retained at
`/Users/alex/.local/state/vinix/android/compound268-fixture2-2026-10-24`,
with the same limited smoke scope and `smoke-completed-sha256.json` pin
`5622447816eef23175f4a968b404c73485c528f0d7019e331961d2ab55755f68`.
Its signed APK is
`c4b47f4b8dc1a89e889008772435e5c70b102ac6d462d344b049ea05361ec207`
and fixture source is
`99518c6b936e61796b6a8d9a581a0497a36c9371efaa4f48692b7a384e0978d8`.
It used the identical frozen268 framework and native runtime.

The entire successful frozen build, including source/compiler closure,
inputs and receipts, is independently retained at
`/Users/alex/.local/state/vinix/android/compound268-2026-10-24/failed-build`.
Its `failed-build-sha256.json` pin is
`087125d442a63f2e71398edba75547e5dcf9f1e68d2b1e5e2491648896323e34`.
`failed-build-retention.json` records 2,947 regular files and no omitted
entries. This archive contains no VM run or semantic seal.

The baseline is source revision
`ad65b2828e495fb33c0faf682c9e0d155f9dadce`, framework
`69f560aef5965acd2e4c1eba35a545dae5c8e48708695b0c747a1267d75643c3`
and native
`0a9928b59585bc7e1d6518c22a9a388f5bb99e4f43f3c0838d6c1c47588fb680`.
Fixed source was frozen before its production commit; exact input texts
are retained. The actual failed smoke used signed APK
`985317970410e2b6b38399ad391990e4e23bd90778158b30b6fc7a69cfa5ef29`,
framework
`b9c9165b46716c5dfd410e4983613eec871e627839a0f928d2cd532983f8165c`
and native
`b034c453321c8a14e0d3b3cb0bb877ccfe5f4966e8ae6da1f89f5756fada3868`.

The strict 268 checker remains frozen. It requires complete 125-file
framework and 83-file native maps/texts, with changes only inside
`framework_text_widgets` and `ws_draw_content`. Generated JNI V wrappers
and full bindings must match the frozen 266 inputs. It also requires paired
receipts, the same signed APK, common runtime/initial private-media equality and
staged host module hashes. No FAT or guest memory readback is claimed.
Its unexercised runtime contract requires the baseline's exact constructor
callback assertion and all five fixed text markers plus 30-second survival.
The original classifier and exact optional diagnostic lines are preserved.

The recorded auditor compilation passed with source
`23063a6d7cb3ea3a69abcaeaae09c91c7ef4ee069e25885484674ff45ebf486b`
and executable
`bbc4e63ec27e88c3f2c8720f8bc2523fd876fc50919e94b2f9e4e47d169d529c`.
Source, compiler, before/completed receipts and executable are retained at
`/Users/alex/.local/state/vinix/android/compound268-audit-build-2026-10-24`.
The assertion probe and final `-prod` refusal passed. No strict semantic
seal, full paired recheck or complete-bundle negative audit was run,
because the required pair does not exist. Historical evidence and the
frozen268 auditor remain unchanged; fresh270 uses separate artifacts.
