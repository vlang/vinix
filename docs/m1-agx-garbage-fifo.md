# Bounded FIFO deferred GPU collection

Deferred allocation records now retire in release order, replacing descending-VA
collection. `collect_garbage(count)` retires at most the oldest requested prefix;
zero leaves it untouched and oversized counts clamp to the current pending
count. Existing `gc()` and allocation-pressure retry still collect all pending
records. `garbage()` returns their count and rounded reservation bytes.

The packaged Asahi
[`alloc.rs`](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/alloc.rs)
appends deferred nodes, drains a count-limited prefix and subtracts their node
sizes. Pinned KVec drain advances its forward iterator; clear/truncate drops
the resulting slice. Rust specifies first-to-last slice destruction in its
[destructor rules](https://doc.rust-lang.org/reference/destructors.html#destructors.operation).
Together these establish release FIFO order for that path.

One nonowning rank per record and pending count/byte fields per heap implement
the FIFO without allocating a second container. Release assigns a rank only on
the live-to-released transition. Collection repeatedly finds rank one, updates
hole coalescing/frontier state, decrements counters and compacts higher ranks,
then unlinks and frees the record. All updates hold the existing lock; ranks
remain bounded and live record addresses stay fixed. Independent review found
no lifetime, locking, FIFO-rank or accounting blockers.

This matches removal order for the same deferred-release and collection calls.
Manager pacing, block capacity, optional immediate destruction, backing objects
and broader accounting still differ. Vinix keeps one lock across each collection
call; upstream moves batches out of its inner lock before dropping nodes. Native
performance and complete concurrent allocation histories remain unqualified.

Offline validation passed:

- The previous allocator fails the low-then-high full-GC probe. The fixed code
  checks both release orders independently of VA. ASan/UBSan runs 19,440
  six-release-permutation/count/offset cases and 10,240 mixed partial-GC/reuse
  steps against an independent address FIFO and chronological-hole model.
  Counts, rounded bytes, release/hole ranks, deferred ownership, zero/maximum
  limits, duplicate/unknown releases and live pins are checked.
- The full sanitized heap suite passes 9,216 history steps, 3,072 fragmented
  placements, 9,216 padding cases, 5,940 bounds cases, 288 collection cases,
  13 growth boundaries, 10,000 churn cycles and 80,000 locked statistics reads.
  Ordinary, padded and table-growth measurements retain zero extra blocks/bytes.
  Interior GC reclaims 8,192 blocks / 393,216 host malloc bytes below a pin.
  The added rank grows records from 32 to 40 source bytes; observed Darwin
  malloc blocks grow from 32 to 48 bytes. Native slab rates are unmeasured.
- Ten compiled FIFO negatives and fifteen C mutations reject wrong order,
  ignored limits, duplicate release, raw/stale accounting, missing ranks or
  compaction, incorrect widths and ownership errors. Existing four heap,
  five bounds, four padding, four capacity, six collection, eight reuse and
  eight history negatives pass. Generators target the new traversal and measured
  block size; the original 320,000-byte assertion is retained. Padding/collection
  matrices check live bytes before retained-record access. Historical checkers
  and complete bundles remain unchanged.
- Fresh isolated ARM/x86 builds pass. Native C preserves eight heap bodies,
  release apart from exact scalar bookkeeping, exact coalescing/frontier code,
  ten owning layouts apart from three scalars, nine GPU lifetime bodies and ten
  event methods. No hidden collection allocation is introduced. x86 C matches
  after compiler path-hash normalization. All 63 focused test files, 150 storage
  guards, three checker selftests, pending-storage checks, native ARM error probes
  and existing wait/wire/fence/close/async/cache/VM/TLB/layout/render/packet/wire
  fixtures pass.
- Two hundred production heap/page-table reuse cycles pass ASan/UBSan using the
  kernel's `-gc none -manualfree` settings and fake-stack detection enabled.
  They check old-leaf invalidation, new backing, live pins and actual metadata
  destruction. Privileged operations are replaced; no firmware cache operation runs.

The previous default-Boehm heap/TLB fixture hit a null table entry under ASan's
fake-stack mode. The same binary passed with fake stacks disabled; a traced
variant also passed. This points to GC/fake-stack interoperability, which remains
unqualified. Both outcomes, C, binaries and the trace fixture are retained.
Acceptance retains fake-stack detection and adds poisoned-metadata assertions
under the production memory model.

Allocation reports exactly match the verified predecessor: 379 ARM / 289 x86
sites across 833 / 813 source files. Existing allowance-check failures remain
unchanged; no allowance was edited.

Fresh heads are Omarchy `3b36b9e19ea00a6c21492098308a7f44a8091564` and packages
`6aa71681da0fa53944f230e2d6b807bf852f2b0b`. Package definitions remain unchanged:
Linux `bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

Whole-driver audit: **not_equivalent**. Complete allocator behavior, modern
UAPI/Mesa integration, timestamp publication/units, remaining stage backing/event
destruction, manager/UAT replacement, firmware/cache teardown, reservation fences,
timelines, wire/default coverage, topology and power/reset remain open.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-garbage-fifo-20261117/`.
Baseline is `cb55d47678bfcc2b5f5925240f2c576f799beffe` plus twenty-three retained
source paths, including one native overlay. Independent unchanged runners are
reused after checksums; dependent fixtures and kernels are fresh. The original
inventory checker verifies the prior bundle, current bundle and full archive
restoration. Pinned KVec/drain and DRM MM sources match their Git blobs.
`completion.txt` binds sources/reports to the commit. Generated evidence stays
outside Git.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `84553340ea2cc51aca5032580ca58ba88c0ef2264f0b116e09044cb9595eb6d7` |
| `bundle.tar.gz` | `f7576ee254c601c2e934c8b1f8369f3b24c11d69ae9f89f6af6798fce54fbb68` |
| `bundle/vinix-aarch64` | `b5a6b45357706445211b663c8867eb8f9774b743c779b2feaa7ae6aab0892ba8` |
| `bundle/vinix-x86_64` | `6331f20cfcde21a3b6dd54ce7850120b3d0cfbb3243e48a19a6a4fba93f69c84` |
| `bundle/blob-aarch64.c` | `b40a9d21141e56630939503ccaa3bc388a6a50e84e35b61e50f0cc97caf1365c` |

No GPU workload, firmware interaction, Vinix/QEMU boot, reboot, SSH or deployment occurred.
