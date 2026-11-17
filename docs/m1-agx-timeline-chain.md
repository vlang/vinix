# Modern Asahi cumulative timeline chains

Modern SUBMIT now publishes cumulative chain roots instead of using Vinix's
legacy point map. A later job finishing first cannot release work that still
depends on an earlier unfinished payload. Timeline input point zero preserves
the captured root; positive lookup follows unsigned Linux chain/context rules
and can validly return no dependency for a retired prefix. Zero, duplicate and
decreasing output points are accepted. Chain roots carry no queue provenance,
so same-queue leaf elision cannot bypass the complete prefix.

Each output reserves its node after all sync records have been validated and
snapshotted. Failure releases every unpublished reservation. Publication
transfers metadata to the retained fence graph before child registration;
syscall cleanup then frees only unpublished nodes. Embedded waiter links and a
deduplicated notification queue propagate completion without recursion, nested
fence locks or new allocations. An independent lifetime review found no blocker.

Exported sync-file information unwraps leaves head-first, preserving root names,
capacity validation, root status versus leaf errors and array-before-header
copy ordering. If retirement shrinks the second pass, the original allocation
size is still copied with a zeroed tail, matching the pinned Linux handler.
Identity-only naming does not refresh chain completion on detailed-info errors.

The reference remains packaged Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`. The isolated Vinix baseline is
`85fa9142e09f7ede076fd645ec4bca8f6b2cea17`, plus nine owned kernel files.
Concurrent event-manager edits are excluded. Passed offline checks:

- 41,472 production lookup/readiness results match compiled, unchanged Linux
  chain init/walk/find bodies. All triples of six boundary values, completion
  masks, nil/pending/completed binary predecessors and eight queries are tested.
  Refcount, RCU and lockdep are single-thread host stubs.
- ASan/UBSan chain checks include 10,000 reverse completions, immutable captures,
  poll/callback cancellation and exact-lock registration races. The full async,
  DRM wait/sharing/info and first-completion suites pass. Modern tests include
  every reservation OOM prefix through 129 outputs, two-queue reverse completion,
  same-queue chain waits, retired nil dependencies and packet rollback.
- Three compiled negatives fail their designated readiness, zero-snapshot and
  reservation-cleanup assertions. Sync-file tests inject retirement between
  query passes and tail/header/short-span copy faults.
- Nine warmed batches of 1,000 reservation/release cycles at 1/65/129 outputs
  retain zero host malloc blocks and bytes. This found and removed an implicit
  V boxing allocation in the initial cleanup helper. Its failing probe, C and
  source are retained separately in the evidence. Published metadata and native
  slab rates are excluded from the zero-retention claim.
- AArch64 MP and x86_64 builds pass. Fourteen shared C bodies reject hidden
  allocations; six namespace helpers match the preceding native C. ARM also
  checks seven chain and seven storage bodies, unchanged legacy lookup and
  thirteen unchanged owning paths. The original 18-body modern-adapter checker
  and its six negative controls pass. Shared DRM code changes mean whole-x86-C
  equality is not claimed for this increment.
- All 71 isolated source-contract test files pass, including updated common
  completion, poll and unwrapped-info guards with negative controls. Allocation
  reports remain 377 ARM / 289 x86 sites across 841 / 814 sources. Every
  file/kind count matches the preceding build. Existing allowance failures
  remain; the allowance list is unchanged.

Full parity remains **incomplete**. Legacy map interoperability, generic timeline
ioctls, sync-file merge/array containers, published metadata reclamation,
allocator policy, lazy callback/timestamp timing and actual multi-CPU behavior
are incomplete or unqualified. Purge backing, Mesa migration, firmware/cache
lifecycle and hardware acceptance remain open. No GPU access, firmware execution,
Vinix/QEMU boot or reboot occurred.

Source, runners and checkers are in [the test directory](../tests/drm-timeline-chain/README.md).
The evidence root is
`/Users/alex/.local/state/vinix/omarchy-m1-timeline-chain-20261117/`.
`bundle/qualified/` contains final source snapshots, C/ELFs, test binaries,
logs, the pinned oracle and allocation inventories. Diagnostic boxing evidence
is separate. The preceding complete sync-storage bundle is checked unchanged;
the new complete archive is restored and both named roots are checked. A
post-commit receipt binds committed feature bytes to the sealed source.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `0c9d92e39b3cf9bf48a2bfffc86cb3f51e6f840d64aba3ed3113bb20f822b3bc` |
| `bundle.tar.gz.inventory.txt` | `1f96f61880e811734ec1e1056ab93acb6924e83b1658886c8dbb365bfbde2626` |
| ARM ELF | `2b1a901498d4472f32e452807d01cd90d48490625b791758d09894fc02eb8a27` |
| ARM C | `e71c895fe45787684c3d276bc0d91ae017aec74262360029c704fcefe51deb49` |
| x86 ELF | `0c5a15a683790aa7b14539eb89e3b3b5c95babdcb7f7e018ba4a27d474b386ae` |
| x86 C | `87a3093c21aab9069c19ee5d7f8125cea1efd8dbd7b4f0b0fd05058afdc3c471` |
