# GEM backing access

Omarchy's pinned Asahi driver backs GEM objects with shmem pages, which need
not be physically contiguous. Vinix allocates every GEM object as one
physical run with `pmm_alloc_aligned_fallible`. The physical allocator is a
first-fit bitmap without compaction, so after long uptime a large allocation
can fail while plenty of memory is free. Kernel `malloc` already falls back to
mapping single pages for that reason; GEM has no fallback yet.

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

Today every object is still one run, so each accessor returns what the old
arithmetic did. Host-visible virtio apertures (`external`) keep their own
mapping. Phase 2 will let AGX user objects fall back to scattered pages when
no contiguous run is available, and teach the accessors and object teardown
to walk them. Display and virtio objects will stay contiguous.

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
