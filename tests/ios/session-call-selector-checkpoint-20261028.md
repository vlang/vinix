# Session selector diagnostic checkpoint — 2026-10-28

Runtime and frozen auditor: `ff83fa79d2e54fb4855994737b08d06ac15fd6e4`.
The session selector diagnostic is implemented by that revision; this capture
does not emit it. Advertising remains skipped.

All **37 guest fixtures pass**. Eight required host suites and the supplemental
Swift layout suite are explicitly reused from their recorded revisions; a fresh
session selector suite also passes native comparisons and normal and
deterministic ASan/UBSan runs. These are separate from the subsequent configured
session implementation.

Fortnite reproduces the Swift Optional layout rejection instead of reaching the
URL session diagnostic. The rejected Wrapped value is **48 bytes, alignment 8,
flags `0x30007`, extra inhabitants 2,147,483,647**. The flags describe a non-POD,
non-inline value. This is an unsupported out-of-line layout, not evidence of
incomplete metadata. Supporting it requires correct buffer ownership and value
operations as well as larger temporary storage; merely raising the 24-byte
limit would overrun existing Optional temporaries.

Application exit is 1 and capture exit is 0, with no application signal fault,
OOM event or supervisor kill. All six budget event counters are zero; final
application usage is 328,118 bytes. The desktop peer records 17 builds and
16 polls. No game frame is verified. Progress remains **4/8 observable launch
gates (50% of the checklist, not an effort estimate or ETA)**: loading/binding,
`+load`, initializers and application entry. Frame, menu, login and playable
match remain unverified; audio output and Metal execution/presentation still
need backends.

The initial run failed the guest budget self-test before application entry
(budget-check wait status 35,584, signal 11). Its complete logs, firmware state,
media hashes and retry executable/source/revision are retained under
`budget-failure-96482`. The verified replay uses the original frozen VM/media,
one CPU, 8 GiB guest memory, 2 GiB application budget and 1,800-second guard.
Media hashes are checked before and after replay. The retry runner is from
`aeff3693b`; neither the runtime nor the saved checkpoint auditor was replaced.

The unchanged saved auditor passes sealing and an independent complete check,
including extracted media and original application/resource comparisons. All
**207 negative controls** reject corrupted evidence. The complete expanded
bundle is retained in persistent storage.

```text
Cache root: /Users/alex/Library/Caches/vinix-ios
Bundle: session-call-selector-20261028
VM state: probe-no-ads-624083
Manifest SHA-256:
875ea465d1b12bbb6d3c01d2357ed49185c3f3698869cf0f347fc97f0b6e101d
Runtime SHA-256:
cde990a2a84c423f077187ebdc192b0696a220e84661105149a0ede6cc127f51
Serial SHA-256:
2f1ec7bc4070cf14af478a1171a67de9cc0a5f2538b7b56c04e22c9f4509f463
Audit logs: audio-category-20261027-work/session-call-selector-*.log
```

Run `BUNDLE/checkpoint check ABSOLUTE_BUNDLE_PATH` from the repository with the
complete [NSError prior](error-description-checkpoint-20261028.md) restored at
its recorded path. Its historical kernel has dirty-worktree provenance; these
snapshots do not establish a complete compiler/header/library closure.

The redundant RAM restorations of `swift-type-probe-20261028` and
`swift-optional-lookup-20261028` have now been removed. Their persistent
`*-archive` directories remain. Before removal, both complete trees passed
fresh archive verification and exact typed inventory comparison; their earlier
full restoration and unchanged-auditor receipts also passed. Receipts are in
`audio-category-20261027-work/reclaim-restored-swift.log` and the
`swift-diagnostic-roundtrip` and `swift-optional-roundtrip` directories.
No historical evidence requirement was weakened.
