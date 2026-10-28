# NSObject identity equality checkpoint — 2026-10-28

Implementation, runtime and frozen auditor: `8414d39c5`. Advertising remains
skipped. NSObject instances and class objects now inherit identity `isEqual:`.
Application overrides, super dispatch and saved IMPs retain their behavior;
existing Foundation value overrides remain in effect. Value classes without
implemented equality remain explicitly unsupported.

Native comparisons and normal and deterministic ASan/UBSan runs pass. They
cover metadata, direct and saved IMPs, replacement and restoration, inheritance,
super dispatch, ownership, eight workers and two drained runtime lifetimes.
All **42 guest fixtures pass**: 35 explicitly reused fixtures and seven freshly
built fixtures. Twelve required host suites and one supplemental Swift layout
suite are reused with their provenance; the equality suite is fresh. The sealed
saved auditor and **297 negative controls** pass, including original resources
and extracted guest-binary comparisons.

Fortnite passes `PLCrashReporter isEqual:` and now stops at
`NSNumber numberWithUnsignedLong:`. Application exit is 1 and capture exit is 0,
without an application signal fault, OOM event or supervisor kill. All six
application budget counters are zero; final usage is 377,604 bytes. The desktop
records 13 builds and 12 polls.

Progress remains **4/8 observable launch gates (50% of the checklist, not an
effort estimate or ETA)**: loading/binding, `+load`, initializers and application
entry. Frame, menu, login and playable match remain unverified. Audio output
and Metal execution/presentation still need backends.

The complete sealed bundle is retained on persistent storage; it has not been
replaced by a compressed archive or qualified for deletion.

```text
Persistent cache: /Users/alex/Library/Caches/vinix-ios
Complete bundle: object-equality-20261028 (approximately 8 GiB)
VM state: probe-no-ads-151666
Manifest SHA-256:
1d355cf00f2a640b05b62f3b1b678042300d5b7880655d8d72be89b5a0507e6e
Runtime SHA-256:
95c18d7320ceb29cbf870f0ca5d53f9e557e36c649b7a05fa23adc5613d9f6c2
Serial SHA-256:
a9727a41273a40b435aa1961f07144befb718e79bbc13820152685922184eae1
Receipts: audio-category-20261027-work/object-equality-*.log
```

Run `BUNDLE/checkpoint check ABSOLUTE_BUNDLE_PATH` from the repository at the
recorded bundle path, with the complete [NSError prior](error-description-checkpoint-20261028.md)
at `/Volumes/VinixAudioActivation20261028/error-description-20261028`.
That historical kernel has dirty-worktree provenance. The frozen V is 0.5.2
`c6bb06f`; these snapshots do not establish a complete compiler/header/library
closure. No historical auditor was weakened.
