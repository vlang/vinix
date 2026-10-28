# Default session configuration checkpoint — 2026-10-28

Runtime, fixtures and saved auditor:
`2087fcde2c66d8b2e69cb7d82075b45b5e71b75c`. Advertising remains skipped.

`+[NSURLSessionConfiguration defaultSessionConfiguration]` now returns a fresh,
autoreleased configuration with the supported default settings. Copies preserve
independent settings and distinguish unresolved built-in protocols from an
explicit replacement, including nil. Retrieving the unresolved protocol list,
cache/cookie/credential stores, modern TLS settings and configured URL sessions
remains unsupported. This is a settings factory; network transport is unverified.

The focused host fixture passes native Foundation comparisons and normal and
deterministic ASan/UBSan runs. It checks 20 default properties, independent
mutation, copies across pool drains, concurrent factories, weak cleanup,
constructor failure, two runtimes and 31 explicit unsupported cases. All
**37 ARM64 guest fixtures pass**, including the configuration and Optional lookup
fixtures and 35 unchanged fixtures from the pinned NSError checkpoint.

Fortnite passes the factory call and now stops at:

```text
Optional requires live, complete, copyable inline Wrapped metadata
(at most 24 bytes, alignment at most 8)
```

Application exit is 1 and capture exit is 0. There is no application signal
fault, OOM event or supervisor kill. The desktop peer records 10 builds and
9 polls; its first tree has one node, zero images and 336 bytes. No compositor
is present. Final application usage is 328,118 bytes and all six budget event
counters are zero. The single-CPU 8 GiB guest retains its 2 GiB application
budget, tagged reservation, 1,800-second limit and enforcement/isolation checks.

Progress remains **4/8 observable launch gates (50% of the checklist)**:
loading/binding, `+load`, initializers and application entry. A game frame, menu,
login and playable match remain unverified. This fraction does not estimate
remaining effort or time. Audio output and Metal execution/presentation still
need backends.

The complete expanded bundles are preserved in persistent storage below.
Their saved auditors verify full manifests, original application/resources,
retained kernel, all reused fixtures/generated C, new built inputs and extracted
guest media. The fixed run requires eight complete host suites; seven are
explicitly reused Swift regression runs. Its 207 negative controls reject altered
or incomplete inputs, failed host logs, missing/duplicate fixture markers,
application faults, budget events and changed launch guards. Sealing and an
independent complete check pass. No expanded evidence has been removed.

```text
Cache root: /Users/alex/Library/Caches/vinix-ios
Fixed bundle: session-defaults-20261028
VM state: probe-no-ads-265541
Manifest SHA-256:
8336779e07b86082b1b86c365f68eebf40ff97ad7b320652a5607d617f22692f
Runtime SHA-256:
ff46706421c7214029f7268f616ba9f4c36fadb787edf861e4eda48bfbbe83f0
Serial SHA-256:
45980275b767eeb7932ee286ef49c5933ba0c993de0d8f3370152761f7ee0d23

Preceding diagnostic bundle: session-configuration-selector-20261028
Runtime revision: 1e73258bc301b0487b08d3cbf372e452dd968c01
Auditor revision: 59e740abc3d38a7850a7081bd45345806cbf8db4
VM state: probe-no-ads-437166
Manifest SHA-256:
8bebc36e932734b21b2835ea484145db9fd7178d81747567990c7caccfbf490d
```

The preceding diagnostic identifies `defaultSessionConfiguration` as the actual
unsupported selector; all 36 fixtures and 182 negative controls pass there.
Both captures use the complete [NSError prior](error-description-checkpoint-20261028.md)
with manifest `8b4028c3d90c69e6b4e418820ab287eb93c8fdc4f6f0ecd10ce99346e069df09`.
Run the bundle's saved `checkpoint check ABSOLUTE_BUNDLE_PATH` after restoring
its dependencies at their recorded paths. Audit logs remain under
`audio-category-20261027-work` in the cache root. The historical kernel includes
dirty-worktree provenance; snapshots and selected hashes do not establish a
complete compiler/header/library closure or reproducible source build.
