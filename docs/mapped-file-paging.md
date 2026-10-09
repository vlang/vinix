# Mapped-file paging

EXT2 file pages now participate in user-memory reclaim on x86_64 (4 KiB pages)
and AArch64 (16 KiB pages). The sleepable pressure worker and foreground allocation
recovery reclaim cold file pages before compressing or swapping anonymous pages.
`MADV_PAGEOUT` uses the same file pager. Ordinary PMM callbacks never perform
file I/O or acquire blocking VM locks.

Shared file PTEs initially deny writes. A permitted write fault records software
dirty evidence before granting write access. x86 accessed/dirty bits and ARM
access flags supply reference state; ARM access-flag faults restore access without
changing write permission. Checked kernel usercopy also records reads and writes.
Before collecting dirty state, writeback revokes writes on every resident alias
and completes TLB invalidation. Writes after collection fault and become eligible
for the next sync. mprotect and repeated page installation preserve dirty evidence.
Unchanged mapped pages require no inode/data writeback.

The VM registers tracked file globals in an intrusive list. The file cache can
identify every alias by retained resource identity, file offset and physical
frame. Reverse lock acquisition tries all address-space and shadow locks before
changing any descriptor. Busy locks, inconsistent identities or more than 64
participating globals/address spaces leave the page untouched and retry later.
An untouched lazy global with no shadow root is skipped. The final local removes
its global from the registry before destroying its shadow tables or resource pin.

A first reclaim pass ages referenced pages. Cold pages lose every matching local
PTE and global shadow entry before the cache releases its physical owner. A
locked or immutable alias pins the underlying file frame. Background scans rotate
through batches of at most 16 resources and 256 pages per resource. Foreground
recovery covers a complete cache cycle, yields between 256-page batches and
reloads inode state after reacquiring vnode/filesystem locks. Explicit pageout
locates the requested file page independently of the background cursor.

Shared globals own counted cache references; private clean globals own PMM
references. Acquired pages awaiting installation keep their independent owners.
Private COW frames have different physical identities and never write back to
the file. They use the existing compression/encrypted-swap pager instead. Full
native-page `MADV_DONTNEED` forgets a private backing and reloads file contents.
Refaulting a clean file page reacquires the cache page through the retained source,
preserving coherence with descriptor I/O and surviving unlink or descriptor close.

Unmap harvests dirty evidence before removing its PTE. Failed or short inode
writeback keeps the dirty cache frame and registry's inode pin, even when all
aliases were revoked. Refault sees those retained bytes; later writeback retries.
Truncation/regrowth keeps the existing cached-tail zeroing and bounds writes by
current inode size. Successful inode writeback transfers responsibility to the
block cache, whose failed device writes remain dirty for retry. Sync barriers and
storage error reporting retain their existing contracts.

This implements paging for the disk-backed EXT2 cache. tmpfs, device apertures,
translated partial-page discard policy, filesystem crash recovery and retry of
failed final inode deallocation retain their existing behavior. It does not
provide a journal or make concurrent shared writes an atomic filesystem snapshot.

See [acceptance tests](../tests/mapped-writeback/README.md) for host failure
injection, native alias/refault and pressure tests, hard-stop disk verification
and measured repeated lifetimes. General kernel allocation allowance failures
and unrelated operation/churn retention remain separate work.

## Verification (2026-10-09)

Both isolated production architecture builds pass. Host ASan/UBSan runs cover
EXT2 mapping/writeback failures, the production alias bridge and existing
anonymous pager/source/codec/store regressions. The block-cache suite passes
failure propagation and retry tests. An independent lifetime review found no
remaining blocker after the empty-shadow and reclaim-cursor regressions were fixed.

Native QEMU runs pass sync, syncfs, background, shared/private churn and file
pageout on both architectures. The final pressure fixtures populate an 8 MiB
file, then exceed free RAM plus the block cache by 24 MiB. They verify automatic
file eviction, dirty file refault and all anonymous bytes within the configured
compression capacity, without an active swap device. Both disk images match the
expected bytes after the guest is stopped. Existing encrypted disk paging and
swapoff guests also pass on both architectures.

After warmup, 200 native shared write/pageout/refault operations keep every live
slab size class flat on both architectures. The broader ARM ops/churn/cache and
desktop idle/apps/drag scenarios complete. Those broad workloads still show
inherited mkdir/process-churn retention; they do not establish global leak freedom.
The complete allocation audit has 432 ARM and 318 x86 warning sites, unchanged
from its committed baseline, with no new/increased group. Its 179 inherited
allowance failures remain, and the allowance file is unchanged.
