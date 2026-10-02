# Memory locking

SC2 replaces the successful no-op handlers with native-page `mlock`,
`munlock`, `mlockall`, `munlockall`, `mlock2(flags=0)` and `MAP_LOCKED` behavior
on aarch64 and x86_64. Supported anonymous and regular-file pages are physically
populated before a lock succeeds. `PROT_NONE` pages may become resident while
remaining inaccessible, including tagged stack guards.

`RLIMIT_MEMLOCK` charges each locked virtual page once and rounds the limit down
to the native page size. `CAP_IPC_LOCK` bypasses it. A zero limit without that
capability returns `EPERM`; an excessive explicit lock returns `ENOMEM`, and
an excessive locked/future mapping returns `EAGAIN`. Unmapped spans and file
pages beyond EOF fail with `ENOMEM` before changing lock flags. Unsupported
device mappings fail with `EOPNOTSUPP`. Unknown flags return `EINVAL`;
`MLOCK_ONFAULT` and valid `MCL_ONFAULT` requests explicitly return `EOPNOTSUPP`.
These constants and permission checks follow the [Linux memory-locking
implementation](https://github.com/torvalds/linux/blob/master/mm/mlock.c).

`MCL_CURRENT` covers user mappings and committed heap pages, excluding the
internal inaccessible heap reservation. `MCL_FUTURE` belongs to the address
space, including threads sharing it, and covers mmap and subsequent heap
growth. Fork clears locks and future mode in the child; exec creates a fresh
address space. Unmap, fixed replacement, heap shrink and remap update accounting
through the surviving ranges. `/proc/<pid>/status` reports `VmLck` in KiB.
Discard advice refuses locked pages. Current mapping ownership keeps resident
frames and mapped file-cache pages referenced; Vinix currently has no swap.

Lock changes preflight all ranges and limits, populate outside the map lock,
then revalidate residency and policy before committing. Failure leaves prior
lock flags and future mode unchanged; successfully faulted pages may remain
resident as ordinary owned pages. Partial lock/unlock boundaries remain owned
until unmap, bounded by mapped native pages; repeated calls reuse them. Remap
accepts compatible restored pieces of the same original mapping without
requiring metadata coalescing. It preserves dirty private-file bytes,
read-only/executable protections and locked accounting, and checks source and
destination identities before copying or removing mappings.
Remap rejects internal heap reservation mappings, including committed pieces,
with `EINVAL` so the process break continues to refer to its original arena.

Build kernels first and point the isolated guest runners at them:

```sh
VINIX_KERNEL_DIR="$PWD/kernel" \
  VINIX_AARCH64_SYSROOT=/path/to/aarch64/sysroot \
  CC=/path/to/clang tests/memlock/run.sh aarch64
VINIX_AMD64_KERNEL="$PWD/build-amd64-kernel/bin/vinix" \
  tests/memlock/run.sh amd64
```

The seven guest groups verify real residency, overlapping and unaligned locks,
finite limits and capabilities, holes/overflow/EOF rollback, stack guard
faults, fork/exec inheritance, private-file and executable remaps, fixed
replacement, heap sealing, invalid/on-fault flags and two-CPU replacement
races. Three hundred success and denial loops compare `/proc/meminfo` slab
usage and print retained allocation sites on an `ALLOC_TRACK=1` kernel.

Run `python3 tests/mapped-writeback/run.py --arch aarch64 --steps=private`
and `--arch amd64 --steps=private` with the same kernel overrides (and
`VINIX_QEMU_RT_NO_BUILD=1` for a prebuilt ARM kernel). That EXT2 guest verifies
dirty locked private remaps leave cached aliases and disk contents unchanged,
unlocks allow discard/reload, and 500 private remap/unlink/close/unmap operations
keep allocations bounded. Its host then checks every byte of the backing file
after a power cut. The shared anonymous remap behavior inherited from the
existing kernel remains a separate compatibility limitation.
