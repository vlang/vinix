# Variadic dictionary checkpoint — 2026-10-28

Implementation, runtime and frozen auditor: `7422773df`. Advertising remains
skipped. `NSDictionary dictionaryWithObjectsAndKeys:` and the mutable factory
now read anonymous arguments from the Darwin arm64 stack, stop at the nil
value sentinel, copy keys and retain values. Metadata is `@24@0:8@16`.
Native comparisons establish that the immutable factory keeps the first
duplicate key's value and the mutable factory keeps the last. Lists over
65,536 pairs and nil keys are explicitly rejected.

Native comparisons and normal and deterministic ASan/UBSan runs pass. They
cover class scope, signatures, message and direct IMP calls with poisoned
unused registers, empty lists, eight pairs, duplicate keys, Unicode and
embedded NULs, mutable keys and values, ownership and eight workers. Runtime
checks also cover reentrant key-copy callbacks, protected pages at the nil
sentinel, five rejection cases and two balanced runtime lifetimes.

All **45 guest fixtures pass**: 35 pinned reused fixtures and ten freshly built
fixtures. Fifteen required host suites and one supplemental Swift layout suite
retain their earlier provenance; the variadic dictionary suite is fresh.
The sealed auditor and **339 negative controls** pass, including original
resources and extracted guest binaries.

Fortnite passes `NSMutableDictionary dictionaryWithObjectsAndKeys:` and stops
at the existing StoreKit purchase/request guard:
`StoreKit payment and request construction or operations are not implemented`.
That guard reports neither the receiver nor the selector, so this capture
does not establish the particular StoreKit operation. Application exit is 1
and capture exit is 0, without an application signal fault, OOM event or
supervisor kill. All six application budget counters are zero; final usage is
426,862 bytes. The desktop records 12 builds and 12 polls.

Progress remains **4/8 observable launch gates (50% of the checklist, not an
effort estimate or ETA)**: loading/binding, `+load`, initializers and application
entry. Frame, menu, login and playable match remain unverified. Audio output
and Metal execution/presentation still need backends.

The complete sealed bundle has a persistent copy with an exact typed inventory
comparison, including every file's hash and permissions. The original RAM-disk
bundle remains at its recorded path. Neither expanded copy has been removed;
archive restoration and deletion qualification are not claimed.

```text
Persistent cache: /Users/alex/Library/Caches/vinix-ios
Complete persistent copy: dictionary-variadic-20261028 (approximately 8.6 GiB)
Recorded bundle: /Volumes/VinixNSError20261028/dictionary-variadic-20261028
VM state: probe-no-ads-132916
Manifest SHA-256:
c1163dfbb2bf9b0f096eba6123246028b00a43902ebd9963b115909b999e3dbb
Runtime SHA-256:
a48b3823de759a25eff52e4556a039f85f616c5d2590753ffc1bdb22c54ce4ee
Serial SHA-256:
aebc0a7cb9f514cb7cd9db98aeed41640ea4c8854d0be6cbb06f8d5122f32bc7
Receipts: audio-category-20261027-work/dictionary-variadic-*.log
Copy receipts: audio-category-20261027-work/dictionary-variadic-preservation/
Comparison: audio-category-20261027-work/dictionary-variadic-preservation-retry1/
```

Run `BUNDLE/checkpoint check ABSOLUTE_BUNDLE_PATH` from the repository at the
recorded RAM-disk path. If that path is gone, first copy the complete persistent
bundle back to that fresh path. The complete [NSError prior](error-description-checkpoint-20261028.md)
remains at `/Volumes/VinixAudioActivation20261028/error-description-20261028`.
That historical kernel has dirty-worktree provenance. The frozen V is 0.5.2
`c6bb06f`; these snapshots do not establish a complete compiler/header/library
closure. No historical auditor was weakened.
