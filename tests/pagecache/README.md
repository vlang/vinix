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

Dirty pages are written on eviction, explicit synchronization, and final resource
close. Failed or short writeback leaves the page dirty, resident and retryable.
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
Dirty or partly covered pages remain resident. Advice walks are limited to one
cache-capacity window; other advice values remain accepted hints without a policy
change. Devices, pipes and in-memory files do not acquire meaningless caches.

## Deliberate limits and merge gates

There is no periodic flusher, inode page mapping, shared writable mmap,
dirty-PTE tracking, or msync in this first implementation. Physical allocation
failure does reclaim clean LRU cache pages before retrying; dirty pages are never
discarded by that path.
Do not enable EXT2 mmap merely because this cache exists: these are physical
backing pages and can contain bytes from different inodes and metadata.

The cache uses the existing kernel lock across backing I/O. Its current ATA
consumer polls completion. Cache misses and writeback retain the old EXT2
adapter's physically contiguous, page-aligned PMM bounce buffers, releasing them
on both success and failure. Before using interrupt-dependent backends, verify
that completion does not require interrupts disabled by that lock; an interrupt-dependent backend needs a
sleepable lock/explicit in-flight page state. Direct raw-device access outside
EXT2 is not coherent with this cache, and must not modify a mounted filesystem.
The existing EXT2 allocator, resize/truncate and concurrent metadata-update
limitations are not repaired by caching. Crash consistency and on-disk ordering
are not journaled. Validate on a disposable image before using real data.

## Tests

Run the production cache module on a host with V installed:

```sh
V=/path/to/v sh tests/pagecache/run.sh
```

The harness substitutes only the kernel lock and errno modules. The actual cache
source is copied unchanged and exercised with an instrumented byte-array backing
store. Tests cover hits, partial/cross-page writes, tail pages, LRU and bounded
prefetch, clean-only discard, invalid/overflowing ranges, backing identity,
failed/short fills, failed/short writeback, dirty eviction, teardown retry, and
400 deterministic randomized operations under a three-page capacity limit.
The host tests do not validate kernel locks, syscalls, DMA, or EXT2 disk images.
The pagecache workflow runs these tests; the existing kernel workflow provides
separate build coverage. Kernel boot, remount persistence, allocation/truncation,
concurrent descriptor access and power-loss behavior still need integration tests.
