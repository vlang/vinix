# GPU heap collection below live allocations

Heap GC now collects every released metadata record, including below a live
allocation. A single descending walk preserves the unvisited prefix and live
record order. Each released record is unlinked before destruction under the
heap lock. The frontier changes only when collecting its current address tail;
later tail collection also recovers gaps whose records were collected earlier.
Live GPU addresses stay fixed. No owning layout or allocation site was added.

The baseline retained 8,192 released records below one live allocation. Its GC
reclaimed zero host malloc blocks. The updated production allocator reclaims all
8,192 blocks / 262,144 bytes while preserving the live record and frontier.
Both samples compile the complete allocator with `-gc none -manualfree` and use
ordinary Darwin malloc statistics. Native slab rates remain unmeasured.

Packaged Asahi's
[`HeapAllocation::drop` and `collect_garbage`](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/alloc.rs)
transfer released range nodes to a garbage vector and drop collected nodes
independently of higher live allocations. This increment aligns metadata
collection with that ownership rule. Vinix still allocates VA from its frontier:
interior gaps remain unavailable until higher allocations are released. Asahi's
best-fit range placement and backing-object policy remain open parity work.
GC now scans tracked records; native runtime cost has not been measured.

Offline validation passed:

- ASan/UBSan exercises 288 combinations of heap-start offsets, alignment and all
  four-pin release orders. Cases collect interiors, append beyond surviving
  pins, release the highest pin, repeat GC and reset fully. Every live record
  keeps its pointer and address; every retired record is poisoned. The existing
  eight release masks and 9,216 padding cases now require all released records
  to be collected while preserving suffix-frontier behavior. The 5,940 bounds
  cases, 13 table-growth boundaries, automatic GC and concurrent statistics
  readers also pass. Padded churn, table growth and three ordinary 10,000-cycle
  samples retain zero additional blocks and bytes.
- Six compiled collection negatives reject the old collector, suffix-only
  collection, stopping at a live record, freeing live records, changing an
  interior frontier and skipping records. Ten generated-C mutations check
  complete scanning, ownership, frontier updates and reader locking. Four heap
  ownership, five bounds, four padding and four table-capacity compiled negatives
  pass. The unchanged bounds and capacity C selftests pass.
- Negative runners select the bounds, padding, capacity or collection suite
  under ASan/UBSan. This lets historical baseline sources reach their intended
  property failure independently of the newer collection rule. The interval
  mutant fails in the direct overflow probe; restoration to a predecessor's
  start fails the fully released padded-heap reset assertion. Initial runs with
  incorrect expected failure labels remain in the external diagnostics.
- Fresh isolated ARM/x86 kernels build. The complete native collector exactly
  matches its expected stack-only C body. Six other heap bodies, ten owning
  declarations, nine GPU lifetime bodies and ten event methods match baseline.
  Both native snapshots match the single allocator overlay; x86 C matches after
  normalizing compiler path hashes. Independent lifetime review found no
  lifetime or aliasing blockers. Descending deletion leaves the unvisited prefix
  intact, predecessor reads precede deletion and the heap lock excludes readers.
- All 60 focused V test files, 150 native storage guards, three storage checker
  selftests, pending-storage checks and native ARM errno probes pass. Existing
  wait, wire, fence, close, async, CPU-cache, VM, sanitized TLB, event, layout,
  render, packet and source-derived wire fixtures pass. Nine completion, eleven
  render, five compute-credit, seven event-credit and four native error compiled
  negatives pass with fresh dependent fixtures.

Allocation-site counts remain 379 ARM / 289 x86 across 833 / 813 source files.
The fresh report exactly matches the verified baseline report. Existing
allowance-check failures remain; no allowance or historical C checker changed.

Fresh heads are Omarchy `3b36b9e19ea00a6c21492098308a7f44a8091564` and packages
`fab37d198dc6b22daf5f17da2f4d10de8346067b`. The three selected package
definitions remain unchanged: Linux `bed544bdf93a496ebf70ba180923bab12b6e01cf`,
Mesa `b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

The whole-driver audit remains **not_equivalent**. Modern UAPI/Mesa integration,
timestamp publication/units, remaining stage backing/event destruction, complete
allocator behavior, manager/UAT replacement, safe firmware teardown, reservation
fences, timelines, remaining wire/default coverage, topology and power/reset
behavior remain open. Native GPU behavior remains unqualified.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-heap-collect-20261117/`.
Baseline is `a64edf9ab3831f02107691b0c9a0eb0fc9a5c082` plus fifteen retained
source paths, including one native overlay. Independent unchanged runners are
reused after source/binary checksum checks; dependent fixtures and kernels are
fresh. The baseline fixture, generated C and binary are retained. The unchanged
historical inventory checker verifies the preceding complete bundle, this
complete bundle and a full archive restoration. Baseline allocator source
matches its commit. Historical C checker modes and their complete original
bundles remain unchanged. `completion.txt` binds sources and reports to the
commit. Generated evidence stays outside Git.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `1ec3b0bfffdc79184f195e58bfb22f89bcf90daf350a717df995a3088568d664` |
| `bundle.tar.gz` | `45c196c853d043077bdad22e82234bf1e1c45a43831c976821a26f6b9c29701c` |
| `bundle/vinix-aarch64` | `c0f49ad836c93f52dbb3dc3a5886675e16c41372b3e2bb7c7e9c0a3d179e10bf` |
| `bundle/vinix-x86_64` | `b11f2ed7284f3792fd176d8394a1f2c27c7236dd0d06ad9944f2a3989eaa4e81` |
| `bundle/blob-aarch64.c` | `2e999f1b4336b9c69dc83dafadfd26b167568318e257e1738c2292584dfdeeb2` |

No GPU workload, firmware interaction, Vinix/QEMU boot, reboot, SSH or deployment occurred.
