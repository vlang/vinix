# Native cachestat

`cachestat` uses a 16-byte input range and returns five 64-bit counters.
Offsets and lengths are in bytes. A nonzero length selects every page
intersecting the range, and a length of zero extends it to the end of the
file. The syscall keeps the selected descriptor alive throughout the query
and leaves its file position intact. [Linux 6.12.51 cachestat](https://github.com/gregkh/linux/blob/v6.12.51/mm/filemap.c#L4447)

A writable description, inode ownership, `CAP_FOWNER` under Vinix's inode
credential rules, or current write permission authorizes the cache query.
Vinix also applies its mandatory inspection policy. Invalid descriptors and
`O_PATH` return `EBADF` before the range copy, bad input pointers return
`EFAULT`, and nonzero flags return `EINVAL` after the access check.

Tmpfs and memfds report resident backing within the file's sampled size.
Mapped shared faults can populate that backing, and untouched sparse slots
stay empty. Procfs, sysfs, devtmpfs, character devices, pipes, and sockets
have empty file-page counts. These supported resources have zero dirty,
writeback, evicted, and recently evicted pages in Vinix's file cache.

## Qualification

The same native probe ELF per architecture passed on Vinix and Linux
6.12.51. It exercises typed syscall arguments, bad pointers and flags,
permission checks, sparse reads and writes, shared faults, shrink,
stream files and 128 multi-batch memfd queries. Both baseline kernels
returned `ENOSYS`.

Production Vinix builds used `6c01b60c6` plus the archived patch. The
`memfdcreate`, `memfdseals`, `sharedmem`, `accessflags`, `readahead`, and
`procself` regressions passed on both architectures. The allocation checker
reported the same existing failures and the same 306 AArch64 and 254 x86-64
allocation sites as the baseline.

| Architecture | Probe ELF | Vinix kernel | Vinix serial log | Linux serial log |
| --- | --- | --- | --- | --- |
| AArch64 | `5b0dc1ca8a618004` | `6e8e11457b9a939a` | `154e8c3b4e222804` | `3b35cc449b976149` |
| x86-64 | `be5302f1ef0e20c6` | `a7e5b40e3da8db61` | `273e3fa6fda7d359` | `be6d3935e299f5aa` |

Hashes are SHA-256 prefixes. The restored and verified archive is
`~/.cache/vinix-r15/cachestat/qualification.tar.zst`, with SHA-256
`2bfda933ec38b3cc6c6fd59faa6bf57650ef15dd0a6cb3929582ab93db91fb2e`.

## Limits

Disk-backed inodes and block devices return `EOPNOTSUPP`. Vinix's block
cache is indexed by device offset. Per-file statistics for disk-backed
inodes need an inode-and-page residency index.

Tmpfs reports its actual resident storage. A small extension can use an
inline buffer, and a regrown file can reuse pages retained after truncation.
Large queries sample the page vector in bounded batches, so writes during
a query can change the residency observed in later batches.
