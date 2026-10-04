# EXT2 backing-store page cache

This change adds an initial page-sized **backing-store cache**, not a unified
inode page cache or a file-backed mmap implementation. EXT2 data, inode tables,
indirect blocks and bitmaps all use the same cache. Its identity is the backing
Resource plus a 4 KiB physical offset; instantiated filesystems share the cache
created during detection. This avoids separate stale copies for file aliases or
for data accessed through internal EXT2 helpers.

## Writeback and lifetime

The default limit is 128 pages (512 KiB of data per detected filesystem), with
LRU replacement. Pages are allocated on demand. Full-page overwrites skip reads;
partial writes preserve the rest of the page. Bounds are checked by subtraction,
and a sector-aligned device tail may be shorter than a page.

Dirty pages are written on eviction, explicit synchronization and final
resource close. Once more than `dirty_limit` (1024) are waiting,
`over_dirty_limit` says so, and EXT2 has the writing thread flush on its way
back to userspace, holding no lock. Past `dirty_ceiling` (4096), which only a
single enormous write or a kernel thread reaches, a write writes the oldest back
itself before it returns. Consecutive dirty pages go out together, up to
`max_run_pages` (32) to a request, so store callbacks must accept up to
128 KiB. Failed or short writeback leaves the page dirty, resident and
retryable.

EXT2 changes to the namespace -- create, link, unlink, rename, chmod, freeing an
inode, msync -- are on the device before the call returns, but are not flushed
where they are made: EXT2's lock, and often the VFS's, are held there, and every
other access to the filesystem waits for them with interrupts off. The thread is
marked as owing a flush (`Thread.owes_sync`), and the syscall's way back to
userspace runs `pagecache.sync_all()`, as does an exiting process once its
descriptors are closed, before its parent can wait for it. A failure there is
not reported to that call; the pages stay dirty for the next fsync or sync to
report, as on Linux. A kernel thread's change goes out with the next writeback
pass.
Failed/short fills are not published. Teardown does not free dirty pages if
writeback fails. Callers must keep the backing resource alive until teardown
succeeds. Cache callbacks must bypass the cache and must not re-enter it.

`fsync`/`fdatasync`, `O_SYNC`/`O_DSYNC` writes and nonzero `sync_file_range` requests
call an optional Resource synchronization capability. EXT2 conservatively flushes
the entire shared cache, including metadata and unrelated files, rather than
claiming precise per-file or asynchronous range writeback. An optional underlying
driver synchronization hook is then called. Physical persistence still depends
on the backing driver/controller contract. Last-close errors cannot currently be
reported through Handle destruction; applications must use explicit fsync to
observe writeback errors.

`POSIX_FADV_WILLNEED` performs bounded best-effort prefetch. `DONTNEED` drops only
clean, fully covered backing pages, including coalesced adjacent 1 KiB blocks.
Dirty or partly covered pages remain resident. Advice walks are bounded to 128
backing pages per invocation. Devices, pipes and in-memory files do not acquire
meaningless caches.

## Sequential read-ahead

Two consecutive successful regular-file reads activate a bounded 128 KiB
read-ahead window. `pread` contributes its explicit offsets without moving the
file position. The open-file description owns this state, so `dup` and `fork`
share both the position and advice policy. A discontinuous offset resets the
sequence. `POSIX_FADV_RANDOM` suppresses automatic prefetch;
`POSIX_FADV_SEQUENTIAL` doubles the window to 256 KiB, and `NORMAL` restores
128 KiB. Explicit `WILLNEED` remains available with random advice. Hint failures
preserve the successful read's result and errno.

Prefetch fills consecutive missing backing pages with one device read, up to
32 pages (128 KiB) per transfer. Existing resident pages divide runs and retain
their contents, including dirty pages. A failed or short transfer publishes
none of its private pages. Allocation failure can fill an already allocated
prefix; all unused temporary storage is freed. Speculation replaces only clean
pages and stops at the capacity bound when no eligible victim remains. The
EXT2 inode walk uses the same resource, filesystem and cache lock order as a
normal read.

This is synchronous best-effort prefetch using existing polling block drivers.
It reduces device request counts; it does not add asynchronous block queues or
multiple requests in flight.

## Deliberate limits and merge gates

