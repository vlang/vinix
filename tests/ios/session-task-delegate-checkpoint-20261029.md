# URL session task delegate checkpoint — 2026-10-29

Implementation and captured source: `ccd305ad2`. URL session tasks retain an
independent per-task delegate. Replacement retains the new delegate before
retiring the old one; old-delegate destruction runs outside the state lock.
Generic allocation ownership preserves cleanup after an isa replacement.

Native comparisons and normal/deterministic ASan/UBSan host runs pass, as do
the existing base-task and suspended data-task regressions. Coverage includes
the four public task classes, configured data tasks, saved IMPs, metadata,
strong ownership, getter autorelease lifetime, replacement, self-assignment,
session/delegate independence, eight workers, reentrant destruction, caller
storage canaries, weak references, isa replacement and two runtime lifetimes.
LeakSanitizer is disabled; object counters do not prove absence of all leaks.
Runner selftests pass five profiles with three tar member spellings, exact
media bytes/modes, pinned fixtures and invalid/missing/duplicate result logs.

All **50 guest fixtures pass**: 45 pinned fixtures retain earlier provenance;
StoreKit, suspended data-task, URL resource-value, signed number and delegate
fixtures are fresh, as are the runtime, native init and VM driver. Fortnite
passes `setDelegate:` and stops at **`-[NSURLSessionDataTask resume]`**. This
requires transfer and callback backends; successful networking is unverified.
Application exit is 1 and capture exit is 0. All six budget event counters are
zero; final usage is 426,862 bytes. The desktop records 13 builds and 12 polls,
without a supervisor kill. Advertising remains skipped.

Progress remains **4/8 observable launch gates (50% of the checklist, not an
effort estimate or ETA)**: loading/binding, `+load`, initialization and entry.
Frame, menu, login and playable match remain unverified. Audio output and
Metal execution/presentation still require backends.

The complete bundle passes its unchanged historical auditor, independent
supplemental media/results checks and **339 negative controls**. A persistent
192 MiB delta archive passes checksum and prior-manifest verification. Its
complete prior is the retained filesystem resource-value checkpoint. This
archive has not yet been restored; restoration/deletion qualification is not
claimed. The complete original remains retained. Interrupted first archive
and supplemental-check attempts are not qualification evidence.

```text
Cache: /Users/alex/Library/Caches/vinix-ios
Original: /Volumes/VinixTaskDelegate20261029/task-delegate-20261029
Persistent archive: CACHE/task-delegate-20261029-archive
Prior: CACHE/url-resource-values-20261029-r2
VM state: probe-no-ads-132916
Manifest SHA-256:
3f8796890590065f859747054cf37d0c038999df507dd35763e21c8092338389
Runtime SHA-256:
87248234769f1b1d02bdc64ea70ae7ba7a694f9d7e181431f43af544bd15adba
Serial SHA-256:
975d6abccba5e8ab13ea14026c45d61a8968fe82ae876b35bb04e1b8d66aeb21
Archive inventory SHA-256:
fae67666c612cb62a592f05a7a42cbb3e54d069b9b2e6f1ef284aae003f3ab89
Prior manifest SHA-256:
fe500d7b2c7e13b03cc662628a5139c33b5fbd298ac268989ebbcca7c86b075c
Receipts: CACHE/audio-category-20261027-work/task-delegate-*-20261029*.log
Native inspection: CACHE/audio-category-20261027-work/native-task-delegate-20261029.log
```

From the repository, run `BUNDLE/storekit-operation-probe check-queue
ABSOLUTE_ORIGINAL_BUNDLE FRESH_EXTERNAL_SCRATCH`. Restore using the maintained
[archiver](evidence-delta-archive.v): `restore ARCHIVE FRESH_TARGET FRESH_WORK`.
Restoration needs the complete pinned prior and macOS system libraries; codec
binaries and their additional libraries are packaged. Earlier provenance and
limits are recorded in the [resource-value checkpoint](url-resource-values-checkpoint-20261029.md)
and [signed-number checkpoint](number-long-long-checkpoint-20261029.md).
