# StoreKit default queue checkpoint — 2026-10-28

Implementation: `fae78bab7`; captured source: `d34e54c56`.
`SKPaymentQueue defaultQueue` now returns a cached, synchronized built-in
instance. `canMakePayments` returns false because no payment provider exists.
Queue subclass factories, caller-provided storage, payments and requests remain
explicitly unsupported. Advertising remains skipped.

Native metadata inspection and normal and deterministic ASan/UBSan host runs
pass. Tests cover metadata and direct IMP calls, cache identity across eight
workers, balanced ownership and two runtime lifetimes, 276 unsupported purchase
operations and seven invalid queue lifetime/storage cases. Native inspection
does not contact an App Store provider or establish native queue behavior.

All **46 guest fixtures pass**: 45 retain the dictionary checkpoint's provenance
and the StoreKit suite is fresh. Fortnite passes `defaultQueue` and stops at
`SKPaymentQueue addTransactionObserver:`. Application exit is 1; capture exit
is 0, without an application signal fault, OOM event or supervisor kill.
All six application budget counters are zero; final usage is 426,862 bytes.
The desktop records 15 builds and 15 polls.

The initial wrapper rejected CRLF serial output after a successful capture.
Checker fix `154a64824` accepts LF and CRLF while rejecting failed, missing and
duplicate results. Its saved supplemental auditor passes, including the
unchanged historical auditor, original resources and extracted binaries.
The original wrapper's failed qualification receipt remains preserved.
Sealing and **339 negative controls** pass. An early check overlapped sealing
and failed on a temporary audit path; the sequential post-seal check passes.

Progress remains **4/8 observable launch gates (50% of the checklist, not an
effort estimate or ETA)**: loading/binding, `+load`, initializers and application
entry. Frame, menu, login and playable match remain unverified. Audio output
and Metal execution/presentation still need backends.

The complete bundle is preserved in a verified persistent delta archive.
Its complete restoration matches the original typed inventory, including hashes
and permissions, and passes its saved unchanged historical and supplemental
auditors at the original recorded path. Both expanded RAM-disk copies remain.

```text
Persistent cache: /Users/alex/Library/Caches/vinix-ios
Archive: storekit-queue-20261028-archive (2,166,626,863 bytes)
Required parent: dictionary-variadic-20261028 (complete persistent bundle)
Recorded bundle: /Volumes/VinixStoreKitQueue20261028/storekit-queue-20261028
VM state: probe-no-ads-132916
Manifest SHA-256:
be9f99c6eb5c195cfd8ed1ffd53a237e9ba0434bbf47697811532ef485b25cf6
Archive archive.sha256 SHA-256:
fc181583bb67c20e9d7d70c6c82ba848cb5d03e841e6f33c25bf64170d813389
Runtime SHA-256:
3cf99ea0c944fb25dcda6d0ff00de5fbbcdc6327f89345bcc5124c740961e406
Serial SHA-256:
37b6cc37f3d9567ad19c899d0c5d1fd363697cd03577c01e82d4a0cc8054f18c
Receipts: audio-category-20261027-work/storekit-queue-*.log
Round-trip receipts: audio-category-20261027-work/storekit-queue-roundtrip/
```

Restore with the maintained `tests/ios/evidence-delta-archive.v` tool:
`restore ABSOLUTE_ARCHIVE FRESH_TARGET FRESH_SCRATCH`. Its base references must
resolve to the complete persistent parent. Place the restored bundle at its
recorded path, then run `BUNDLE/queue-checker check-queue ABSOLUTE_BUNDLE
FRESH_EXTERNAL_SCRATCH` from the repository. That saved checker includes the
CRLF fix; the original driver and source are also retained.

The [parent report](dictionary-variadic-checkpoint-20261028.md) records the reused
fixtures and historical kernel's dirty-worktree provenance. The frozen V is
0.5.2 `c6bb06f`; these snapshots do not establish a complete compiler/header/
library closure. No historical auditor was weakened.
