# Single-entry dictionary checkpoint — 2026-10-28

Implementation, runtime and frozen auditor: `9c1ed5d92`. Advertising remains
skipped. `NSDictionary dictionaryWithObject:forKey:` and the inherited mutable
factory now copy the key and retain the value, with measured `@32@0:8@16@24`
metadata. Copy callbacks can reenter the runtime without invalidating a saved
destination header.

Native comparisons and normal and deterministic ASan/UBSan runs pass. They
cover method scope, signatures, direct IMPs, empty/Unicode/embedded-NUL mutable
keys, mutable values, numeric keys, lookup, mutation, ownership, eight workers,
application copy callbacks, nil rejection and two balanced runtime lifetimes.
All **44 guest fixtures pass**: 35 pinned reused fixtures and nine freshly
built fixtures. Fourteen required host suites and one supplemental Swift layout
suite preserve their earlier provenance; the dictionary suite is fresh. The
sealed saved auditor and **325 negative controls** pass, including original
resources and extracted guest binaries.

Fortnite passes `NSDictionary dictionaryWithObject:forKey:` and now stops at
`NSMutableDictionary dictionaryWithObjectsAndKeys:`. Application exit is 1 and
capture exit is 0, without an application signal fault, OOM event or supervisor
kill. All six application budget counters are zero; final usage is 426,862
bytes. The desktop records 12 builds and 12 polls.

Progress remains **4/8 observable launch gates (50% of the checklist, not an
effort estimate or ETA)**: loading/binding, `+load`, initializers and application
entry. Frame, menu, login and playable match remain unverified. Audio output
and Metal execution/presentation still need backends.

The complete sealed bundle is retained on persistent storage; it has not been
replaced by a compressed archive or qualified for deletion.

```text
Persistent cache: /Users/alex/Library/Caches/vinix-ios
Complete bundle: dictionary-single-20261028 (approximately 8 GiB)
VM state: probe-no-ads-231708
Manifest SHA-256:
f58b7f0b1010ec29b37828d2de5fff421c20200e73fabeedfb108648360f9d07
Runtime SHA-256:
3a20d119fa7795b91b949a5d58261030e9d244f5d00df1f0822b926239481dae
Serial SHA-256:
96dfdfaa75a15743db4928f0826046ebb1658e6c8930d4c1cab7beb0a86177c5
Receipts: audio-category-20261027-work/dictionary-single-*.log
```

Run `BUNDLE/checkpoint check ABSOLUTE_BUNDLE_PATH` from the repository at the
recorded bundle path, with the complete [NSError prior](error-description-checkpoint-20261028.md)
at `/Volumes/VinixAudioActivation20261028/error-description-20261028`.
That historical kernel has dirty-worktree provenance. The frozen V is 0.5.2
`c6bb06f`; these snapshots do not establish a complete compiler/header/library
closure. No historical auditor was weakened.
