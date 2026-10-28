# NSNumber unsigned long checkpoint — 2026-10-28

Implementation, runtime and frozen auditor: `e935123c6`. Advertising remains
skipped. `NSNumber numberWithUnsignedLong:` now preserves the complete 64-bit
range, with measured `q`/`Q` storage encoding and `@24@0:8Q16` factory metadata.

Native comparisons and normal and deterministic ASan/UBSan runs pass. They
cover integer boundaries, decimal text, floating conversion, caller-provided
storage bounds, equality, direct IMPs, signatures, ownership, eight workers
and two drained runtime lifetimes. All **43 guest fixtures pass**: 35 pinned
reused fixtures and eight freshly built fixtures. Thirteen required host suites
and one supplemental Swift layout suite retain their earlier provenance; the
unsigned-number suite is fresh. The sealed saved auditor and **311 negative
controls** pass, including original resources and extracted guest binaries.

Fortnite passes `NSNumber numberWithUnsignedLong:` and now stops at
`NSDictionary dictionaryWithObject:forKey:`. Application exit is 1 and capture
exit is 0, without an application signal fault, OOM event or supervisor kill.
All six application budget counters are zero; final usage is 377,604 bytes.
The desktop records 11 builds and 10 polls.

Progress remains **4/8 observable launch gates (50% of the checklist, not an
effort estimate or ETA)**: loading/binding, `+load`, initializers and application
entry. Frame, menu, login and playable match remain unverified. Audio output
and Metal execution/presentation still need backends.

The complete sealed bundle is retained on persistent storage; it has not been
replaced by a compressed archive or qualified for deletion.

```text
Persistent cache: /Users/alex/Library/Caches/vinix-ios
Complete bundle: number-unsigned-20261028 (approximately 8 GiB)
VM state: probe-no-ads-212750
Manifest SHA-256:
f3f0ff6ac20e3b153fcad32c9bdd08dc06ed08fbcd8adf34bcc72b997c2c4884
Runtime SHA-256:
8bf2f3fd9c619525fed8322d285caca380e54ead9b6d2685d9330d3c7372a3af
Serial SHA-256:
678f6df4085aed3680bbb4f52e93c86a13ebaabca11a2d6fc99745b7f563b96e
Receipts: audio-category-20261027-work/number-unsigned-*.log
```

Run `BUNDLE/checkpoint check ABSOLUTE_BUNDLE_PATH` from the repository at the
recorded bundle path, with the complete [NSError prior](error-description-checkpoint-20261028.md)
at `/Volumes/VinixAudioActivation20261028/error-description-20261028`.
That historical kernel has dirty-worktree provenance. The frozen V is 0.5.2
`c6bb06f`; these snapshots do not establish a complete compiler/header/library
closure. No historical auditor was weakened.
