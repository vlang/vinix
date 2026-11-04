# Request cookie policy and longer startup observation — 2026-11-04

Fortnite still verifies **4/8 launch milestones**: loading/binding, `+load`,
initializers and application entry. No game frame, menu, login or match is
verified. This is 50% of the checklist, not an engineering completion estimate.
The longer guarded launch reproduces:

```text
V panic: iOS: URL session request transport profile is not implemented: cookies
```

`fcee5f780` implements native request-cookie precedence. An unset request policy
inherits `HTTPShouldSetCookies`; an explicit request value overrides it. Copies
preserve that distinction without rewriting public getters. Effectively
disabled handling permits transport, preserves manual Cookie headers and does
not replay response cookies. Enabled or partitioned cookie profiles remain
explicitly unsupported; no shared cookie jar or persistence is implemented.
The profile name alone does not identify the precise failing policy field.
The same change normalizes `options` to `OPTIONS`, while preserving `trace`
and custom method spelling, as measured against Foundation.

The November 1 verification passes normal/deterministic ASan/UBSan runs for the
complete HTTP/TLS, URL-request and StoreKit suites; LeakSanitizer is disabled.
Seven native cookie-policy cases check real wire headers and native storage.
Twenty-four runtime transfers check disabled explicit/inherited policies,
manual headers, source mutation after copying, ordered callbacks and two
drained runtimes. The ARM64 HTTP guest passes with 4096 MiB and four CPUs;
the GLES runtime builds. These complete results remain preserved, including
a 118 MiB archive whose fresh extraction passes a full byte/type/mode comparison.

The first November 4 game capture exited 0 after nine empty desktop builds.
Investigation found that the diagnostic peer closes the window after ten
seconds and selects `VINIX_IOS_EXIT_ON_CLOSE=1`. This was a controlled close,
not completed Fortnite startup. The historical panic-only auditor correctly
rejects it and remains unchanged. This complete short capture is retained
with a separate typed integrity receipt, not a launch qualification.

`53f294c4c` extends the game's observation limit to sixty seconds, retaining
the 200 ms window fixture, 30-second reply guard, 1800-second startup limit,
8192 MiB guest, one CPU and 2 GiB application budget. APFS clone staging checks
the complete copied input inventory; its self-test covers permissions,
independent clone mutation and unchanged media members. `f4de8c012` and
`64f00002a` add guarded pre-launch recovery and a coordinator detached from
the headless CLI. Recovery preserves interrupted build receipts, verifies the
saved source snapshot, rejects changed runtime/init/test sources and rebuilds
the target binaries. The separately recorded coordinator is the sole source
exception; a completed launch cannot be resumed by this mode.

The longer capture uses original cooked content with advertising skipped.
All 46 guest fixtures pass. The application reaches the cookie-profile panic
before controlled closure: 17 builds, 16 polls, one node, zero images, no
supervisor kill. All six application budget event counters are zero; application
exit is 1 and capture exit is 0. The unchanged saved auditor passes seal and
independent check, all 339 corruption controls pass, and the supplemental
StoreKit media check passes. No historical checks were relaxed.

The pull rebased the harness commit from `6ad9faad7` to `53f294c4c`; the iOS and
test trees were byte-identical at that point. The saved capture source remains
`6ad9faad7ef29a5091c92cde2d7859efabefe2d4`, with coordinator revision
`64f00002aaa1ba86ad1c573fdf9920b7ddf1360d`. The source tar and separate resumed
coordinator sources/binary are retained. This run uses the pinned dictionary
checkpoint's kernel; it does not validate the newly pulled kernel changes.

Rendering remains a major known gap. The game imports
`_MTLCreateSystemDefaultDevice`, and `compat/ios/runner/metal_device.c.v` returns
nil because no Metal command-buffer/AIR-shader backend is available. The current
capture does not establish that the game reaches that call. The next observed
startup work is the required cookie profile; clearing it alone cannot establish
a working renderer or playable Fortnite.

Both November 4 captures and the focused validation tree remain in persistent
storage. No expanded evidence was retired for this checkpoint. The independent
integrity-receipt feature in `152988b0f` preserves
complete file bytes, sizes, permissions and directory/root modes without
certifying application success. Its legacy archive tests and four new receipt
rejection controls pass. Both short and longer captures pass independent
checks against their complete typed receipts. The short capture's receipt
does not change its historical auditor rejection.

```text
CACHE: /Users/alex/Library/Caches/vinix-ios
WORK: CACHE/audio-category-20261027-work
Focused tests: CACHE/cookie-policy-validation-20261101-r1
Focused source: fcee5f780796f6df200eb4a44430741b16c80d8e
Focused archive: CACHE/cookie-policy-validation-20261101-r1.tar.gz
Archive SHA-256: 1c1af9fa68a7ee59031b27a2bc07b376ae13db13188117ef89966531228e484c
Focused restored: CACHE/cookie-policy-validation-restored-20261104/cookie-policy-validation-20261101-r1
Short capture: CACHE/cookie-policy-probe-20261104-r2
Short typed receipt: CACHE/cookie-policy-short-20261104.inventory.json
Receipt SHA-256: 194764d33ce99b60faa560492d13297b4dde99e5c5d96240875dacc6ac67239b
Qualified longer capture: CACHE/cookie-policy-probe-20261104-r3
VM state: probe-no-ads-132916
Manifest SHA-256: 7f44b36dc29ac0dd770eefaea5da937d67419014b4aa2e5df6243db9fa58bcda
Long typed receipt: CACHE/cookie-policy-long-20261104.inventory.json
Receipt SHA-256: 87cc31b202e3405d915e858af4187754daebf676fc52d42cfd9f4c6be9c070c0
Serial SHA-256: 2df3ce51f58bfc6e887a98f56f855d163aeb3777cfa4536494563739681c7359
Runtime SHA-256: 79396ffac9993242959bf3954457b9d6d2d4ae37d91f1b7e440a6254f825bb7d
Native init SHA-256: ca31e5fc83a04b4f43abd06dc5f04d2fb3c39d694379347757557e322006a1d0
Source tar SHA-256: de85c3663ab0f8412f6c3f3b31d7415f23af789d1b1dc63e312bf0ceb56e596a
Prior: CACHE/dictionary-variadic-20261028
Prior manifest SHA-256: c1163dfbb2bf9b0f096eba6123246028b00a43902ebd9963b115909b999e3dbb
Audit receipt: WORK/cookie-policy-final-check-20261104.log
Negative controls: WORK/cookie-policy-negative-controls-20261104.log
Inventory/clone tests: WORK/{inventory-selftest,long-probe-selftest}-20261104.log
Pull equivalence: WORK/pulled-ios-tree-equivalence-20261104.txt
```

Reproduce with frozen V 0.5.2 (`c6bb06f`), maintained `notification-checks`
host modes (`data-http-host`, `url-request-host`, `storekit-purchase-host`) and
`notification-vm data-http` / `build-run-ios-gles`, using fresh external roots.
The startup runner supports `--queue-clone` on one APFS volume, or `--queue-copy`
across volumes. `start-queue-build PREPARATION FRESH_LOG` resumes only a verified
interrupted base-queue preparation. Finish with the saved checkpoint's
seal/check and negative-controls modes and the runner's `check-queue` mode.
Integrity receipts use `record-inventory` and `check-inventory` with an external
receipt; build these helpers with `-cflags -O2`.
