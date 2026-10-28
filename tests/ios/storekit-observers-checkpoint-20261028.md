# StoreKit observer checkpoint — 2026-10-28

Implementation, runtime and captured source: `80f68d63b`.
`SKPaymentQueue` supports adding and removing transaction observers, immutable
observer snapshots and an empty transactions snapshot. Registration uses stable
zeroing-weak slots and identity-based duplicate suppression. Snapshots own
their contents independently. No payment provider, purchases or synthetic
transaction callbacks are supplied; `canMakePayments` remains false.
Advertising remains skipped.

Native metadata inspection confirms method scope and ABI for all four added
selectors. It makes no requests and does not establish native observer
retention behavior. Normal and deterministic ASan/UBSan host runs pass,
including message and direct IMP calls, signatures, duplicate registration,
removal, snapshot ownership, 80 weak slots across registry growth and observer
deallocation, eight concurrent writers and two balanced runtime lifetimes.
Nil add/remove, a missing required callback and a retired queue are rejected.
The previous 276 purchase-operation and seven queue-lifetime rejections also
pass. LeakSanitizer is disabled; balanced object and weak-slot counters do not
establish absence of every heap leak.

All **46 guest fixtures pass**: 45 pinned fixtures retain their earlier
provenance and the complete StoreKit suite is fresh. Host generation, four
objects, linking and both sanitizer executions have status 0. Probe-runner
selftests cover LF/CRLF result checks and missing/failed/duplicate results,
streaming copies over 2 GiB, and exact runtime/init/fixture replacement in tar
and FAT media, including absent and dot-prefixed members.

Fortnite passes `addTransactionObserver:` and now stops at
`-[NSURLSession dataTaskWithRequest:]`. Application exit is 1 and capture exit
is 0, without an application signal fault, OOM event or supervisor kill.
All six application budget counters are zero; final usage is 426,862 bytes.
The desktop records 13 builds and 12 polls. The existing URL-session code
supports configured sessions and inert task metadata; creating and running
session data tasks remains unsupported.

Progress remains **4/8 observable launch gates (50% of the checklist, not an
effort estimate or ETA)**: loading/binding, `+load`, initializers and application
entry. Frame, menu, login and playable match remain unverified. Audio output
and Metal execution/presentation still need backends.

The sealed historical auditor, supplemental StoreKit media/result checks and
**339 negative controls** pass. The complete persistent copy matches the
original typed inventory, including file hashes and permissions. Both expanded
copies are retained; archive restoration and deletion qualification are not
claimed for this bundle.

```text
Persistent cache: /Users/alex/Library/Caches/vinix-ios
Complete persistent copy: storekit-observers-20261028 (approximately 8.8 GiB)
Recorded bundle: /Volumes/VinixStoreKitObservers20261028/storekit-observers-20261028
VM state: probe-no-ads-132916
Manifest SHA-256:
15a58a641e63bcb81647d91ded8629beea754d822575256c9d8de2eb744a7fb1
Runtime SHA-256:
9209ce6389186a450b1fccd527cb23740664c07df8799fd52f5aab6070475a30
Serial SHA-256:
798f66225507d6faeacab94ae4a337f1a18065ce4926c5c3dc5571dd55a8f506
Receipts: audio-category-20261027-work/storekit-observers-*.log
Copy receipts: audio-category-20261027-work/storekit-observers-preservation/
```

Run `BUNDLE/storekit-operation-probe check-queue ABSOLUTE_BUNDLE
FRESH_EXTERNAL_SCRATCH` from the repository at the recorded RAM-disk path.
If that path is gone, first copy the complete persistent bundle back to that
fresh path. The saved supplemental checker invokes the unchanged historical
auditor and checks the additional guest fixture. No historical auditor was
weakened.

The [dictionary parent](dictionary-variadic-checkpoint-20261028.md) records the
reused fixtures and historical kernel's dirty-worktree provenance. The frozen
V is 0.5.2 `c6bb06f`; these snapshots do not establish a complete compiler/
header/library closure. The [queue checkpoint](storekit-queue-checkpoint-20261028.md)
separately preserves the preceding `addTransactionObserver:` boundary.
