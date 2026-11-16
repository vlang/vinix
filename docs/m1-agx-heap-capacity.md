# GPU heap pointer-buffer reclamation

Each GPU heap now exclusively owns its allocation pointer buffer before the
first append. V's `.noslices` flag lets capacity growth free the previous buffer
after copying its pointers. The allocation records themselves remain separately
owned and valid. Heap construction returns a stack value without cloning; no
record layout, bounds, GC frontier or new allocation site changes.

The old constructor left this flag unset. Production allocator code compiled
with `-gc none -manualfree` retained 12 discarded pointer buffers / 90,160 host
malloc bytes when growing from a warmed two-entry table to 8,192 simultaneous
records. The fixture releases every record and restores the warmed table
capacity, excluding the final legitimately owned buffer from the comparison.
The fixed source retains zero additional blocks and bytes in the same sample.
This is a host measurement; native kernel slab rates remain unmeasured.

Packaged Asahi's
[`HeapAllocator`](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/alloc.rs)
uses owned range nodes and `KVec` storage. This change removes a Vinix/V storage
lifetime gap. It does not provide Asahi's best-fit interior-hole reuse, backing
object policy or complete allocator behavior.

Offline validation passed:

- ASan/UBSan exercises 13 growth boundaries up to 8,192 records. All 12 replaced
  buffers are poisoned after retirement; the initially empty table has no
  buffer to retire. Record pointees and VA addresses remain stable, with two
  concurrent statistics readers making 80,000 locked reads. Existing 9,216
  padding cases, 5,940 bounds cases, suffix ownership, automatic GC and ordinary
  churn tests pass. Padded churn and three ordinary 10,000-cycle samples retain
  zero additional blocks and bytes.
- Four compiled capacity negatives catch the original constructor, missing
  ownership, ownership enabled only during release, and ownership lost before
  append. Eight generated-C mutations reject constructor, hidden-allocation,
  missing/early free, no-op disposal and lost flag-transfer errors. Four padding,
  five bounds and four heap ownership compiled negatives pass. The unchanged
  eight-case padding and five-case bounds C selftests pass.
- Fresh isolated ARM/x86 kernels build. Native C reduces exactly to the baseline
  constructor after removing only the local-return transformation and ownership
  flag. Six other heap bodies, ten owning declarations, nine GPU lifetime bodies
  and ten event methods match baseline. Runtime C copies before freeing, handles
  managed and raw buffers, preserves flags through growth and reaches the actual
  allocator free. The builtin array source and complete generated C are retained.
  Both native snapshots match the single allocator overlay; x86 C matches after
  normalizing compiler path hashes. Independent lifetime review found no aliasing
  or lifetime blockers: production table access stays in locked allocator methods,
  construction copies only empty heaps and temporary element pointers cannot
  survive growth.
- All 59 focused V test files, 150 native storage guards, three storage checker
  selftests, pending-storage checks and native ARM errno probes pass. Existing
  wait, wire, fence, close, async, CPU-cache, VM, sanitized TLB, event, layout,
  render, packet and source-derived wire fixtures pass. Nine completion, eleven
  render, five compute-credit, seven event-credit and four native error compiled
  negatives pass with fresh dependent fixtures.

Allocation-site counts remain 379 ARM / 289 x86 across 833 / 813 source files.
The fresh report exactly matches the verified baseline report. Existing
allowance-check failures remain; no allowance or historical checker changed.

Fresh heads are Omarchy `3b36b9e19ea00a6c21492098308a7f44a8091564` and packages
`fab37d198dc6b22daf5f17da2f4d10de8346067b`. All three selected package
definitions remain unchanged: Linux `bed544bdf93a496ebf70ba180923bab12b6e01cf`,
Mesa `b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

The whole-driver audit remains **not_equivalent**. Modern UAPI/Mesa integration,
timestamp publication/units, remaining stage backing/event destruction, complete
allocator behavior, manager/UAT replacement, safe firmware teardown, reservation
fences, timelines, remaining wire/default coverage, topology and power/reset
behavior remain open. Native GPU behavior remains unqualified.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-heap-capacity-20261117/`.
Baseline is `c812fb89819704040fd99f0568e7e3899e28e6c1` plus nine retained source
paths, including one native overlay. Independent unchanged runners are reused
after source/binary checksum checks; dependent fixtures and kernels are fresh.
The unchanged historical inventory checker verifies the preceding complete
bundle, this complete bundle and a full archive restoration. Original allocator
source matches the baseline commit. Historical proof modes and their complete
original bundles remain unchanged. `completion.txt` binds sources and reports
to the commit. Generated evidence stays outside Git.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `17c3e16cef82dbcd8cf8d08e9c6d156c98fab4f3c724f674411d0f8d890e7362` |
| `bundle.tar.gz` | `b7a2c25c23635af0c81e594740501b60d2e810010abea914ba78e75f194bf49d` |
| `bundle/vinix-aarch64` | `6ea958e074a3d4630372f2912d67898d4d22060003171303adbd73e14f886d48` |
| `bundle/vinix-x86_64` | `19f7b701df3dfab57d9e73e724d7e7bb062a0bce89f02763f23a9d79e183909d` |
| `bundle/blob-aarch64.c` | `69390fcfab976171ad6b887ff9cbd712bf1af075bf7d263feb6817143a3a63f9` |

No GPU workload, firmware interaction, Vinix/QEMU boot, reboot, SSH or deployment occurred.
