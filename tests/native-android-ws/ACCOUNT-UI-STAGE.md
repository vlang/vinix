# Real desktop account UI fixture

`account-ui-stage.v` appends a fixed diagnostic overlay to a fresh, unbooted
headless stage. It pins the baseline receipt, media, Limine configuration and
original modules, checks the complete headless overlay inventory, and verifies
the new archive and preserved modules after readback.

The guest runs the real desktop helper and controller against the window service
belonging to its GUI terminal. It verifies process, socket and peer identity,
validates the controller's frame and lifetime receipt, and exports the complete
results over UART. This fixture proves no ART, Google account or sign-in behavior.

Controller source is `b5ce00d64`, supplied binary SHA-256
`3dcfb85051079e8205d4a71334e432241a72e9950b25551ea8e69ece70c909d4`.
Helper source is `4887c0f13`, supplied binary SHA-256
`eff0ee8da211772f2549a5b39fdb2739cbb746db44e859bc25bd56b854fbd989`.
The stager retains these sources and receipts without claiming to rebuild the
two supplied binaries. Guest and collector tooling was committed in `bc9004af1`.

Host-only validation passed at
`/Users/alex/.local/state/vinix/android/account-ui-check-2026-10-26-r1`;
`checks.json` SHA-256 is
`84152d4b627178d8d23ddb22acff6462ffe9719e18da44e095b3cd5487a92e61`.
Checks cover static AArch64 guest compilation, exact overlay allowlist, archive
readback, configuration and destination aliases, digest mismatches, incomplete
baseline receipts, fresh output and QMP pathname limits. Production/debug build
checks verify embedded source retention, reject debug source auto-reading, and
preserve compiled source identity after changing every copied source file.
No guest was launched by these checks.

The checked production stager is `build/android-maps/account-ui-stage-r2`, SHA-256
`ca848f1fab51da7a1a4e92e2d0e617f903f354bd31afdfc834ec58b8b27fd091`.
It embeds stage source
`8c8b684b03d4978b23379e0041446fba59a7364212284ce6e619c24134898400`,
guest source
`c04e92d96a9c10f810f4ef18ebbb74a651fef938954d33e0658253741b689740`,
and collector source
`bee6754db75af772577dfe9f260e15b312737061590b8b4fd1e3f80dc1b38a76`.
Guest compilation checks the retained compiler hash before and after use.

Run with the actual SHA-256 of the baseline `stage.json`:

```text
build/android-maps/account-ui-stage-r2 BASE_STAGE STAGE_JSON_SHA256 FRESH_EXTERNAL_OUTPUT
```

Boot the resulting media with the maintained runner. In its real GUI terminal,
run `/opt/vinix-account-ui/bin/account-ui-guest` as root. Collect the strict
`VINIX-ACCOUNT-UI-RESULTS-1` transfer with:

```text
/Users/alex/.local/state/vinix/android/account-ui-collect-check --account-ui SERIAL_LOG FRESH_EXTERNAL_RESULTS
```

The checked collector SHA-256 is
`357edf19436ac0f905b2fab4ceb000937e821447fbc48cba7ddcb16660771578`.
Frame ordering, transfer digests and archive inventory remain mandatory.

Fresh staging completed with exit zero from source `ca13b0838` at
`/Users/alex/.local/state/vinix/android/account-ui-stage-2026-10-26-r2`.
Its `stage.json` SHA-256 is
`a7c8a08157f32595491863bf6bb2a86c370a79bb644d6bc681194547f60b0ecb`;
the complete `sha256.json` inventory is
`f5def88d6933a888f81b8a816788dbd28c38ca89523cc8417d074bfd1d1a624b`.
The baseline was the unbooted `headless-stage-r4-2026-10-26`, receipt
`7448a177792eaba0a5555dd35ada0efefd790afd4b863def3647362c23c65559`.
All six original modules passed unchanged hash checks and overlay readback.
Guest execution remains a separate root-owned check.

This run used `build/android-maps/account-ui-stage-r4`, SHA-256
`f5b9cda90a51c60394414a03b760ca1890a3a6bc026d9d0976fb7213a6e5a6f2`.
It retains compiled stage source
`1c6b73a6d60e9d3d8bd904c4200de0ac95942fdcc5128c3e4af813c75b73acfb`
and guest binary
`253c6daefdd308c9dc8c7f597c5615b659e5323aeccd2e15f51aa98e9e6f0056`.
The earlier `account-ui-stage-2026-10-26-r1` remains preserved after its
120-second compiler deadline. The revised runner gives guest compilation
a separate 900-second bound and retains timeout receipts. Its targeted
deadline rejection check passed at `account-ui-deadline-check-2026-10-26-r1`,
receipt SHA-256
`c08df6271bb4300425b7c25753517fcb234e45d2c712c3b8d7daea53efed79db`.
