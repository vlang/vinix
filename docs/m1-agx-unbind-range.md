# UNBIND ranges and surviving mappings

Native UNBIND now removes the intersection of its VA range with every mapping
in the selected VM, following packaged
[Asahi range removal and splitting](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs).
It succeeds over already unmapped addresses and holes, can span several BOs,
and preserves live head/tail pieces. Previously it required one exact mapping
match and returned EINVAL for partial, combined or already removed ranges.

The existing validation still requires a positive page-aligned user range,
excludes the private reservation, resolves the file-owned VM and rejects
in-flight work with EBUSY. This qualifies native range-removal behavior;
modern VM_BIND batching and reservation-fence/deferred-in-flight semantics
are outside this change.

Before any new BO reference or PTE mutation, the file lock protects a fallible
reservation for all transient survivor records. Disjoint mappings need at most
two added fragments. The replacement array copies records without changing
their BO owners, publishes its header, then frees old storage once. Slot/byte
bounds and allocator failure return before visible mutation. Existing capacity
needs no allocation.

Each surviving piece acquires one BO reference before the original record is
clipped to the removed intersection and retired. Surviving PTEs remain intact,
including SINGLE_PAGE physical aliases and exact permissions. Failed firmware
invalidation retains the removed fragment's owner. A retry overlapping that
tombstone retries its complete recorded range without splitting or unmapping it
again. Reverse traversal of the original record count permits appends/deletions
and continues independent overlaps after a flush failure. Existing GEM_CLOSE,
UNBIND_ALL and file close release every surviving/retiring owner through the
same invalidation gate.

Independent source and native ARM C lifetime review approved both the array
storage and survivor references, with no findings. Exact reviewed hashes and
scope are retained in `independent-review.txt`. C confirms shallow header moves,
stack fragment values and sufficient reserved capacity before both array pushes.
There is one explicit checked raw allocation site for owned array storage;
there are no new hidden temporary/boxing allocations in these helpers.

Validation passed:

- ASan/UBSan with stack-use-after-return detection: 14,600 new ioctl checks
  across 200 cycles cover head/tail/middle/full cuts, holes, multiple BOs,
  contiguous/SINGLE_PAGE leaves, foreign-VM preservation, busy gates, reservation
  OOM before any refs/PTE changes, failed split invalidation, continued progress
  on other overlaps, complete tombstone retries, rebinding the cleared hole,
  UNBIND_ALL/GEM_CLOSE and failed file close/retry. Every object returns to zero
  live instances. ASan shadow verifies every successful raw array reservation
  is freed after final close, including backing replaced during a later split.
- Production PTE fixture: 100 new cycles cover all four cut shapes, contiguous
  and repeated backing, RO/WO/RW and L3 boundaries. Every surviving leaf keeps
  its exact physical/protection word; the removed hole is zero before TLBI.
  Final teardown releases every host table allocation. Allocator, privileged
  instructions and locks remain injected host services.
- The exact prior ioctl method, substituted into current source/helpers and
  fixtures, fails the new range-removal assertion with EINVAL. Raw baseline,
  precise adapter, executable and rejection are retained.
- Earlier 16,200 GEM-size, 12,800 SINGLE_PAGE, 32,800 BIND-order, 24,200 binding-VM,
  9,400 identity, 12,600 submit-order and 167,395 wait/syncobj cases pass, along
  with async, retirement, priority/private BO/PRIME, geometry, wire/node, fence
  and earlier PTE checks. The old repeated-UNBIND expectation now requires success.
- 31 V source/contract/allocation-tool test files pass. Primary-source gates,
  ownership mutation tests and the strict native ARM C checker for 102 helpers
  pass, including negative selftests for the owned reservation allocation.
- Isolated ARM and clean x86 builds from
  `485c08eb3c065519eeeb9d0cfb52ef1dee0c7b09` plus one overlay,
  `kernel/gpu/agx/file/file.v`. Both ELF/C pairs and exact overlay inputs are
  retained; selected audited/support sources match the isolated inputs. The
  native AGX path is ARM-only; x86 checks the shared kernel build.

The unchanged global allocation allowance audits **still fail** for isolated
baseline and feature with identical per-file/kind counts: 383 ARM/289 x86
V-reported sites, 827/813 sources. These reported sites do not measure the new
explicit raw reservation or native heap use. No allowance or existing allocation
rule was relaxed. Host ownership/ASan evidence and source/C review do not qualify
native heap rates, multi-CPU races or firmware execution.

Local Omarchy/package clones were refreshed against remote heads, still
`4bf10ed28342b597009dcf573ffc0d70b94b31e3` and
`d727707b620c4e6c1c8de0f45c4a843475fa020e`. Reference pins remain Linux
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. Selected gates pass; the full
audit remains `not_equivalent` (exit 1).

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-unbind-range-20261116/`.
Canonical `bundle/` and a complete archive restoration pass the unchanged typed
inventory checker. Sources/references, kernels/C, executables, negative baseline,
raw logs and independent lifetime review are retained. Initial array-header
compile diagnostics and the first passing 14,000-check fixture are preserved;
the authoritative strengthened lifecycle pair is `close-stronger.log` and
`close-test-final`. `completion.txt` binds fifteen source paths and two reports
to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `e6ef428039121e5d89528e4f8e4393cb18f0148f35bd05bc2af4b95344ee99f1` |
| `bundle.tar.gz` | `b4287b677ea89060a20deec7145f2ce3a7583a0fc774922626afba41a99bd391` |
| `bundle/vinix-aarch64` | `5542411d8ce18c2572fc4a99edd543e34313950a7c9ba2bf152de9acbc74d8fe` |
| `bundle/vinix-x86_64` | `9cafc23037a5c73e09383db1299459fbeeaab6bc5769038d030164f6f5a349e8` |

Overall Omarchy equivalence remains incomplete. Modern ABI/Mesa integration,
BIND overlap replacement, accounting/reservation fences, cumulative timelines,
fence containers, retained-queue destruction, reclamation and hardware
qualification remain open. No GPU execution, native hardware test, Vinix/QEMU
boot, reboot, SSH or deployment occurred.
