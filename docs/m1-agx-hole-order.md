# GPU hole insertion history

Equal-size eligible holes now prefer the newest insertion rather than the lowest
address. Splitting removes the old hole and inserts the leading remainder before
the trailing remainder. Collection removes both adjacent holes and reinserts
the coalesced predecessor hole. Allocation records retain their addresses and
VA order, and pending releases still occupy their ranges until GC.

The reference is Omarchy's packaged Linux-Aurora
[`drm_mm.c`](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_mm.c).
`insert_hole_size` places equal keys on the right; `best_hole` searches right for
the smallest fit and subsequent candidates use `rb_prev`. Since rotations
preserve in-order traversal, the inferred policy is newest eligible insertion
among equally sized holes. Its split and removal paths specify the same
leading/trailing and coalescing insertion order now used by Vinix.

Three nonowning scalar fields track recency: one following-hole rank per record,
plus head-hole rank and hole count in the heap. Removing a rank compacts larger
ranks. Current holes occupy exactly `1..hole_count`; no lifetime counter can
wrap. All updates hold the existing heap lock, and no new allocation, pointer
owner or metadata destruction path is introduced. The existing collector still
unlinks each released record before freeing it.

The same insertion/removal stream is a deliberate scope limit. Vinix GC remains
descending by VA. Asahi drains a count-limited prefix from its deferred-garbage
vector; release policy, batch size and timing still differ. Thus complete
allocation histories are **not equivalent**. Vinix's scans, rank compaction and
pointer rotation also differ from upstream's tree-backed costs. Backing-object
and accounting behavior remain open, and native performance is unmeasured.

Offline validation passed:

- Three targeted probes cover a newer high hole beating an older low hole,
  equal leading/trailing split remainders and alignment fallback to an older
  eligible hole. The original allocator fails the first probe at runtime.
- ASan/UBSan runs 9,216 seeded allocation/release/collection steps against an
  independent chronological hole list and candidate-enumeration model. Another
  run checks every production rank, including zero for occupied adjacency,
  against that list after each step. Reservations remain in creation order in
  the model; collection explicitly supplies the production descending-VA stream.
- The full sanitized heap suite passes existing 3,072 fragmented-placement,
  9,216 padding, 5,940 bounds and 288 collection cases, 13 table-growth boundaries,
  10,000 concurrent churn cycles and 80,000 locked statistics reads. Ordinary,
  padded and capacity-growth malloc samples retain zero additional blocks/bytes.
  Interior GC still reclaims 8,192 blocks / 262,144 host malloc bytes below a pin.
- Eight compiled history negatives and fourteen generated-C mutations reject
  reversed/omitted ties, split ordering, stale coalescing, unbounded counts,
  missing compaction, bounds violations and ownership errors. Existing four heap,
  five bounds, four padding, four capacity, six collection and eight reuse
  compiled negatives pass. Construction checks and eight C selftests pass.
- Fresh isolated ARM/x86 kernels build from one allocator overlay. Generated C
  confirms allocation-free rank helpers, checked placement and one explicit
  stable record owner. Removing only the exact scalar bookkeeping block restores
  the previous GC body. Four heap bodies, ten owning declarations apart from the
  three new scalars, nine GPU lifetime bodies and ten event methods preserve
  baseline ownership. Independent review found no lifetime or rank blockers.
- All 62 focused V test files, 150 native storage guards, three storage checker
  selftests, pending-storage checks and native ARM errno probes pass. Existing
  wait, wire, fence, close, async, CPU-cache, VM, sanitized TLB, layout, render,
  packet and source-derived wire fixtures pass. Two hundred sanitized production
  heap/page-table reuse cycles preserve invalidation order and live pins, and
  release all page tables. Privileged operations are replaced by host fixtures.

Allocation-site reports exactly match the verified preceding report: 379 ARM /
289 x86 sites across 833 / 813 source files. Existing allowance-check failures
remain unchanged; no allowance or historical checker was changed. Host malloc
measurements do not qualify native slab rates.

Fresh remote heads remain Omarchy `3b36b9e19ea00a6c21492098308a7f44a8091564` and
packages `fab37d198dc6b22daf5f17da2f4d10de8346067b`. Selected package definitions
are unchanged: Linux `bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

The whole-driver source audit remains **not_equivalent**. Deferred garbage
policy, complete allocator behavior, modern ioctl/Mesa integration, timestamp
publication/units, remaining stage backing/event destruction, manager/UAT
replacement, firmware/cache teardown qualification, reservation fences,
timelines, remaining wire/default coverage, topology and power/reset remain open.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-hole-order-20261117/`.
Native baseline is `d57544095d05c6ab21f59831b214a57ab273daec` plus thirteen
retained source paths, including one native overlay. Unchanged independent
runners are reused after checksums; dependent fixtures and kernels are fresh.
The original complete inventory checker verifies the preceding bundle, current
bundle and complete archive restoration. Sources and reports are bound to the
commit in `completion.txt`; generated artifacts remain outside Git. Historical
checkers and complete original evidence bundles retain their original contracts.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `c609d1cc650f897cf793f8d39425a6cc3f8d669ccf689a94f636fe33ed59c3a3` |
| `bundle.tar.gz` | `f2fe377c8de3d0e7ce58d23c1785b8a925560d32dc110a797eb81ad3ee3fb6ce` |
| `bundle/vinix-aarch64` | `1f9f0d366f07222de13626461616bf5c12258ade2f139b415ed7fe83a9b6d97f` |
| `bundle/vinix-x86_64` | `1480ce76d6706ce46cb1e42b07fe9ff90a6270b27fd1b8809d1707cc790ed236` |
| `bundle/blob-aarch64.c` | `c7310d689fb2b095109c18e3ab4aa0ad978415bc23bee899f8f652c0894f16dd` |

No GPU workload, firmware interaction, Vinix/QEMU boot, reboot, SSH or deployment occurred.
