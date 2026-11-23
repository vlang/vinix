# Native process_madvise

`process_madvise` accepts a pidfd and an iovec of virtual ranges. It returns
the original byte count of completed entries, including a completed prefix
when a later entry fails. Within each entry, advice can still apply on both
sides of an unmapped hole before the kernel reports `ENOMEM`.

The pidfd resolves the target by process identity. The kernel retains its
address space during the operation. Remote advice requires permission to
inspect the target using filesystem credentials and effective capabilities,
plus `CAP_SYS_NICE` in the initial user namespace. Local advice through a
self pidfd requires no extra capability. [Linux 6.12.51 syscall and permission checks](https://github.com/gregkh/linux/blob/v6.12.51/mm/madvise.c#L1491)

- `MADV_WILLNEED` prefetches stored pager pages and requests file readahead
  where the mapping supports it. Untouched anonymous ranges stay sparse.
- `MADV_COLD` clears the referenced bit of resident pages. Vinix's current
  anonymous reclaim scan does not use PTE age to rank candidates.
- `MADV_PAGEOUT` stores eligible anonymous and private copy-on-write pages
  through the Vinix pager. It skips multiply mapped frames and does not
  evict clean file-cache pages. `COLD` and `PAGEOUT` reject locked mappings,
  device mappings, and immutable kernel-managed ranges.
- `MADV_COLLAPSE` accepts an empty vector. A nonempty range returns `EINVAL`
  because Vinix does not promote pages to transparent huge pages.

## Qualification

The same probe ELF per architecture passed on Vinix and Linux 6.12.51. It
checks argument width and error order, partial vector results, locked ranges,
VMA holes, sparse reservations, remote filesystem credentials and capabilities,
reaped pidfds, and resident shared aliases. It verifies actual eviction and
refault on Vinix. The Linux reference guests ran without swap. The previous
Vinix kernels returned `ENOSYS`.

Production kernels used `fc07465c2` with the archived source patch. The paging
host fixtures passed with AddressSanitizer and UndefinedBehaviorSanitizer.
The allocation checker reported the same existing failures and the same
306 AArch64 and 254 x86-64 allocation sites as the baseline.

The `pidfdgetfd`, `fsuid`, `cappid`, `mmap`, `memfdseals`, and `mapstorage`
regressions passed on both architectures. `mseal` passed on x86-64. Its first
AArch64 run measured 79 to 81 live large pages across 200 cycles with no slab
growth. The candidate rerun and the previous kernel both passed all 168
checks, each holding steady at 81 large pages.

| Architecture | Probe ELF | Vinix kernel | Vinix serial log | Linux serial log |
| --- | --- | --- | --- | --- |
| AArch64 | `6c6a6cde8cc34672` | `4084fbc6fe057615` | `0b22114926de3913` | `dbc85273d5ce95d6` |
| x86-64 | `6ffe5a6370634003` | `96f6a3dcc58c1540` | `5f833d7320922cc0` | `b011079d80ec48f8` |

Hashes are SHA-256 prefixes. The restored and verified archive is
`~/.cache/vinix-r15/process-madvise/qualification.tar.zst`, with SHA-256
`88ffba054f019981f3315045feea2df5452d125e69bcd835503bc40a7cddeed4`.
