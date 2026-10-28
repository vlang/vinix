# Suspended URL-session data-task checkpoint — 2026-10-29

Implementation, runtime and captured source: `6b3a88bb7`.
`-[NSURLSession dataTaskWithRequest:]` now creates suspended data tasks with
per-session identifiers, native defaults and independent request snapshots.
Tasks own their session and requests; an unresumed task introduces no session
ownership cycle. Constructors run outside the state lock with inputs retained.
Transfers, task lifecycle operations and delegate delivery remain unsupported.
Advertising remains skipped.

Native comparisons and normal/deterministic ASan/UBSan host runs pass for the
new fixture and the existing session/task suites. Checks cover mutable and
immutable requests, defaults, direct IMP calls, metadata, mutation isolation,
eight concurrent creators, two balanced runtime lifetimes, weak-reference
cleanup, isa replacement and reentrant/failing task constructors. Ten invalid
input, lifetime, identifier and lifecycle cases fail explicitly. LeakSanitizer
is disabled; balanced object counters do not establish absence of all leaks.

The current host Foundation task records measure 728 bytes, with the added
private `_sourceApplicationBundleIdentifierForMobileAsset` field at offset
720. All 14 measured public property offsets match the earlier 720-byte
record. The native layout test checks both measured variants explicitly;
Vinix's public task record remains 720 bytes.

All **47 guest fixtures pass**: 45 pinned fixtures retain their earlier
provenance; the StoreKit and data-task fixtures, native init, VM driver and
runtime are fresh. Runner selftests pass for LF/CRLF and invalid result logs,
copies over 2 GiB, and exact runtime/init/fixture replacement in tar and FAT
media, including absent and dot-prefixed members. The StoreKit host suite
retains its preceding checkpoint's provenance.

Fortnite passes `dataTaskWithRequest:` and stops with:

```text
iOS: URL session task transfers, cancellation, delegates, progress and coding are not implemented
```

This capture does not identify the exact selector. Application exit is 1;
capture exit is 0, without an application signal fault, OOM event or supervisor
kill. All six application budget event counters are zero; final usage is
426,862 bytes. The desktop records 17 builds and 16 polls.

Progress remains **4/8 observable launch gates (50% of the checklist, not an
effort estimate or ETA)**: loading/binding, `+load`, initializers and application
entry. Frame, menu, login and playable match remain unverified. Audio output
and Metal execution/presentation still require backends.

The unchanged historical auditor, supplemental StoreKit/data-task media and
result checks, and **339 negative controls** pass. The complete expanded
bundle is retained on persistent storage. Archive restoration and deletion
qualification are not claimed.

```text
Persistent cache: /Users/alex/Library/Caches/vinix-ios
Complete bundle: session-data-task-20261029 (approximately 9.1 GiB)
VM state: probe-no-ads-132916
Manifest SHA-256:
e6eef125e08e98259b0ab25eca7e8eeab8a1e4624e77627bab285df942b9ceaf
Runtime SHA-256:
4f21a9882f874b150ba87f1eb5674ae5cf5f5f62baf4da0525373401a6d280e3
Serial SHA-256:
c03a1b1a4255d50bc9ada9a2f5ded80cb596aa51cf89c2526ed4c06c7645e004
Receipts: audio-category-20261027-work/session-data-task-*.log
Saved additional checks: session-data-task-20261029/data-task-extra-validation/
```

From the repository, run `BUNDLE/storekit-operation-probe check-queue
ABSOLUTE_BUNDLE FRESH_EXTERNAL_SCRATCH`. The saved checker invokes the
unchanged historical auditor and validates both additional guest fixtures.
Keep the complete bundle at its recorded absolute path for historical logs.

The [dictionary parent](dictionary-variadic-checkpoint-20261028.md) records
reused fixture and historical kernel provenance. The frozen V is 0.5.2
`c6bb06f`; these snapshots do not establish a complete compiler/header/library
closure. The [StoreKit observer checkpoint](storekit-observers-checkpoint-20261028.md)
preserves the preceding `dataTaskWithRequest:` boundary.
