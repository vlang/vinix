# Repeated single-page GPU bindings

Native BIND now implements the SINGLE_PAGE behavior in Omarchy's packaged
[Asahi MMU](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs):
one complete 16 KiB BO page at the requested offset backs every page in the
requested GPU VA range. Previously a range larger than the remaining BO backing
was refused, and no repeated mapping path existed.

`asahi_bind_single_page` uses reference bit 3. Native READ/WRITE flags keep their
existing values; this does not migrate the whole ioctl to the modern ABI.
Read or write permission remains required. BO bounds consume one page, while
global/private VA checks, overlap exclusion, mapping metadata and invalidation
use the full virtual range. The last complete BO page is valid. Ordinary BIND
keeps its contiguous physical mapping and full-size backing requirement.

The new page-table helper holds the existing lock, writes every leaf with the
same physical address, and invalidates the complete range before unlocking.
Allocation failure removes all written leaves before invalidation and before
the caller drops its BO reference. One existing mapping reference pins all
aliases. A failed firmware flush retains that owner until full-range retirement
can complete. No additional mapping owner or temporary heap allocation is
introduced. Intermediate page tables follow the existing cache-until-destroy
lifetime. Independent source and retained native ARM C review approved these
lifetimes with no findings; exact approved hashes are in `independent-review.txt`.

The fake software GPU returns `EOPNOTSUPP` for SINGLE_PAGE before acquiring a BO
reference because its CPU resolver requires contiguous backing. The new guard
is covered by source checks and cross-builds; no fake guest runtime test ran.

Validation passed:

- ASan/UBSan lifecycle fixture: 12,800 new checks across 200 cycles, RO/WO/RW,
  first/last BO pages, 1/2/17-page VA ranges, one mapping owner, busy pins,
  full-range removal, malformed bounds/permissions/VM/private-window requests,
  failed mapping allocation, failed flush and retirement retry. Final close
  returns the live object count to zero.
- Production PTE fixture: 100 cycles of 1/2/3/17 repeated pages across an L3
  boundary, exact permissions and physical addresses, contiguous-map controls,
  all aliases cleared on unmap, partial allocation rollback visible at TLBI,
  alignment/overflow refusal and every table allocation released at destroy.
  Privileged instructions, allocator and locks are host services here.
- Earlier 32,800 BIND-order, 24,200 binding-VM, 9,400 lifecycle, 12,600
  submit-order and 167,395 wait/syncobj cases pass, along with VM geometry,
  async, retirement, priority, private BO/PRIME, wire/node and fence checks.
- Exact prior GpuFile bytes with the new fixture fail the repeated-map dispatch
  assertion. Raw source, precise single-source adapter, executable and failure
  are retained. Initial passing lifecycle/PTE artifacts are also retained;
  final assertions additionally verify full unmap sizes and zeroed alias PTEs.
- 29 V test files, selected primary-reference/source gates, mutation tests and
  the strict native ARM C storage checker for 99 live helpers pass. The latter
  includes the new backing-size and repeated-map helpers; negative selftests pass.
- Isolated ARM and clean x86 kernel builds from
  `a371beb1d674fb78a7000f40187715548cd0f36e` plus five overlays:
  `kernel/drm/ioctl/ioctl.v`, `kernel/gpu/agx/file/file.v`,
  `kernel/gpu/agx/vm/vm.v`, `kernel/gpu/agx/pgtable/pgtable.v` and
  `kernel/gpu/agx/fake/driver.v`. Both ELF/C pairs and all five inputs were
  retained. Selected audited/support sources match the isolated inputs.

The unchanged global allocation allowance audit **still fails** for baseline
and feature. Per-file/kind counts are identical: 383 ARM/289 x86 reported sites,
827/813 sources. No allowance or checker was relaxed. Host ownership/table
measurements and source/C review do not qualify native heap use or multi-CPU
races.

Local Omarchy/package clones were refreshed against remote heads, still
`4bf10ed28342b597009dcf573ffc0d70b94b31e3` and
`d727707b620c4e6c1c8de0f45c4a843475fa020e`. Reference pins remain Linux
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. Selected gates pass; the full
audit remains `not_equivalent` (exit 1).

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-single-page-20261116/`.
Canonical `bundle/` and a complete archive restoration pass the unchanged typed
inventory checker. The full sources/references, kernels/C, executable tests,
negative baseline, raw logs and independent lifetime review are retained.
`completion.txt` binds seventeen source paths and two reports to the feature
commit. Final lifecycle/PTE evidence uses `close-final.log`/`close-test-final`
and `tlb-final.log`/`tlb-test-final`.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `be397e9ca96e8e9045263dc71405fb9bf2d4f10de39233754c18321d4e71ae59` |
| `bundle.tar.gz` | `29a5b142550567f67f32e8ff8d838c66ae179e8d528ff267fb0c5297ba7f53b1` |
| `bundle/vinix-aarch64` | `d70d29543d812742d7b3d16c91d43898351ed519bbd5c4a8a55e4c8d3f9ce5d2` |
| `bundle/vinix-x86_64` | `84ed5a24bc20a787beda8a49d780f2be31563acacd96cf14e0ede0336a50126d` |

This qualifies repeated-page behavior for the native supported binding fields
and page-aligned BOs. Modern bind batching/formats, mapping replacement/splitting,
memory accounting, Mesa integration, cumulative timelines, fence containers,
retained-queue destroy semantics, reclamation and hardware qualification remain
open. No Vinix/QEMU boot, GPU execution, hardware test, reboot, SSH or deployment
occurred. Overall Omarchy equivalence is incomplete.
