# BIND overlap replacement and preparation

Native BIND now replaces idle overlapping mappings, following packaged
[Asahi preparation and GPUVM mapping](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs).
Exact, partial and multi-BO replacement preserves the live pieces outside the
new VA range. Previously every overlap returned EBUSY.

After existing BO/global/VM/private validation and cleanup, BIND counts at most
two survivors and reserves their transient slots plus the new mapping slot.
All BINDs now use fallible metadata reservation with checked geometric growth.
The shared survivor counter keeps UNBIND and replacement consistent.
Overlapping replacement still requires an idle VM; fresh mappings remain
admissible while work is in flight.

`prepare_map_range` then prepares every intermediate UAT table before old
leaves are removed. It requires positive aligned whole pages, checks the end,
holds the page-table lock and changes no leaf or TLBI state. Preparation failure
preserves old mappings; attached empty tables remain rooted until VM teardown.
UAT table/root page allocation now uses the fallible PMM path. Review found
that the previous allocator could panic on exhaustion despite returning an
Option, which would have defeated the new error handling.

Only successful preparation permits old-range retirement. Old invalidation
failure retains removed-fragment owners, returns the new temporary BO reference
and prevents new installation. Successful retirement leaves topology allocated,
so final contiguous/SINGLE_PAGE mapping cannot allocate tables. Mapping insertion
adopts the new reference; failed new invalidation retains it in the existing
retiring record. Independent source/native ARM C lifetime review approved these
paths and geometric growth, with no remaining findings. Exact hashes and review
limits are retained in `independent-review.txt`.

Validation passed:

- 27,000 new ASan/UBSan ioctl checks cover exact/partial/multi-BO replacement,
  holes, old/new contiguous and SINGLE_PAGE modes, RO/WO/RW changes, same-BO
  replacement, foreign VMs, busy refusal, metadata/table OOM before mutation,
  old/new flush failure, retry and failed close. Fresh BIND OOM and in-flight
  admission also pass. Object counts return to zero; ASan proves every tracked
  raw array reservation is freed before its tracking slot is reused or after close.
- 100 new production-PTE cycles run explicitly with `tlb-run --sanitize`.
  Root OOM and initial/later L3 failure preserve old leaves and retain earlier
  empty tables. After preparation, both map paths cover 2,050 pages across L3
  boundaries with all further allocation forced to fail. Every table is freed
  at destruction. Sanitizer linkage receipts are retained for both focused binaries.
- The exact prior ioctl method with current helpers/fixtures fails with EBUSY
  where idle replacement now succeeds. Raw baseline, adapter, executable and
  rejection are retained. Earlier 14,600 range-UNBIND, 16,200 GEM-size, 12,800
  SINGLE_PAGE, 32,800 BIND-order, 24,200 binding-VM, 9,400 identity, 12,600
  submit-order and 167,395 wait/syncobj cases pass, with async/retirement/private
  BO/PRIME/priority, geometry, wire/node, fence and previous PTE regressions.
- 32 V source/contract/allocation-tool test files and primary-source gates pass.
  The strict native ARM C checker covers 105 helpers and its negative selftest
  passes. Native C has four additional explicit pre-adoption BO release sites,
  preserves get_ref count, uses the fallible table allocator and keeps new
  preparation/counting temporaries on the stack.
- Isolated ARM and clean x86 builds use
  `7209777a3f8ab49cc16b66c3bc0d0ec8c768dcae` plus two overlays,
  `kernel/gpu/agx/file/file.v` and `kernel/gpu/agx/pgtable/pgtable.v`.
  Both ELF/C pairs and exact inputs are retained. Selected support sources,
  including `kernel/memory/physical.v`, match isolated inputs. Native AGX is ARM-only.

The unchanged allocation allowance audits **still fail** for baseline and feature
with identical per-file/kind V-reported counts: 383 ARM/289 x86 sites, 827/813
sources. These counts do not measure explicit metadata/table allocations or
native heap rates. No allowance or allocation rule was relaxed. Host services
replace privileged instructions, allocator and locks; source/C ownership review
does not qualify multi-CPU races, firmware execution or native memory use.

Remote Omarchy/package heads remain `4bf10ed28342b597009dcf573ffc0d70b94b31e3`
and `d727707b620c4e6c1c8de0f45c4a843475fa020e`. Pins remain Linux
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. The full audit remains
`not_equivalent` (exit 1), while selected gates pass.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-bind-replace-20261116/`.
Canonical `bundle/` and full archive restoration pass the unchanged complete
typed inventory checker. Initial tests/sources before geometric growth are
retained separately; final lifecycle evidence is `close-final.log` and
`close-test-final`. An initial seal rejected an approval-wording mismatch;
its untouched partial payload and typed receipt remain in `failed-seal-bundle`
and `failed-seal-inventory.json` (SHA-256
`420f6228610027190388d00b085e8609f4d412c1aca43664feafea0cbcb53669`).
The final seal requires the actual approved wording. `completion.txt` binds
sixteen source paths and two reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `f8e8f640a0f42eb042dd935b974bf3918fd0e4716a071e0fac6d1f05c13e74c5` |
| `bundle.tar.gz` | `2133a110499e98c7e306fcfa20490f126c27d912dc1667ebf70ccb09fc92d5b5` |
| `bundle/vinix-aarch64` | `b960cadeb4e249087a883ae34eeb32269c4ad9d8f114a089c28cd33488ee905a` |
| `bundle/vinix-x86_64` | `3d7ba6ce29ff76c99832419791b268212c53ca1f5599fa22e57e7fe2dd1d317d` |

Overall parity remains incomplete: modern ABI/Mesa integration, batched VM_BIND,
reservation fences/deferred in-flight mutation, memory accounting, cumulative
timelines, fence containers, retained-queue destruction, reclamation and hardware
qualification remain open. The fake backend is outside this replacement change.
No GPU execution, native hardware test, Vinix/QEMU boot, reboot, SSH or deployment
occurred.
