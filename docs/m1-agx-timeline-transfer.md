# DRM timeline destination transfers

Positive `DRM_IOCTL_SYNCOBJ_TRANSFER` destination points now flatten source
chains/arrays and publish a cumulative destination chain. Completed leaves are
removed. No pending leaves produce a private successful stub with the latest
observed timestamp; one pending leaf is borrowed; multiple contexts produce a
flat array sorted by context, keeping the greatest unsigned sequence per context.
Private storage unwinds if merge or chain allocation fails, before publication.
Binary destination transfers retain their existing path.

Flat arrays support lazy readiness and callback activation, first-error
selection, and nonrecursive parent notification. Callback membership/count and
immutable children exist before activation. Reservation ownership transfers
before any callback can observe the payload; reservation cleanup does not modify shared leaves.
Draining occurs after publication unlock. Sync-file info unwraps array leaves
and names array roots. Arrays keep the established retained-metadata policy.

Review found and corrected two integration issues: G13 public fence contexts
now use unique queue identities so independent queues of one file cannot be
deduplicated together, and array errors use explicit `i64` atomic storage so ARM
preserves negative errors. Tests exercise both completion orders for two queues
with the same owner, lazy/enabled array errors and the generated ARM 64-bit loads.

Reference: packaged Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`. Isolated Vinix builds use
`480367cfb7415fa0e9d0001f25055c21b912843c` plus eleven owned kernel overlays;
concurrent event edits are excluded. Passed offline checks:

- Full ASan/UBSan DRM regressions, 51 counted transfer cases and array protocol
  checks: every merge/array/chain OOM position, exact private unwind, completed
  prefixes, context deduplication, timestamps, one/zero pending leaves after
  inter-pass retirement, and sync-file flattening. Arrays of 129/4096 leaves
  cover sorting, activation, completion fanout and one final wake. Three compiled
  negatives fail designated cleanup, latest-sequence and first-error assertions.
  The sanitized G13 async/modern/chain suite also passes, including queue
  dependency elision, foreign waits, reverse retirement and recreated identities.
- All 8,640 outcomes match compiled unchanged pinned transfer/find/chain,
  array allocation/init/lazy readiness, unwrap, sorting/dedup and merge bodies.
  Cases cover unsigned context/sequence boundaries, completed subsets, retired
  source points, MAX values and pending destination prefixes. Refcount/RCU/time/
  callback and allocation plumbing are host stubs. The complete preceding
  binary-transfer bundle is rechecked before reusing its infrastructure.
  Earlier wrapper compile/model failures remain separately retained.
- Nine warmed 1,000-cycle host batches fail each of the merge pointer-table,
  array/callback metadata and chain allocations, retaining zero malloc blocks
  and bytes. Successful publication intentionally retains metadata; this does
  not qualify native slab retention or published reclamation.
- AArch64 MP and x86_64 builds and all 76 source-contract files pass. Generated C
  rejects hidden allocations in merge/array/unwrap/atomic/transfer/info paths,
  confirms two fallible owners and private unwind, explicit signed 64-bit error
  CAS/load, conditional reservation transfer and drain-after-unlock. Eleven
  shared lookup/wait/query/signal/capture bodies match baseline, plus ARM's error
  getter; the old x86 getter was pruned. Independent lifetime review covers the
  corrected ownership and callback paths.
- Allocation diagnostics remain 377 ARM / 289 x86 sites across 851 / 824 source
  files, with matching file/kind counts and existing allowance failures. The
  allowance list is unchanged. These diagnostics do not enumerate every explicit
  allocator call; generated-C ownership checks and host measurements supplement
  them.

Full parity remains **incomplete** and the generic timeline capability stays
disabled. Native chains activate callbacks eagerly; Linux activation/irq-work
timing can differ. The comparison qualifies functional merge/readiness outcomes,
not actual multi-CPU scheduling, error/timestamp race timing or native performance.
Legacy map interoperability, published metadata reclamation, remaining syncobj
UAPI/Mesa integration, firmware/cache lifecycle and hardware acceptance remain
incomplete or unqualified. No GPU access, firmware execution, Vinix/QEMU boot or
reboot occurred.

The fake backend still creates file-wide public fence contexts and is outside
the verified G13 identity correction. Its cross-queue merging remains a separate
parity gap; keeping the generic timeline capability disabled avoids advertising
complete support there.

Maintained [tests and runners](../tests/drm-timeline-transfer/README.md) stay in Git.
Complete source, primary reference bodies, native C/ELFs, sanitized executables,
negatives, malloc probes, source contracts and review are retained at
`/Users/alex/.local/state/vinix/omarchy-m1-timeline-transfer-20261117/bundle/`.
Complete archive restoration and both named roots are checked; a post-commit
receipt binds committed feature bytes to the sealed source.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `dfd6ef5c7f2f535591994dcc074134f5e348457b4c2e4253dcefc6a4f351813f` |
| `bundle.tar.gz.inventory.txt` | `e0195ee3e8d605848754e878a8592d58fabf076f56e1f2b505f1126d8698d33d` |
| ARM ELF | `38bee6b5d2af4ba17f685faa152ba12f334c565a3dbb374862f6b10a28e4684c` |
| ARM C | `c6ae85258a8c5dc6cad06975530f4a1a305ad06889b2f41d3c70fce0c52bd08b` |
| x86 ELF | `6e0e0b9a271140bde3ed03ed6504fdc8cb7af3470ee60518d97196956a01d765` |
| x86 C | `241b7204d7cfb971f41c6b6af52d29d33c7c7dedf2ba03ebc9c1ae11bbb40ff2` |
