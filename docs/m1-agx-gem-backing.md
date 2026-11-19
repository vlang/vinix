# GEM backing access

Omarchy's pinned Asahi driver backs GEM objects with shmem pages, which need
not be physically contiguous. Vinix allocates every GEM object as one
physical run with `pmm_alloc_aligned_fallible`. The physical allocator is a
first-fit bitmap without compaction, so after long uptime a large allocation
can fail while plenty of memory is free. The panicking kernel `malloc` falls
back to mapping single pages for that reason; GEM had no fallback.

## Phase 1: one way to reach backing

Code that used a GEM object's backing added an offset to `phys_addr` or
`virt_addr` itself. It now goes through accessors in
`kernel/drm/gem/backing.v`:

- `page_phys(offset)`: the physical address of one byte, used by the DRM and
  GEM `mmap` page lookups and by SINGLE_PAGE binds.
- `contiguous_run(offset, length)`: the physically contiguous run starting at
  an offset. AGX `BIND` maps the requested range run by run through
  `map_object_runs`; if a later run fails, the runs already mapped are
  unmapped, so the bind is still all or nothing. A G13 timestamp range must
  be a single run.
- `contiguous_phys()`: the base of an object that is one run. Display scanout
  and its DART identity map and swap descriptor, and virtio-gpu backing,
  use it and fail cleanly for anything else.
- `write_bytes(offset, data, length)`: the legacy G13 result writes. They copy
  through the object's kernel mapping as before, or through the direct map
  run by run for an object without one.

At this phase every object was still one run, so each accessor returned what
the old arithmetic did. Host-visible virtio apertures (`external`) keep their
own mapping.

## Validation

`tests/gem-private` checks the accessors directly under ASan/UBSan: page
lookup, bounded and empty runs, the single-run base, writes through the
mapping and through the direct map, and out-of-range refusals. The AGX
file-close, async, CPU-cache, native-error, job-dependency and G13 failure
suites, `drm-wire` and `drm-syncobj-wait` compile the production code with
the accessors and pass. Four runners and two GEM fixtures now include
`backing.v`. Three G13 contracts follow the new bind lines, and a new one
requires run-wise mapping to unmap on failure; its test rejects a version
without the rollback. All 79 contract test files and 122 pinned reference
checks pass.

AArch64 (`LIMINE_MP=1`) and x86_64 `PROD` kernels build, and the allocation
scan matches the previous 427 findings with one line shift. The AArch64
kernel boots in QEMU, registers `/dev/dri/card0` and passes the
mount-lifecycle `descflags` case. Virtio-gpu resource creation and buffer
mapping were not exercised by that boot. No M1 hardware test or reboot
occurred.

Evidence is under
`/Users/alex/.local/state/vinix/omarchy-m1-gem-backing-api-20261119/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `1ae58c0d980d12051789817524960ddff8ce77f56e28e6a48e74441db65b42d0` |
| `bundle.tar.gz` inventory | `2df7437322b26df03c49e70e00b7693905308b4dde1550fa6319ca9d1993fb22` |

## Phase 2: scattered AGX objects

AGX `GEM_CREATE` objects of more than one page now fall back to single pages
when the PMM has no contiguous run long enough. Only `create_aligned_with_cache`
(the AGX constructor) allows it, and only when the requested alignment equals
the page size, which is the case on AArch64, where AGX runs. Display, virtio
and ordinary objects stay contiguous. A contiguous run is still tried first.

A scattered object has `phys_addr == 0`, `virt_addr == 0` and a list of page
addresses. Each page gets the object's direct-map cache policy as it is
allocated and the cacheable one back before it returns to the PMM. A partial
allocation releases the pages it took. The accessors walk the list and merge
adjacent pages into runs. `contiguous_phys` refuses scattered objects outright,
so scanout and virtio backing fail cleanly. A scattered object cannot reach
them today: PRIME import is limited to the same device. A G13 timestamp range
must still be one run; one that crosses a gap is refused with `ENOMEM`, as the
object creation was before. Asahi maps timestamp buffers from a scatter list.

Object metadata and backing are now allocated before `gem_objects_lock` is
taken, for contiguous objects too. That lock masks interrupts, and page
allocation can reclaim. The lock now covers only the handle choice, the mmap
offset and publication. Backing that cannot be published is released after
the lock is dropped.

The page list itself comes from `malloc_packed_fallible`, which needs one
contiguous run of about 8 bytes per page: 528 KiB for a 1 GiB object.

## Phase 2 validation

`tests/gem-private` checks scattered objects under ASan/UBSan: the single-page
fallback, merged and split runs, a write across a gap, per-page cache policy
set and restored, release after a partial allocation, no fallback for ordinary
or over-aligned objects, and contiguous objects still preferred. The AGX
file-close fixture binds a three-run object, maps SINGLE_PAGE from the list,
unmaps the first run when the second fails, and checks timestamp ranges within
and across runs. The CPU-cache contracts now require the per-page policy order,
the scattered teardown and the release of unpublished backing; their tests
reject each removed step.

An independent lifetime review found no use-after-free, double free or leak.
It raised the timestamp limit, the interrupt-masked allocation and the strict
`contiguous_phys`; all three are addressed above. The fake G17 driver still
reads `virt_addr` directly, but it only creates contiguous objects.

The AGX file-close, async and CPU-cache suites, `gem-private`, `drm-wire`
and `drm-syncobj-wait` pass, as do 79 G13 contract test files and 122
pinned reference checks. Both `PROD` kernels build, the allocation scan is
unchanged, and the AArch64 kernel boots in QEMU and passes the
mount-lifecycle `descflags` case. No M1 hardware test or reboot occurred.

Evidence is under
`/Users/alex/.local/state/vinix/omarchy-m1-gem-scatter-20261119/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `99b63252a13c0b03d276338e7daeeec8fde6d3857ee387da4f9fee53dc17ea49` |
| `bundle.tar.gz` inventory | `4d0dfc396e7fad1ccd0d5566352944eb074b899a3e81bb9623aae31d42c45a78` |
