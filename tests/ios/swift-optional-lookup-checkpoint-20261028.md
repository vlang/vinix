# Swift Optional lookup checkpoint — 2026-10-28

Runtime and fixtures: `45e07fb52a2bff1d6ebc73e0bbbc6451908e58ff`.
Saved auditor: `59e740abc`. Advertising remains skipped.

Fortnite's rejected type was `ScPSg`, the Swift mangling of `TaskPriority?`.
The bounded name parser now handles postfix Optional wrappers and nested
Array/Optional order through the existing canonical metadata caches. It
validates the complete expression before publishing metadata or invoking
an accessor, with a maximum of 64 wrappers. The existing four lookup entry
points share this behavior.

All seven focused host suites pass both normal and deterministic ASan/UBSan
runs, including native Swift comparisons. They cover mangled lookup, generic
contexts, both metadata-state entry points, Optional metadata and TaskPriority.
The new fixture compares canonical identity and two-byte `TaskPriority?` value
witnesses, protected input and value spans, malformed input before allocation,
eight concurrent publishers and two drained runtimes. The TaskPriority native
test reads an unaligned descriptor as two 32-bit words to avoid undefined
behavior in the reference test itself. All **36 ARM64 guest fixtures pass**.

Fortnite passes this lookup and stops in `NSURLSessionConfiguration` with
`configuration factories, stores, coding and this property are not implemented`.
The original diagnostic capture records the five rejected bytes as
`5363505367`; that diagnostic does not recur in the fixed run. Application exit
is 1 and capture exit is 0. There is no application signal fault, OOM event or
supervisor kill. The desktop peer records 12 builds and 11 polls; its first
tree has one node, zero images and 336 bytes. No compositor is present.

Progress remains **4/8 observable launch gates (50% of the checklist)**:
loading/binding, `+load`, initializers and application entry pass. A game frame,
menu, login and playable match remain unverified. This fraction cannot estimate
remaining effort or time. Audio output and Metal execution/presentation still
need backends. The single-CPU 8 GiB guest retains the tagged reservation,
2 GiB application budget and 1,800-second limit. Budget enforcement and
supervisor isolation checks pass. Final application usage is 328,118 bytes,
with all six budget event counters zero.

The auditor verifies the pinned complete NSError checkpoint, all 35 reused
fixtures and generated C, the retained kernel, original application/framework
binaries and resources. It checks the new runtime, supervisor and Optional
fixture against built-input hashes; extracts and compares guest media inputs;
and requires the seven complete host runs. Its 182 negative controls reject
missing/duplicate markers, application faults, budget events, altered launch
guards, failed host logs and incomplete/changed input lists. An earlier launch
failed before VM execution because the frozen V `os.disk_usage` freed a borrowed
path; the runner now supplies a clone. The failed attempt and successful retry
logs are retained externally.

The kernel is unchanged from the preceding checkpoint; its historical dirty
worktree prevents a reproducible-source claim. Source snapshots and selected
input hashes do not establish the full compiler/header/library closure.

Both captures have complete persistent delta archives, each based directly
on the unchanged [NSError bundle](error-description-checkpoint-20261028.md).
Full restoration, exact typed-inventory comparison and the unchanged saved
auditors are checked at the original recorded paths. Original expanded copies
remain in persistent storage during the round trip.

```text
Cache root: /Users/alex/Library/Caches/vinix-ios
Fixed-run recorded expanded path:
/Volumes/VinixNSError20261028/swift-optional-lookup-20261028
VM state: probe-no-ads-376083
Manifest SHA-256:
49f79a921e76c1c79003567f8560d554a9d3c0bce00c925f95912e9ff3cf397c
Persistent archive: swift-optional-lookup-20261028-archive
archive.sha256 SHA-256:
d1651e9a87ab4afaa5b668fbb14adccec18930570dc26afaa91ced0ac3120db8

Original diagnostic expanded path:
/Volumes/VinixNSError20261028/swift-type-probe-20261028
Runtime source: 9783561eeb2b68b666c8566ee3e3d74211a7187a
VM state: probe-no-ads-673500
Persistent archive: swift-type-probe-20261028-archive
archive.sha256 SHA-256:
a5494402ee2e66b12b9726029bf5c8dc11996d1788eeea986dbbaa06657e1cb5

Required complete prior bundle: error-description-20261028
Prior manifest SHA-256:
8b4028c3d90c69e6b4e418820ab287eb93c8fdc4f6f0ecd10ce99346e069df09
```

The old diagnostic bundle contains its exact saved auditor source/binary and
109-control result; a later runner also passes 117 diagnostic controls.
Its runtime and auditor revisions differ. A failed staging tree containing
symbolic links is preserved separately as
`swift-type-failed-staging-20261028.tar.gz` under the cache root. The maintained
`swift-staging-archive.v` restores and compares all types, modes, link targets,
file lengths and hashes. The archive SHA-256 is
`6dab39e347b560a6fb708806a126a332177d732229e0b56a8e23a22ceaf3aa6a`;
the inventory SHA-256 is
`91cf7fa307d1330105e918b5a7333d898143fc79e6d5bd1356bc08cec76d5d55`.
The original failed tree is retained.

Use `tests/ios/evidence-delta-archive.v` at `af4784177` with the frozen V
compiler. Restore the complete NSError prior and its dependencies first, then
run `verify ARCHIVE` and `restore ARCHIVE FRESH_TARGET FRESH_WORK`. Recreate
the recorded expanded path before running the saved `checkpoint check OUT`.
The archives include their decoder source, compression executables and
non-system libraries; ARM64 macOS system libraries remain prerequisites.
Independent audit and round-trip logs remain in
`audio-category-20261027-work` under the cache root. Expanded `/Volumes` paths
are temporary RAM storage; archives and original-copy backups are persistent.
