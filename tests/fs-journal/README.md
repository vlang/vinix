# Journaled filesystem acceptance

Run the unchanged production journal engine on the host:

```sh
V=/path/to/v sh tests/fs-journal/run-host.sh
V=/path/to/v VINIX_HOST_SANITIZE=1 ASAN_OPTIONS=detect_leaks=0 \
  sh tests/fs-journal/run-host.sh
```

The device model records cuts at every store and flush: only the previously
flushed bytes, all completed writes, and half of the current torn write.
Recovery must produce the complete old or complete new transaction. Each
recovery is itself interrupted at every checkpoint and retried. The suite also
checks commit I/O failures and poisoning, dirty read-only mounts, corrupt
payloads, duplicate/out-of-bounds destinations, allocation failure, capacity
failure, abort isolation and balanced engine allocations.

Build qualification kernels in isolated worktrees using the normal kernel
build options plus `VFLAGS='-d journalcut'`. Qualification ioctls obtain the
fixture mode from the kernel command line, arm a serial marker and freeze the
guest at a journal phase, and print singleton allocation call sites on a failed
retention check (`ALLOC_TRACK=1`). Production builds have none of these ioctls.
Run both architectures:

```sh
VINIX_KERNEL_DIR=/path/to/arm/kernel python3 tests/fs-journal/run.py --arch=aarch64
VINIX_AMD64_KERNEL=/path/to/x86/kernel/bin/vinix \
  python3 tests/fs-journal/run.py --arch=amd64
VINIX_KERNEL_DIR=/path/to/arm/kernel \
  python3 tests/fs-journal/run.py --arch=aarch64 --format --cases=full
VINIX_AMD64_KERNEL=/path/to/x86/kernel/bin/vinix \
  python3 tests/fs-journal/run.py --arch=amd64 --format --cases=full
VINIX_AMD64_KERNEL=/path/to/ordinary/kernel/bin/vinix \
  python3 tests/fs-journal/run.py --arch=amd64 --production --cases=full
```

The native runner kills QEMU without shutdown or a final sync, using actual
VirtIO block (ARM) and AHCI (AMD64) devices. Rename replacement is interrupted
after payload flush, commit-marker flush, the first home write, home flush and
marker clearing. A fresh boot verifies the old namespace before commit or the
complete new namespace after commit. The full scenario exercises metadata,
hardlinks, cross-directory rename, directory replacement, rename exchange,
shared mapped durability, private COW isolation, truncate/extend zeroing and
large sparse cleanup. A held zero-link file and a pending linked truncation
are recovered on the next boot. Six hundred sparse allocations 4 MiB apart
force cleanup to cross the 512-page journal capacity with a small physical
volume. Repeated create/map/link/rename/unlink/release cycles measure every
slab class and large-page retention after warming device-cache keys, two
equivalent batches and the observer/reporting code. The AMD64 fixture executes
from disk, so its own lazily faulted executable pages must enter the baseline.
Sampling waits through retirement grace
periods and compares per-class minima across maintenance timer phases, so
short-lived background allocations do not look like persistent retention.

`--cases=full,rename,orphan,truncate,churn` selects scenarios. `--format` uses a
blank sparse 4 GiB disk and exercises the native installer formatter; the
default uses an independently serialized 68 MiB test volume. `--state-dir`
retains images, payload and boot inputs for inspection. e2fsprogs, QEMU, the
usual firmware/boot tools and static musl toolchains are required.

The ordinary production-kernel mode runs the full scenario and restart
verification without qualification ioctls. Architecture builds, the
legacy EXT2 sparse suite and page-cache suite provide separate regressions.

Qualification passed on ARM64 and AMD64: all five rename cuts, repeated boot
recovery, orphan and large linked truncation recovery, blank-disk formatting,
ordinary production-kernel mapped/xattr durability, and inspection with
`e2fsck -fn`. Two measured 200-cycle retention batches keep every slab class
and large allocation count flat on both architectures. Host journal and
sparse suites also pass ASan/UBSan; cache and xattr host suites pass. The ARM
desktop `idle,apps,drag` scenarios pass, and the separate `ops,churn,cache`
workload reports zero retained bytes for all 72 syscall cases and eight
300-run process workloads. New kernel lifetimes were independently reviewed
in generated C for both architectures.

The allocation allow-list checker has 170 existing discrepancies on baseline
`79c2ccac`; an isolated build with this feature reports the identical set,
with zero added allocation categories. The baseline allow-list is unchanged.

VJFS is a private format. Do not mount it with an EXT2 driver or run EXT2 repair
tools on its live image. After native recovery clears the commit marker,
`image.export_clean` makes a separate inspection copy, removes the journal
tail and restores EXT2 signatures in that copy. `e2fsck -fn` then checks every
allocation, inode sector count, directory and link invariant. The fixture
serializer is only for new disposable test volumes, not an in-place migration
tool. See [format guarantees and limits](../../docs/primary-filesystem.md).
