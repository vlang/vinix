# Procfs and directory scratch allocations

Build an isolated kernel with `ALLOC_TRACK=1`, then run:

```sh
VINIX_KERNEL_DIR=/path/to/worktree/kernel VINIX_QEMU_RT_NO_BUILD=1 \
  VINIX_AARCH64_SYSROOT=/path/to/aarch64/sysroot \
  python3 tests/procfs-allocs/run.py
VINIX_AMD64_KERNEL=/path/to/worktree/kernel/bin/vinix \
  python3 tests/procfs-allocs/run.py --arch amd64
python3 tests/procfs-allocs/check-generated.py kernel/obj/blob.c
```

`VINIX_VM_RUNNER_ROOT` can point at a checkout with the prepared boot inputs.
`--baseline` reports retained allocations without enforcing flatness and skips
the unsafe-name regression against kernels lacking the bounds check.

The guest checks proc text, both directory record ABIs on amd64, 8-byte record
alignment and zero padding, 255-byte names, pagination through 1,403 entries,
checked bad-buffer errors, and an insufficient first-record buffer. A tmpfs
1,024-byte name must fail enumeration with `ENAMETOOLONG`; removal must allow
the same descriptor to rebuild its snapshot. A 1,023-byte name must fit the
last supported record with its terminator intact.

After warm-up it measures every heap size class and large pages for 200 cycles
of six proc files, 200 proc listings, and 40 listings of the large directory.
Live allocation sites are printed as `PERF-SITE` for `kernel-allocs/sites.py`.
The generated-C check detects heap promotion of the measured Text, Dirent and
record scratch, including allocation accidentally moved inside an entry loop.

## Measurement and ownership

An earlier measured desktop kernel retained 529 bytes per six-file proc cycle
and 32,257 bytes per proc listing. Named sites showed 48-byte Text descriptors
and 1,536-byte objects in `getdents64`. The exact measured ELF disassembly
confirmed a `malloc(1048)` for its Dirent every iteration. A newer compilation
of the same source kept that Dirent on the stack: escape analysis depends on
the whole call graph, so source-level locals alone are insufficient evidence.

The isolated 36fd5d8d baseline retained 1,336,544 bytes over 200 proc cycles:
2,202 extra 48-byte descriptors and 2,403 extra 512-byte read scratch buffers.
The latter has a separate synchronous-I/O stack fix included in the test base.
Caller stack Text descriptors keep the existing byte-buffer ownership:
`Text.str()` returns an independent owned string and frees its builder buffer.
Each getdents call reserves one Dirent and one bounded record before its loop;
the VFS snapshot reserves one Dirent before its loop and append copies it into
the handle-owned array. No stack pointer survives those synchronous calls.
No deferred VFS name or node lifetime is shortened.

Both final architecture guests passed the oversized-name boundary and retry
tests. The focused ARM guest retained 96 bytes per measurement, from two fixed
slab-snapshot descriptors; amd64 retained 96–592 bytes of fixed overhead, with
no proportional growth in the 48-, 512- or 1,536-byte classes. The full ARM
desktop run reported 0 bytes per operation for proc reads, proc listings and `/usr/bin` listings; its complete
ops, churn, cache, idle, apps and drag plan passed. Unrelated pipe, ppoll, stat,
namespace and socket sites and process churn remained measurable and were
reported separately. This change does not claim the entire kernel heap is flat.

The compiler allocation report has stale repository-wide allowances. The
unchanged test base emitted 439 unique sites versus 430 after the measured
Text fixes, with only the nine removed proc descriptor promotions differing.
Both runs fail the same allowance groups; this work does not add exemptions.
Both architecture builds and production generated-C checks are required.

Existing shared-directory position synchronization, rollback of a directory
position after failed user copying, global 255-byte namespace admission, and
other proc formatting paths are outside this focused change.