There is no periodic flusher, inode page mapping, shared writable mmap,
dirty-PTE tracking, or msync in this first implementation. Physical allocation
failure does reclaim clean LRU cache pages before retrying; dirty pages are never
discarded by that path.
Do not enable EXT2 mmap merely because this cache exists: these are physical
backing pages and can contain bytes from different inodes and metadata.

Fills, eviction and write-behind past the ceiling hold the cache lock across
backing I/O; sync does not. It copies each run with the lock held, marks its
pages in flight, and writes the copy under a second lock that only serializes
writeback. The cache lock is the one every EXT2 read and write waits for with
interrupts off, and holding it across a system disk's whole cache stopped the
machine for minutes.
Pages in flight are never evicted, discarded, reclaimed or written by anyone
else, and a sync that finds one waits for it to land before returning. The
second lock still turns interrupts off, so a writer cannot be preempted with a
page in flight while the CPUs that could resume it spin on EXT2's lock. Current
backends poll completion. Cache misses and writeback retain the old EXT2
adapter's physically contiguous, page-aligned PMM bounce buffers, releasing them
on both success and failure. An interrupt-dependent backend still needs a
sleepable lock. Direct raw-device access outside
EXT2 is not coherent with this cache, and must not modify a mounted filesystem.
The existing EXT2 allocator, resize/truncate and concurrent metadata-update
limitations are not repaired by caching. Crash consistency and on-disk ordering
are not journaled. Validate on a disposable image before using real data.

## Tests

Run the production cache module on a host with V installed:

```sh
V=/path/to/v sh tests/pagecache/run.sh
```

The harness substitutes the kernel lock, errno, and physical-storage allocator modules. The actual cache
source is copied unchanged and exercised with an instrumented byte-array backing
store. Tests cover hits, partial/cross-page writes, tail pages, LRU and bounded
prefetch, clean-only discard, invalid/overflowing ranges, backing identity,
failed/short fills, failed/short writeback, dirty eviction, teardown retry,
writeback with the lock free and a write landing mid-flight, pages in flight
staying resident, a second sync waiting for the first, the dirty limit asking
for a flush, write-behind past the ceiling, and 400 deterministic randomized
operations under a three-page capacity limit. Clustered fill tests fetch 68
pages (including a 137-byte tail) in three device reads, preserve a dirty page
inside a hint, reject failed/short loads, and inject temporary-buffer, page
header and physical-page allocation failures with exact reference recovery.
The host tests do not validate kernel locks, syscalls, DMA, or EXT2 disk images.
The pagecache workflow runs these tests; the existing kernel workflow provides
separate build coverage. Kernel boot, remount persistence, allocation/truncation,
concurrent descriptor access and power-loss behavior still need integration tests.

`tests/pagecache/run-guest.py --arch=aarch64` (or `amd64`) boots a disposable
physical EXT2 root using the existing isolated VM drivers. Set
`VINIX_VM_RUNNER_ROOT` to the checkout with the boot dependencies,
`VINIX_KERNEL_DIR` to the ARM kernel directory, and `VINIX_AMD64_KERNEL` to
the x86 kernel binary. `VINIX_QEMU_RT_NO_BUILD=1` uses the already built ARM
kernel. The payload verifies random suppression, 128/256 KiB automatic windows,
explicit hints, shared descriptions, offset reset, positional-read offsets and
byte-exact EOF tails, then repeats 400 cold fetch/discard cycles. After stopping
the guest, the harness runs `e2fsck -f -n` on the real disk image.

Both tracked architecture builds and guests pass: the first 1 KiB read caches
4 KiB; the second caches 0/128/256 KiB with RANDOM/NORMAL/SEQUENTIAL. The
measured slab remains 1,408 KiB on ARM and 1,084 KiB on x86 across both churn
rounds. Both generated-C outputs pass `check-generated.py`, which rejects
hidden interface copies and repeated stack-slot allocation in the fill loop.
These measurements establish the read-ahead paths; unrelated kernel allocation
sites remain subject to the repository's existing allocation audit.

The complete ARM desktop `ops,churn,cache,idle,apps,drag` sweep finishes with
all 43 measurements and no kernel panic. Idle/apps/drag CPU totals are
0.27%/0.77%/4.55%; the 32 MiB cache scenario remains bounded at 16 MiB cached.
The broad sweep still reports retained pipe/directory and process-churn
allocations outside read-ahead. The allowance audit still fails on existing
unallowed sites (its x86 scan reports sites but exits nonzero); no allowances
were changed. The actual production builds and four-function generated-C
checks pass on both architectures.
