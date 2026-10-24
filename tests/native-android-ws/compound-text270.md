# Compound text270 paired regression

The actual baseline266/fixed270 pair passed its runtime assertion gate
using the same standalone signed fixture APK. Baseline failed the expected
first constructor callback assertion; fixed emitted all four text PASS
markers plus READY, with backend ready and the process alive for 30 seconds.
Both suites exited naturally with host code 0. The strict seal and
independent full check passed for all 6,991 retained entries. Failed268
remains independently retained with its unchanged checker; see
[compound-text268.md](compound-text268.md).

The baseline source revision is
`ad65b2828e495fb33c0faf682c9e0d155f9dadce`, framework
`69f560aef5965acd2e4c1eba35a545dae5c8e48708695b0c747a1267d75643c3`
and native
`0a9928b59585bc7e1d6518c22a9a388f5bb99e4f43f3c0838d6c1c47588fb680`.
Fixed production revision is
`f1b8ed0bd4defa39e9caf2b03733b52f60878045`, framework
`b1364aa6d21f3293bef534a939cafa93bb4194e13deb9c0864bec7e9b18f9413`,
native
`ce78582105a8e2e29e29d0fa843769549d5fa4deba02067b41749643bb4b0c32`
and signed fixture APK
`42636b3afa2dfe515da4ad194f0f83e0f214f1ddacb3f5c616a7713f3585eec1`.

The checker requires complete 125-file framework and 83-file native
source maps and exact texts. Only `framework_classes.v` may change in
the framework, inside `framework_text_widgets` and the later
`framework_check_widgets` writer. Only `ws_views.v` may change in native
code, inside `ws_draw_content`. All generated JNI V wrappers and full
bindings remain identical to baseline266. The later getter writer is
checked explicitly because the separate268 retry exposed its overwrite
of the earlier `CompoundButton.getText` forwarder.

The unchanged fixture assertions verify virtual constructor/setText
overload dispatch, retained Spanned identity from `getText`, compound
text gravity and styled text drawing. Baseline266 failed the exact
`Button constructor invokes overload actual=0 expected=1` assertion
before any PASS marker. Fixed270 emitted
`BOOTSTRAP-TEXT-OVERLOAD-DISPATCH-PASS`,
`BOOTSTRAP-COMPOUND-GRAVITY-PASS`,
`BOOTSTRAP-STYLED-COMPOUND-TEXT-PASS`,
`BOOTSTRAP-COMPOUND-TEXT-PASS` and `BOOTSTRAP-READY`, remained alive for
30 seconds with the backend ready, and had no assertion or process exit.
The original suite classifier remains unchanged: both raw rows report
`startup_failed` and `functional_passed: null`. Fixed has exactly the two
known complete Main diagnostic lines (`NoSuchFieldError` for `Lnge;.bB`
and `ClassNotFoundException: nge`); guest assertion success is a separate
claim. Baseline ran 20:09:52–20:10:27 UTC and fixed ran 20:10:27–20:11:30.

The complete sealed external bundle is
`/Users/alex/.local/state/vinix/android/compound270-2026-10-24`.
The checker requires independently retained prelaunch/completed trees,
complete inventories, actual build and run receipts, the same signed APK,
equal common runtime and initial private media, actual staged host module
hashes, and a frozen auditor with its compiler/source/binary receipts.
No FAT or guest memory readback is claimed. The final `sha256.json` pin is
`ffa49c4542c8c5780b7869a59cbc108011fc59a151019fe1ddcffb9afa2ac2c3`.
Wrong-pin and authentic-partial negative cases passed. The independent
full check passed for all 6,991 entries using the frozen executable.

Recorded auditor compilation passed with source
`61f86fb52a76c3118aa39d2eaed83bb798d83aa1212abcb9106685207f578e87`
and executable
`2cb95dfb9537431e5df9b82dba12387258235969164fa1f58a2be5d8a1489c60`.
The source, compiler, before/completed receipts and executable are retained
at `/Users/alex/.local/state/vinix/android/compound270-audit-build-2026-10-24`.
The assertion probe and final `-prod` refusal passed.

Reproduce the full check with the frozen executable:

```sh
/Users/alex/.local/state/vinix/android/compound270-2026-10-24/audit/compound-text270-evidence check \
  /Users/alex/.local/state/vinix/android/compound270-2026-10-24 \
  ffa49c4542c8c5780b7869a59cbc108011fc59a151019fe1ddcffb9afa2ac2c3
```
