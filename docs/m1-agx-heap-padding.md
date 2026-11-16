# GPU heap alignment-padding reclamation

GC now restores the frontier before each reclaimed reservation, including its
leading alignment padding. The preceding record's end supplies that frontier;
an empty heap returns to its original start. Live prefixes keep their addresses
and metadata. Each released suffix record is still unlinked before destruction
under the heap lock. No metadata layout or allocation site was added.

The previous allocator restored the aligned allocation address instead. A pair
of page-aligned and four-page-aligned reservations left 65,536 VA bytes and one
released record stranded after GC. After warmup, 10,000 such pairs retained
655,360,000 VA bytes, 10,000 records and 619,008 host malloc bytes in 10,004 blocks.
The fixed source retains zero VA bytes, records, blocks and bytes in that sample.
These are host measurements of production allocator code compiled with
`-gc none -manualfree`; native kernel slab rates remain unmeasured.

Packaged Asahi's
[`HeapAllocation` and `HeapAllocator::alloc_inner`](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/alloc.rs)
use owned range nodes and best-fit insertion. Alignment gaps do not become
permanent reservations in that range allocator. This fix closes Vinix's
stranded-padding gap; its grow-only heap still lacks Asahi's interior-hole reuse
and complete allocator behavior.

Offline validation passed:

- ASan/UBSan exercises 9,216 combinations of heap-start offsets, three alignment
  choices, all release masks and all six release orders. An independent model
  saves each reservation frontier before allocation. GC must restore that
  frontier, preserve live prefixes, free retired records and remain idempotent.
  Allocation-triggered GC recovers the complete padded range. The existing 5,940
  bounds cases, concurrent statistics readers and suffix ownership tests pass.
  Three ordinary 10,000-cycle samples also retain zero blocks and bytes.
- Four compiled padding counterexamples catch the original gap, a wrong initial
  frontier, restoration to the preceding record's start and destruction of live
  prefixes. Eight generated-C mutations check ownership, reader locking and
  frontier restoration. Five compiled bounds and four heap ownership negatives,
  plus the unchanged five-case bounds C selftest, pass.
- Fresh isolated ARM/x86 kernels build. Native generated C differs from baseline
  GC only by the exact stack-only frontier calculation. Six other heap bodies,
  ten owning declarations, nine GPU lifetime bodies and ten event methods match.
  Both native input snapshots match the single allocator overlay; x86 C matches
  after normalizing compiler path hashes. Independent lifetime review found no
  lifetime or aliasing blockers.
- All 58 focused V test files, 150 native storage guards, three storage checker
  selftests, pending-storage checks and native ARM errno probes pass. Existing
  wait, wire, fence, close, async, CPU-cache, VM, sanitized TLB, event, layout,
  render, packet and source-derived wire fixtures pass. Nine completion, eleven
  render, five compute-credit, seven event-credit and four native error compiled
  counterexamples pass with fresh dependent fixtures.

Allocation-site counts remain 379 ARM / 289 x86 across 833 / 813 source files.
The fresh report exactly matches the complete verified baseline report. Existing
allowance-check failures remain; no allowance or historical checker was changed.

Fresh heads are Omarchy `3b36b9e19ea00a6c21492098308a7f44a8091564` and packages
`6801f0c1905597cd9db3d95dd1c5ae09cabf1ccb`. All three selected package
definitions remain unchanged: Linux `bed544bdf93a496ebf70ba180923bab12b6e01cf`,
Mesa `b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

The whole-driver audit remains **not_equivalent**. Modern UAPI/Mesa integration,
timestamp publication/units, remaining stage backing/event destruction, complete
allocator behavior, manager/UAT replacement, safe firmware teardown, reservation
fences, timelines, remaining wire/default coverage, topology and power/reset
behavior remain open. Native GPU behavior remains unqualified.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-heap-padding-20261117/`.
Baseline is `120e52fbaa2a3eeff666efea29c5bfb608dd1791` plus nine retained source
paths, including one native overlay. Independent unchanged runners are reused
after source/binary checksum checks; dependent fixtures and kernels are fresh.
The unchanged historical inventory checker verifies the preceding complete
bundle, this complete bundle and a full archive restoration. Original allocator
source matches the baseline commit. Historical proof modes and their complete
original bundles remain unchanged. `completion.txt` binds sources and reports
to the commit. Generated evidence stays outside Git.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `063f3f4ab7ce7023d9faf532fb92777e8b8fa420fca977428289dc591ad78181` |
| `bundle.tar.gz` | `db1cf92eaaa0b941c4548c3cd7fdbf9d6fe2940bcebd842868505f39e28f33f7` |
| `bundle/vinix-aarch64` | `aa5d5211dedb4d33f505ee2917a9de83e3e0d9d2ccffdbd813fba210fb7a1810` |
| `bundle/vinix-x86_64` | `b0f0ccc105ec9be2fb3e415523181f43d9e2c9f36ddd56cb2879139802095b5b` |
| `bundle/blob-aarch64.c` | `e5546658789a050443a302fa744b8efbdea632a8e8e255778b73b25ced34376c` |

No GPU workload, firmware interaction, Vinix/QEMU boot, reboot, SSH or deployment occurred.
