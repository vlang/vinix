# URL filesystem resource values checkpoint — 2026-10-29

Implementation: `db55c56e7`; fixture-preservation fix and captured source:
`c08aa651b`. File URLs now expose cached creation date, file size, regular-file
status, backup exclusion and volume capacity values. Explicit invalidation and
backup-exclusion setters invalidate the cache. Missing paths return Cocoa/POSIX
errors; unknown keys and non-file URLs return nil values without fabricated
filesystem results.

Native comparisons and normal/deterministic ASan/UBSan host runs pass. Checks
cover all seven keys, files/directories/symlinks, raw backup attributes, errors,
cache invalidation, ABI and saved IMPs, eight concurrent readers, reentrant
constructors, weak-reference cleanup, isa replacement and two balanced runtime
lifetimes. Four invalid-argument cases fail explicitly. LeakSanitizer is
disabled; balanced object counters do not establish absence of all leaks.

All **48 guest fixtures pass**: 45 pinned fixtures retain their earlier
provenance; StoreKit, suspended data-task and resource-value fixtures are fresh,
as are the runtime, native init and VM driver. The pinned URL setter fixture is
preserved unchanged. Runner selftests cover exact tar/FAT replacement, member
spellings and absence, copies over 2 GiB, and valid/invalid result logs.

Fortnite reaches this observed boundary:

```text
iOS: URL session task transfers, cancellation, delegates, progress and coding are not implemented: -[NSURLSessionDataTask setDelegate:]
```

Different captures have stopped on different startup paths; this result does
not establish that task transfers work. Application exit is 1; capture exit is
0. All six application budget event counters are zero; final usage is 426,862
bytes. The desktop records 14 builds and 13 polls, with no supervisor kill.
Advertising remains skipped.

Progress remains **4/8 observable launch gates (50% of the checklist, not an
effort estimate or ETA)**: loading/binding, `+load`, initialization and entry.
Frame, menu, login and playable match remain unverified. Audio output and Metal
execution/presentation still require backends.

The sealed bundle passes the unchanged historical auditor, independent media
and supplemental fixture checks, and **339 negative controls**. The complete
bundle is retained on persistent storage. Archive restoration and deletion
qualification are not claimed.

```text
Persistent cache: /Users/alex/Library/Caches/vinix-ios
Complete bundle: url-resource-values-20261029-r2
VM state: probe-no-ads-132916
Manifest SHA-256:
fe500d7b2c7e13b03cc662628a5139c33b5fbd298ac268989ebbcca7c86b075c
Runtime SHA-256:
2accfde4a0044fc367d7b75ff5a234446661d08ad2b490bfd5c8c9535ac4d4eb
Serial SHA-256:
26943d4a4ab6959545a6fed20b0c99baaf41d71318cf622bb0fbdd6bb9eee068
Receipts: audio-category-20261027-work/url-resource-values-*-20261029-r2.log
Host receipt: audio-category-20261027-work/url-resource-values-host-20261029-r9.log
Saved native inspection and host/selftest receipts: inside the complete bundle
```

From the repository, run `BUNDLE/storekit-operation-probe check-queue
ABSOLUTE_BUNDLE FRESH_EXTERNAL_SCRATCH`. Keep the complete bundle at its
recorded path. The [data-task checkpoint](session-data-task-checkpoint-20261029.md)
and [dictionary parent](dictionary-variadic-checkpoint-20261028.md) record
earlier host, reused-fixture, kernel and frozen-toolchain provenance and limits.
