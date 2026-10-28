# Background URL-session configuration checkpoint — 2026-10-28

Implementation, runtime and frozen auditor: `b747c83b6`. Advertising remains
skipped. Both `backgroundSessionConfigurationWithIdentifier:` and the deprecated
`backgroundSessionConfiguration:` now copy their identifiers and supply the
native configuration defaults. Transfers and background scheduling still need
transport support. Concurrent mutable-copy tests also exposed and fixed an
unlocked object-map read during `objc_copy_value`.

Native comparisons and normal and deterministic ASan/UBSan runs pass for both
session suites. They cover identifiers, direct IMPs, metadata, ownership,
reentrant callbacks, constructor failure and concurrent copying. All **41 guest
fixtures pass**: 35 explicitly reused fixtures and six freshly built fixtures.
Ten required host suites and one supplemental Swift layout suite are reused
with their original provenance; two session suites are fresh. The sealed saved
auditor and **283 negative controls** pass, including original resources and
extracted guest-binary comparisons.

Fortnite passes the background factory and now stops at
`PLCrashReporter isEqual:`. Application exit is 1 and capture exit is 0, without
an application signal fault, OOM event or supervisor kill. All six budget
counters are zero; final usage is 377,604 bytes. The desktop records 12 builds
and 11 polls.

Progress remains **4/8 observable launch gates (50% of the checklist, not an
effort estimate or ETA)**: loading/binding, `+load`, initializers and application
entry. Frame, menu, login and playable match remain unverified. Audio output
and Metal execution/presentation still need backends.

The complete sealed bundle is retained on persistent storage; it has not been
replaced by a compressed archive or qualified for deletion.

```text
Persistent cache: /Users/alex/Library/Caches/vinix-ios
Complete bundle: session-background-20261028 (approximately 8 GiB)
VM state: probe-no-ads-326708
Manifest SHA-256:
6201d8af484562378e88712bd8af6ae7db9f71310bfd153a46b706f2ff6ea553
Runtime SHA-256:
4f4e7303a5988a1cfe0bab16dd5ca5528b07d5d85fed4b3a163baacfeb50405d
Serial SHA-256:
3c18174c9dd95661f774d45894fe8e22ea409b0c21c449631665b821f86cc075
Receipts: audio-category-20261027-work/session-background-*.log
```

Run `BUNDLE/checkpoint check ABSOLUTE_BUNDLE_PATH` from the repository at the
recorded bundle path, with the complete [NSError prior](error-description-checkpoint-20261028.md)
at `/Volumes/VinixAudioActivation20261028/error-description-20261028`.
That historical kernel has dirty-worktree provenance. The frozen V is 0.5.2
`c6bb06f`; these snapshots do not establish a complete compiler/header/library
closure. No historical auditor was weakened.
