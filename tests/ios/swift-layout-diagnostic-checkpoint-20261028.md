# Swift layout diagnostic checkpoint — 2026-10-28

Runtime and frozen auditor: `a277e5104b618dcaeac4207f5fb615c0506eab01`.
The Swift rejection diagnostic is implemented by `0c18d7d9f`; interrupted
staging recovery is implemented by `c816386cf`. Advertising remains skipped.

All **37 guest fixtures pass**. Eight previously qualified host suites are
explicitly reused; a ninth, fresh Swift diagnostic suite passes native
comparisons and normal and deterministic ASan/UBSan runs. The new diagnostics
report bounded scalar layout/witness information without following rejected
pointers or invoking witnesses. They do not relax Optional's layout checks.

This launch **does not reproduce the preceding Optional rejection**. No Swift
rejection diagnostic is emitted. Fortnite instead reaches the existing generic
unsupported URL session panic. This does not establish that the Optional issue
is fixed or explain the different startup path. A subsequent selector diagnostic
is needed to identify the URL session call.

Application exit is 1 and capture exit is 0, with no application signal fault,
OOM event or supervisor kill. All six budget event counters are zero; final
application usage is 328,118 bytes. The desktop peer records 12 builds and
12 polls; its first tree has one node, zero images and 336 bytes. No compositor
or game frame is verified. The single-CPU 8 GiB guest retains its 2 GiB
application budget, tagged reservation and 1,800-second guard.

Progress remains **4/8 observable launch gates (50% of the checklist)**:
loading/binding, `+load`, initializers and application entry. A frame, menu,
login and playable match remain unverified. This fraction is not an estimate
of remaining effort or time; audio output and Metal execution/presentation
still need backends.

The interrupted compression was resumed only after validating the staged
overlays and complete reused/built input hashes. The partial gzip archive is
retained as `initramfs-interrupted.tar.gz`; the complete replacement, boot image,
source/generated C and recovery executable/source/revision are also preserved.
The unchanged saved auditor passes sealing and an independent complete check,
including extracted boot media and original application/resource comparisons.
All **207 negative controls** reject corrupted evidence. The complete expanded
bundle is retained in persistent storage; it has not been deleted.

```text
Cache root: /Users/alex/Library/Caches/vinix-ios
Bundle: swift-optional-layout-20261028
VM state: probe-no-ads-278791
Manifest SHA-256:
9df551e937382bde02de7e957b1093d755445673a4c3f222cad3374d10392fae
Runtime SHA-256:
6cbdd7e92660d302695b14be7262f432ef75535b2105fba3b3fa78c21ac036e0
Serial SHA-256:
0f810fe085946d0cc9be103627a0558492619b9dcc732fb2101e8809e5f55738
Audit logs: audio-category-20261027-work/swift-optional-layout-*.log
```

Run `BUNDLE/checkpoint check ABSOLUTE_BUNDLE_PATH` with the pinned complete
[NSError prior](error-description-checkpoint-20261028.md) restored at its recorded
path. Its historical kernel includes dirty-worktree provenance; the snapshots
do not establish a complete compiler/header/library closure or reproducibility.

The older `swift-type-probe-20261028` and `swift-optional-lookup-20261028`
captures remain available as persistent `*-archive` directories in the cache
root and complete restored bundles on `/Volumes/VinixNSError20261028`.
Only their redundant `*-original` copies were removed after archive verification,
complete restoration, exact typed inventory comparison and unchanged-auditor
success. Receipts are in `audio-category-20261027-work/swift-diagnostic-roundtrip`
and `swift-optional-roundtrip`; no historical evidence requirement was weakened.
