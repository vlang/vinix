# Out-of-line Swift Optional checkpoint — 2026-10-28

Implementation, runtime and frozen auditor: `d3052c7df`. Advertising remains
skipped. Complete, copyable and bitwise-takable Wrapped layouts now support
Optional values up to 65,536 bytes with alignment up to eight, including
out-of-line value buffers, shared boxes, Codable temporaries and destruction.
Incomplete and unsupported witness layouts still fail explicitly.

Native comparisons and normal and deterministic ASan/UBSan runs cover layout
boundaries, buffer ownership, owned Strings, reentrant cleanup and concurrency.
All **41 guest fixtures pass**: 35 explicitly reused fixtures and six fresh
Optional lookup, default/configured session and Optional metadata/encoding/
decoding fixtures. Nine required baseline host suites and one supplemental
Swift layout suite are reused from their recorded revisions; three Optional
host suites are fresh. The saved auditor and **273 negative controls** pass,
including original resources and extracted guest-binary comparisons.

Fortnite passes the former 48-byte Wrapped layout rejection and now stops at
`NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:`.
Application exit is 1 and capture exit is 0, without an application signal
fault, OOM event or supervisor kill. All six budget counters are zero; final
usage is 328,118 bytes. The desktop records 16 builds and 15 polls.

Progress remains **4/8 observable launch gates (50% of the checklist, not an
effort estimate or ETA)**: loading/binding, `+load`, initializers and application
entry. Frame, menu, login and playable match remain unverified. Audio output
and Metal execution/presentation still need backends.

The first RAM-only capture was interrupted; no complete launch result survived
and no success is claimed for it. Historical prerequisite bundles were restored
from persistent archives, encoding/decoding host tests rerun, and a fresh
persistent build and launch performed. The complete archive is sealed and its
hashes verify. Restoration passes the complete typed inventory, an independent
comparison against the retained original and the unchanged saved auditor at
the original recorded path. No historical auditor was weakened.

```text
Persistent cache: /Users/alex/Library/Caches/vinix-ios
Original bundle: optional-outline-20261028 (8.0 GiB)
Archive: optional-outline-20261028-archive (1.7 GiB)
SHA-256 of archive.sha256:
d31f44e9335c75adcfe77f0e538d6d77bbd2bd5c575f0ed7543da1626afc3d60
VM state: probe-no-ads-191958
Manifest SHA-256:
5c9385f4b6d2897ed667f47005950ca4a78b9b99d1914ea2b68e6a021466059e
Runtime SHA-256:
ac8895233d410244e8801aac0ec9f0b294158dae34f7f8a5843d67fcb3da8b04
Serial SHA-256:
f68de04df2159b491e6e7be5a0c1affd16ee402aaf6edf5da6b33f101df78bb6
Receipts: audio-category-20261027-work/optional-outline-*.log
```

Restore the complete [configured-session base](session-configured-checkpoint-20261028.md)
at `/Volumes/VinixNSError20261028/session-configured-20261028` before restoring
this archive with `tests/ios/evidence-delta-archive.v`. Run
`BUNDLE/checkpoint check ABSOLUTE_BUNDLE_PATH` from the repository at the
original bundle path, with the complete [NSError prior](error-description-checkpoint-20261028.md)
at its recorded path. That historical kernel has dirty-worktree provenance.
The frozen V is 0.5.2 `c6bb06f`; these snapshots do not establish a complete
compiler/header/library closure.
