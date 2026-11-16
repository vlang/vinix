# Deadline hints for current sync-file leaves

Vinix now accepts `SYNC_IOC_SET_DEADLINE` on sync-file descriptors, using
Linux's exact 16-byte write-only request. Bad input copies return `EFAULT`
before reserved-field validation; any nonzero 64-bit padding returns `EINVAL`.
All deadline bit patterns are accepted otherwise. No user bytes are written.

This matches the externally observable behavior of current callback-free
leaves in Omarchy's packaged Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`:

- The [sync-file ioctl](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/dma-buf/sync_file.c)
  copies the request, validates padding and passes the hint to the fence.
- The [generic helper](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/dma-buf/dma-fence.c)
  calls a deadline callback only when one exists and the fence is pending.
  Private stub operations have no deadline callback.
- Asahi's underlying `JobFence` uses the
  [Rust fence vtable](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/rust/kernel/dma_fence.rs),
  whose `set_deadline` is `None`.

Vinix's current direct leaves likewise have no deadline callback. Accepting
the hint changes no completion status/timestamp, poll readiness, event
generation or scheduling and allocates nothing. Linux's
[scheduler finished wrapper](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/scheduler/sched_fence.c)
retains the earliest hint and forwards it to a parent. That wrapper metadata
and forwarding remain open; this change does not implement GPU boosting or
complete deadline scheduling.

Validation passed:

- 27,200 new ASan/UBSan cases with stack-use-after-return detection: generic,
  queue and stub leaves; pending/error/success states; integer boundaries;
  repeated hints; reserved bits; all short-header lengths; null/overflow/faulting
  pointers; unknown encodings; high command bits; opaque descriptor rejection;
  allocation failure; unchanged metadata/readiness; namespace removal;
  duplication and final close during descriptor lookup.
- All 87,282 prior synchronization cases, 4,096 borrowed event nodes,
  4,103 geometry probes and 200 capture primitive cycles. The unchanged DRM
  source from `0235f798b566c00f3ec06f019da05eec4192646f` passes those cases,
  then rejects the first valid deadline request with `ENOTTY` (25).
- Async, wire/node and fence sanitizer regressions, 22 V test files,
  selected source/reference gates, strict allocation checks for 82 live ARM C
  helpers and negative checker selftests.
- Isolated ARM and clean x86 builds from that pre-feature revision plus three
  retained overlays: DRM dispatch, ioctl definitions and the new deadline
  helper. Both ELF/C pairs were retained before architecture switch; x86
  excludes AGX. Selected native inputs and reviewed support match the private
  build. The new helper's native C uses one stack request and one full copy-in,
  with no allocation/free/output or fence/scheduler call. There is no new
  owned/borrowed lifetime or reclamation path.

The unchanged global allocation allowance audit **still fails** for baseline
and feature: identical per-file/per-kind counts, 383 ARM/289 x86 sites. One new
source gives 826/812 sources versus 825/811. No auditor or allowance changed.
Native heap/slab use, leaks and concurrent syscalls were not measured.

Fresh Omarchy `4bf10ed28342b597009dcf573ffc0d70b94b31e3` and packages
`4d076593b26175ccb483f8e86255d8185c342e28` match checked remote heads. Linux,
Mesa `b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc` pins are unchanged. The audit now
requires clean `rust/kernel/dma_fence.rs` and scheduler `sched_fence.c` and
retains their exact bytes. Selected gates pass; the full verdict remains
`not_equivalent` (exit 1).

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-sync-file-deadline-20261116/`.
The canonical `bundle/` retains sources/references, kernels/C, test binaries,
logs and the unchanged complete typed inventory checker. Canonical and fully
restored archive inventories pass. `completion.txt` binds eleven source paths
and two reports to the feature commit. A preflight rejected its own missing
output before bundle creation; that rejection and corrected retry are retained.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `895d0d33bebff78711767704ad545b940d7f06d3abe51f425b51635150f569a5` |
| `bundle.tar.gz` | `4c13f627f4426ed767084f0cee1e8ba0bd2ebd00a925ecfc4787927d3e98a5a8` |
| `bundle/vinix-aarch64` | `d4c6474fa13d96e30df551a92388d4db85640bc5e30a3b3f17e651a060459b5d` |
| `bundle/vinix-x86_64` | `ea066804c2b012bfad1c2f068c5bac8c1ea730a15e4c1f116b5d06b45bf59386` |

Merge, fence containers, scheduler deadline metadata/forwarding, descriptor
reservation/error precedence, modern ABI/Mesa integration, timeline chains,
callback waits, indexing/locking performance, reclamation and hardware behavior
remain open. No Vinix boot, GPU/firmware execution, hardware test, reboot, SSH
or deployment occurred.
