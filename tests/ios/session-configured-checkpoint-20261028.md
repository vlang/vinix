# Configured URL session checkpoint — 2026-10-28

Implementation: `894d0238a`. Runtime and frozen auditor:
`e6192a768a8f6384a2252f7b735e79eea6c513d1`; the iOS source is identical to
the implementation revision. Advertising remains skipped.

`NSURLSession` configured factories now retain their delegate and queue before
callbacks and use independent configuration snapshots. Native comparisons and
normal and deterministic ASan/UBSan runs cover reentrant copying and cleanup,
failed copies, replacement, changed object classes, pools and concurrent reads.
Custom subclasses and URL transport remain unsupported.

All **38 guest fixtures pass**: 35 explicitly reused fixtures and three fresh
lookup/default/configured-session fixtures. Eight required baseline host suites
and one supplemental Swift layout suite are reused from their recorded
revisions; the configured-session host suite is fresh. The saved auditor and
**231 negative controls** pass, including original resources and extracted
guest-binary comparisons.

Fortnite still stops at Optional Wrapped metadata: **48 bytes, alignment 8,
flags `0x30007`, extra inhabitants 2,147,483,647**. It does not reach a later
configured-session boundary. Application exit is 1 and capture exit is 0,
without an application signal fault, OOM event or supervisor kill. All six
budget counters are zero; final usage is 328,118 bytes. The desktop records
13 builds and 12 polls.

Progress remains **4/8 observable launch gates (50% of the checklist, not an
effort estimate or ETA)**: loading/binding, `+load`, initializers and application
entry. Frame, menu, login and playable match remain unverified. Audio output
and Metal execution/presentation still need backends.

The complete archive is sealed and verified; restoration passes its complete
typed inventory and the unchanged saved auditor. The first archive attempt
ran out of scratch space and remains separately recorded; the successful
retry used the larger NSError RAM volume. No historical auditor was weakened.

```text
Expanded bundle: /Volumes/VinixNSError20261028/session-configured-20261028
Persistent cache: /Users/alex/Library/Caches/vinix-ios
Archive: session-configured-20261028-archive (1.6 GiB)
SHA-256 of archive.sha256:
d070efb91e9f566d4a2d8f2af346cba931707ae8b0080623bb8ef1ae4a2cbdba
VM state: probe-no-ads-273333
Manifest SHA-256:
8e747cf77bfbc365388ca470162e6ba381693964123d70fef27c83563d3d3cfd
Runtime SHA-256:
496f0a8cc7c5ef9fabe9ebd92732c8280c8ec8da73561109b131b1c1a2735b99
Serial SHA-256:
a5bebbd823f3d4cec7f67ee4d94e67650e35639d7dd51c224e30e891b06fdd0a
Receipts: audio-category-20261027-work/session-configured-*.log
```

Run `BUNDLE/checkpoint check ABSOLUTE_BUNDLE_PATH` from the repository with
the complete [NSError prior](error-description-checkpoint-20261028.md) at its
recorded path. That historical kernel has dirty-worktree provenance; these
snapshots do not establish a complete compiler/header/library closure.
