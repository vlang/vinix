# NSNumber signed long-long checkpoint — 2026-10-29

Implementation and captured source: `8e240d99f`. `NSNumber longLongValue` now
preserves integer bits, truncates real values toward zero, saturates outside
the signed 64-bit range and converts NaN to zero. Instance metadata is
`q16@0:8`; unrelated classes do not acquire the selector.

Native comparisons and normal/deterministic ASan/UBSan host runs pass. Tests
cover signed boundaries, unsigned bit patterns, integers above 2^53, booleans,
13 floating-point vectors, concrete receiver IMPs, metadata, eight workers and
two balanced runtime lifetimes. LeakSanitizer is disabled; object counters do
not establish absence of all leaks. Runner selftests pass all four profiles
and three tar member spellings, exact executable bytes, pinned fixtures,
copies over 2 GiB and valid/invalid result logs.

All **49 guest fixtures pass**: 45 pinned fixtures retain earlier provenance;
StoreKit, suspended data-task, URL resource-value and number fixtures are
fresh, as are the runtime, native init and VM driver. Fortnite again reaches
`-[NSURLSessionDataTask setDelegate:]`; captures can take different startup
paths. Application exit is 1 and capture exit is 0. All six budget event
counters are zero; final usage is 426,862 bytes. The desktop records 12 builds
and 11 polls, without a supervisor kill. Advertising remains skipped.

Progress remains **4/8 observable launch gates (50% of the checklist, not an
effort estimate or ETA)**: loading/binding, `+load`, initialization and entry.
Frame, menu, login and playable match remain unverified. Audio output and
Metal execution/presentation still require backends.

The original complete bundle passes its unchanged historical auditor,
independent supplemental media/results checks and **339 negative controls**.
The persistent archive passes checksum verification, full restoration and a
standalone comparison of every file, directory, type and permission. The
restored copy was compared at a fresh path; the historical auditor requires
the original absolute path and was run against the original bundle. Deletion
qualification is not claimed, and both expanded bundles remain retained.

```text
Cache: /Users/alex/Library/Caches/vinix-ios
Original: /Volumes/VinixStoreKitObservers20261028/number-long-long-20261029
Restored: /Volumes/VinixTaskDelegate20261029/number-long-long-restored-20261029
Persistent archive: CACHE/number-long-long-20261029-archive (approximately 2.1 GiB)
Prior: CACHE/dictionary-variadic-20261028
VM state: probe-no-ads-132916
Manifest SHA-256:
fa9b7376b9a757d3d034a3e8c18aeebfa3f0a3b18df2757a3519d1ae771ed523
Runtime SHA-256:
8d1f5114be89b79258fa6b015c075dd40c240955d6e36d9696b592230ec90cba
Serial SHA-256:
295d5fa08e51fa45f9b21c9d34a1f62853b297d800a3af4f83e57b55d7a0ec51
Archive inventory SHA-256:
c72a66c79ec7ec2de949672cfeba561a502fab911e2efb40dd306e4ea0edbddc
Prior manifest SHA-256:
c1163dfbb2bf9b0f096eba6123246028b00a43902ebd9963b115909b999e3dbb
Receipts: CACHE/audio-category-20261027-work/number-long-long-*-20261029*.log
```

From the repository, run `BUNDLE/storekit-operation-probe check-queue
ABSOLUTE_ORIGINAL_BUNDLE FRESH_EXTERNAL_SCRATCH`. Restore using the maintained
[archiver](evidence-delta-archive.v): `restore ARCHIVE FRESH_TARGET FRESH_WORK`.
Restoration needs the complete pinned prior and macOS system libraries; codec
binaries and their additional libraries are packaged. Earlier provenance and
limits are recorded in the [resource-value checkpoint](url-resource-values-checkpoint-20261029.md)
and [dictionary parent](dictionary-variadic-checkpoint-20261028.md).
