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

## Controller argv lifetime fix replay

Fresh staging at
`/Users/alex/.local/state/vinix/android/account-ui-stage-2026-10-26-r3`
uses the argv lifetime fix from `75154c870`. The controller producer is
`current-ui-controller-build-2026-10-26-r1`, source revision
`c5fc9065af1e624002eaff6e2f927ce79858a06e`, complete inventory SHA-256
`503f4e03edf225311038cc0ecce556b804f6b07a337793ff7a466881fbe0112a`.
The stager checks that complete producer, exact build profile and output, and
the actual compiled controller and argv source pins before and after staging.
It retains the compiled source closure and original producer inventory outside
the guest payload. Historical bundles above remain unchanged.

The new controller SHA-256 is
`5c5d6415f3e97cb2369187a7aa373aca019ae1e085298daf4551789739851f18`;
the guest SHA-256 is
`c6aa4affee1b2ac822cc422aca755bb5867f23bd7b471007e0f04a93020d3f3f`.
The helper remains `4887c0f13` and
`eff0ee8da211772f2549a5b39fdb2739cbb746db44e859bc25bd56b854fbd989`.
Stage source SHA-256 is
`aa112b59fda67bf53ce0ed2a45f313ce917c54e02d05992a3166f1b4b4c79bb2`;
guest source SHA-256 is
`c8642b186fa4255ce63e29958b4cfa101497ff73af0250b15c1a63c10aecf464`.

Production/debug and source-mutation checks passed at
`/Users/alex/.local/state/vinix/android/account-ui-check-argv-2026-10-26-r1`.
The `checks.json` SHA-256 is
`ac359f73b0283c6b298274d0dd4d4e73c97b9ce3628c87326ed9131dc8df6c73`;
`host/checks.json` SHA-256 is
`967c39156b01f9a6c2fbeb3ae12e3b013f3a26bc563239ddac1d7472a24fde1c`.
These also cover complete producer inventory and metadata rejection, static
AArch64 compilation, archive readback, and the existing deadline checks.
The retained `stage-prod` binary SHA-256 is
`ff8d69b191094b63df9f50c8545b4548392b9ed48afaaf0732b9099af829154a`.

The fresh media stage completed with exit zero. Its `stage.json` SHA-256 is
`ade6f5f89f73632ee6ef1cc36b95d17b8a3b70e25dbeb3660ba5c3401e894b20`;
the complete `sha256.json` inventory SHA-256 is
`bcb7656ee29c66d2d54fad120aff2d09f078e3a7684ce59c3ac1dd88aa16d394`.
It uses the same unbooted baseline receipt
`7448a177792eaba0a5555dd35ada0efefd790afd4b863def3647362c23c65559`;
all six original modules passed unchanged hash checks and overlay readback.
The staged firmware SHA-256 remains
`d3b3f7afddb44de7020b8544270a67791fca44a48864dcd550cefee633463cbf`.
No guest was launched by this replay, which proves no ART or Google sign-in.

Independent read-only artifact review is retained in
`check-account-ui-argv-stage.v` at `4dd935b86`. Its assertions-enabled build and
rerun passed all 774 stage output files, 699 recorded stage inputs, retained
compiled controller sources, and the six streamed module preservation receipts.
The external evidence prefix is
`/Users/alex/.local/state/vinix/android/check-account-ui-argv-stage-host-2026-10-26-r1`;
the `.v` source SHA-256 is
`1abbea12ff3e6e5a302ed6bf26865a74bd59db7cf4b5e2af94044565eb41dce8`,
executable SHA-256 is
`a8d70ac590c75270bfeec41b25f49b4d1fef12eb824c00d8c10b0bc586981eb0`,
and `.log` SHA-256 is
`792bc0359cb5eab0d4424f1ff1cb6b5cfdb4f76d875423e198af4b289b8004f4`.

## Actual desktop replay of the argv fix

The root-owned `account-ui-vm-r3` guest passed at 2026-10-26
19:08:05–19:08:07 UTC using the original r3 stage and controller revision
`c5fc9065af1e624002eaff6e2f927ce79858a06e`. The controller exited zero,
did not time out, reported one descendant and left zero cleanup survivors.
All nine checks passed: real helper window, session capability, two received
file descriptors, CLOEXEC, sealed frame size, read-only input FIFO, diagnostic
frame, helper-lifetime EOF/input close, and single-use attachment.

The stopped clone, original stage, full controller producer and original
17-entry collection remain at their complete external paths. The collection
is `account-ui-collected-2026-10-26-r3`, archive SHA-256
`a78b2697680c094b8967d816332996734bc5893456da3f4b489c657516bad1fe`.
`seal-account-ui-run-r3.v` checks their complete membership and hashes, binds
launch/stop receipts to the owned process and media, and replays the retained
historical strict collector with its self-test. The replay archive and every
result file match the original collection exactly.

The sealed evidence is
`/Users/alex/.local/state/vinix/android/account-ui-run-evidence-2026-10-26-r3-r2`,
with complete inventory SHA-256
`7a064dfb75de1c583c74b7b7a3ce3f1bae164155c91f29cc2386b992369bc6bb`
and receipt SHA-256
`2453c19380517a8fe52b4994491b21341b3d4a8db77b46eadfa69bb66a0ea96b`.
It retains the sealer's compiled source and executable, collector commands and
receipts, and 2,450 external file pins; all evidence trees are rechecked before
sealing. Its build argv is documented rather than a retained command receipt.
This proves the standalone desktop helper/controller behavior. Android account
authentication and Google sign-in remain separate checks.
