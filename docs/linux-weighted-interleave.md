# Native weighted NUMA interleave

`set_mempolicy` and `mbind` accept `MPOL_WEIGHTED_INTERLEAVE` for thread and
private anonymous range policies. An explicit range overrides the task policy.
The page index selects a slot in a repeating sequence. Each eligible node
contributes consecutive slots equal to its current weight, in node order.
For example, weights three and two give a five-page period. The page index
determines placement even when pages fault out of order. [Linux 6.12.51 memory policy implementation](https://github.com/gregkh/linux/blob/v6.12.51/mm/mempolicy.c)

Each boot-time node has a root-owned `0644` file under
`/sys/kernel/mm/mempolicy/weighted_interleave/`. Reads report the effective
weight and a newline. Writes accept an unsigned byte in decimal, octal,
or hexadecimal. Zero or a blank line restores weight one. A zero-length
write completes as a no-op. A numeric write takes effect immediately for
future allocations using existing policies. One allocation uses a consistent
weight set. [Linux sysfs attribute implementation](https://github.com/gregkh/linux/blob/v6.12.51/fs/sysfs/file.c)

An oversized write consumes at most one native page. The I/O layer bounds
the payload copy for scalar, positioned, and vectored writes. The no-address
`MPOL_F_NODE` query returns the next allocation-order node. General kernel
allocation and the block cache, shmem home-node overrides, page
migration, optional mode flags, and translated or 32-bit policy calls
remain open.

## Qualification

The probe checks sysfs ownership permissions, syntax, defaults, short reads,
page-sized file metadata, and oversized writes. It also checks the mode and
mask returned by queries, a weight update on an existing policy, out-of-order
faults into both nodes, and the precedence of a weighted range over a task
bind. The two-node run takes the same binary through both weight periods.

Both production kernels were built from `20d5ee8b6` plus the archived
source patch. The same probe ELF per architecture passed on Vinix and
Linux 6.12.51 in single- and two-node guests.

| Architecture | Probe ELF SHA-256 prefix | Vinix kernel SHA-256 prefix |
| --- | --- | --- |
| AArch64 | `8d71ae4e3d738c66` | `f618ae5fa1835902` |
| x86-64 | `7dc28ebcb3ede0da` | `39e7c900c85e0e8b` |

The `mempolicy`, `prefmany`, `taskpolicy`, `mbind`, and `memhome` regressions
passed on both architectures. The allocation checker reproduced the baseline
failures and the same 307 AArch64 and 255 x86-64 allocation sites. Independent
review checked sysfs buffer lifetimes and weight-lock release before allocation.

Run `tests/linux-compat/run --arch ARCH --kernel-dir DIR --state-dir
FRESH-DIR --cases weighted --numa` on Vinix. The Linux reference takes
`--arch ARCH --case weighted --kernel LINUX --init FRESH-DIR/weighted/init
--state-dir LINUX-STATE --numa`. Omit `--numa` for the single-node run.
[Linux reference runner](../tests/linux-compat/syscall-reference.v)

The restored and verified archive is
`~/.cache/vinix-r15/weighted/qualification.tar.zst`, with SHA-256
`434e24b0dcb476706e3550dce31fad6cee2a01fbe58c35eb4d02d9c05f9311f4`.

## Guarded write buffers

The descriptor and user address range are validated before the payload is
copied. A guard page beyond the consumed prefix can be skipped. An
inaccessible byte inside the prefix returns `EFAULT` before the weight
changes. A vectored write validates every header, joins the consumed
segments, and submits them as one store. Positioned writes preserve the
descriptor offset. [Linux 6.12.51 kernfs write implementation](https://github.com/gregkh/linux/blob/v6.12.51/fs/kernfs/file.c)

The `weighted` fixture checks these rules through `write`, `pwrite`,
`writev`, `pwritev`, and `pwritev2` at the current offset. It checks faults
in both the consumed payload and an unused vector header.

Both production kernels were built from `365a9d4c3` plus the archived
source patch. The same fixture ELF per architecture passed on Vinix and
Linux 6.12.51 in single- and two-node guests. The previous Vinix kernels
returned `EFAULT` on the first guarded scalar write on both architectures.

| Architecture | Probe ELF SHA-256 prefix | Vinix kernel SHA-256 prefix |
| --- | --- | --- |
| AArch64 | `b063f28ec904b432` | `0fd885423b282d94` |
| x86-64 | `bd01348e276cbf03` | `54d9f13491dba4fe` |

The `iovimport`, `iovposition`, `iovstream`, and `iovpacket` regressions
passed on both architectures, including their allocation-retention checks.
Independent review checked the borrowed descriptor and buffer lifetimes,
scratch cleanup, and permission checks around the copy. The allocation
checker reproduced the baseline failures and the same 307 AArch64 and
255 x86-64 allocation sites.

The restored and verified archive is
`~/.cache/vinix-r15/weight-store/qualification.tar.zst`, with SHA-256
`f7d2ce17f0e23ccdee7564c463991f5af876ab7845b1fcf3c44f783c26153bb8`.

## Sparse shared memory

With a weighted task policy, a sparse tmpfs or memfd page allocated by a
shared fault or a write uses the inode number plus the page's file offset
in pages. Aliases with different mapping bases and offsets see the same
physical page once it exists. Weight changes affect future allocations.
Named file data and mapper-owned pages retain their existing memory reserve
rules. Contiguous tmpfs storage and conversion of existing file data keep
their ordinary placement. [Linux 6.12.51 shared-memory allocation](https://github.com/gregkh/linux/blob/v6.12.51/mm/shmem.c)

The weighted fixture faults memfd and mounted tmpfs pages out of order
through an offset alias. It checks the resulting nodes and shared bytes,
changes a weight, writes into another hole, and checks where that page was
placed after clearing the task policy.

Both production kernels were built from `ad0bc958f` plus the archived
source patch. The same fixture ELF per architecture passed on Vinix and
Linux 6.12.51 in single- and two-node guests. The previous Vinix kernels
failed the inode-relative placement check in both two-node guests.

| Architecture | Probe ELF SHA-256 prefix | Vinix kernel SHA-256 prefix |
| --- | --- | --- |
| AArch64 | `ed57cacad9b522ab` | `32e3d3ab74c08dd0` |
| x86-64 | `0acc51bb812eabce` | `0ebba782cf72652d` |

The `memfdcreate`, `memfdseals`, and `shmabi` regressions passed on both
architectures. Independent review checked page ownership, reserve
accounting, and lock ordering. The allocation checker reproduced the
baseline failures and the same 307 AArch64 and 255 x86-64 allocation sites.

The restored and verified archive is
`~/.cache/vinix-r15/weighted-shmem/qualification.tar.zst`, with SHA-256
`9baf409ba1a58898d0eb9e8fd63e6a88d4763023abd7ef2ef641e46f03ea5042`.

## Shared anonymous placement

Shared anonymous interleave uses the backing object's identity plus the
page offset in the object. Vinix uses the shared mapping's serial as the
inode number and reports it with the backing offset and `/dev/zero (deleted)`
in `/proc/maps`, using device `00:00`. Fork aliases, splits, and moving
remaps retain the identity and phase. Linux uses a hidden shmem file and
its inode. [Linux 6.12.51 shared-memory allocation](https://github.com/gregkh/linux/blob/v6.12.51/mm/shmem.c)

The fixture forks with an unfaulted shared region, moves a middle slice
with `mremap`, and sets a weighted task policy before faulting pages out of
order. It checks the inode and offset of both views, the resulting node of
each new page, and the bytes visible through the child's original mapping.
The fixture uses a large reservation to exercise Vinix's lazy path.
Small shared mappings can still allocate pages at `mmap` time.

Both production kernels were built from `79cbd5eca` plus the archived
source patch. The same fixture ELF per architecture passed on Vinix and
Linux 6.12.51 in single- and two-node guests. The previous Vinix kernels
failed the shared backing identity check in both two-node guests.

| Architecture | Probe ELF SHA-256 prefix | Vinix kernel SHA-256 prefix |
| --- | --- | --- |
| AArch64 | `776b4bd906fe2c61` | `bc378cfbc5eac0d9` |
| x86-64 | `a94ff9b7e7e8c46e` | `72a31ec837dbc171` |

The `mmap`, `sharedmem`, `mbind`, and `mseal` regressions passed on both
architectures, including the `mseal` allocation-retention checks.
Independent review checked backing identity across range edits, lock
coverage, and proc text ownership. The allocation checker reproduced the
baseline failures and the same 307 AArch64 and 255 x86-64 allocation sites.

The restored and verified archive is
`~/.cache/vinix-r15/weighted-anon/qualification.tar.zst`, with SHA-256
`dbc4ab275322f20788436cdd5fdf50af43a19c243112729b4bd8074408cb90e0`.

## Allocation order for mapped file pages

Cold pages brought into the ext2/VJFS inode mapping cache use a per-thread
cursor under a weighted task policy. A successful `set_mempolicy` starts
the cursor at the first selected node. Starting a turn samples that node's
current weight and successive allocations there spend the saved count.
The next turn reads its own live weight. A no-address `MPOL_F_NODE` query
reports the next node and leaves the cursor available for the next
allocation. Fork and thread creation copy its current state and exec
carries it forward. Indexed anonymous and shmem allocation use their
existing backing indexes. [Linux 6.12.51 memory policy implementation](https://github.com/gregkh/linux/blob/v6.12.51/mm/mempolicy.c)

The probe maps a sparse file through two aliases, visits cold pages out of
offset order, and checks that an alias to a cached page preserves its node
and the cursor. Vinix runs it on a private ext2 image and checks the exact
sequence with a mid-turn weight change. The diskless Linux reference uses
ramfs and checks each cold page against the immediately preceding next-node
query. Linux can spend additional turns on kernel allocations during the
same fault.

Both production kernels were built from `9ad9e3400` plus the archived
source patch. The same fixture ELF per architecture passed on Vinix with
ext2 and on Linux 6.12.51 with ramfs in single- and two-node guests. The
two-node VJFS runs passed on both architectures. The prior Vinix kernels
failed when the next allocation was due on node one.

| Architecture | Probe ELF SHA-256 prefix | Vinix kernel SHA-256 prefix |
| --- | --- | --- |
| AArch64 | `e67d3a166b6783de` | `2946456c6bf31b61` |
| x86-64 | `1278f6a0da3baaf9` | `4ace234930d70f46` |

The `weighted`, `taskpolicy`, and `cachestat` regressions passed on both
architectures. Independent review checked page ownership, reclaim locking,
reserve accounting, and cursor copies. The allocation checker reproduced
the baseline failures and the same 307 AArch64 and 255 x86-64 allocation
sites.

Run `build-support/run-v-tool.sh tests/linux-compat/run-mount.v --case
weightedcache --arch ARCH --kernel-dir DIR --state-dir FRESH-DIR --numa`.
Add `--journal` for VJFS. Pass `FRESH-DIR/init` to the Linux reference
runner with `--case weightedcache`. Omit `--numa` for single-node runs.

The restored and verified archive is
`~/.cache/vinix-r15/weighted-cache/qualification.tar.zst`, with SHA-256
`2b35428e734a8a6b3462465d18102a47a64720b38907eb0255456458124046c8`.

## Shared anonymous range policies

`mbind` on a shared anonymous mapping records policy intervals by backing
offset. A fork alias sees updates through a different address space.
An overlapping binding replaces the covered interval and preserves its
outer fragments. Clearing a binding restores the faulting thread's policy
for future allocations. Resident shared pages keep their data and placement.
A fault racing an update can use the policy it sampled before allocating.
Shared home-node overrides and page migration remain outside this subset.
[Linux shmem policy lookup and installation](https://github.com/gregkh/linux/blob/v6.12.51/mm/shmem.c)

The fixture forks before the parent installs weighted and bind intervals
and clears an interior slice. It checks the child's address-policy queries,
physical nodes, and task fallback, then checks the parent's view after it
clears the remaining policies. The Vinix probe also measures mapping
charges across 128 replacement and clear cycles after warm-up.

Both production kernels were built from `7a0e62fb1` plus the archived
source patch. The same fixture ELF per architecture passed on Vinix and
Linux 6.12.51 in single- and two-node guests. The previous Vinix kernels
returned `EOPNOTSUPP` when the parent tried to bind the shared range.

| Architecture | Probe ELF SHA-256 prefix | Vinix kernel SHA-256 prefix |
| --- | --- | --- |
| AArch64 | `8195fbd794dd2a97` | `b2ddc9be0b93459f` |
| x86-64 | `c5c8d51a9e54c006` | `31c890a088c41f3b` |

The `mbind`, `memhome`, `sharedmem`, and `mseal` regressions passed on both
architectures, including the `mseal` retention checks. Independent review
checked policy ownership, interval replacement, lock coverage, and fault
snapshots. The allocation checker reproduced the baseline failures and the
same 307 AArch64 and 255 x86-64 allocation sites.

The restored and verified archive is
`~/.cache/vinix-r15/shared-policy/qualification.tar.zst`, with SHA-256
`e3883665639fcaed5a8d29503964c54c4838133645fe1742cd0028274dcaf734`.

## Shared tmpfs and memfd range policies

`mbind` on a shared tmpfs or memfd mapping installs a policy by file
offset. The inode retains it after the installer unmaps, so independent
views and writes into sparse holes use the same policy. A range edit can
replace or clear an interior interval while preserving its outer fragments.
Weighted placement uses the inode number plus the file page index.
Clearing an interval restores the ordinary allocation path. Changing a
policy affects future allocations. [Linux shmem policy and allocation](https://github.com/gregkh/linux/blob/v6.12.51/mm/shmem.c)

The fixture installs overlapping weighted and bind intervals through an
offset view of a memfd and a mounted tmpfs file. It clears an interior
slice, unmaps the installer, writes into a bound hole, and checks policy,
data, and node location through a new view. It pins the task's fallback to
node zero to distinguish explicitly governed pages. The qualified path
covers `MAP_SHARED`. The private mapping checks appear below. Shmem
home-node overrides and migration remain open.

Both production kernels were built from `00b57ad54` plus the archived
source patch. The same fixture ELF per architecture passed on Vinix and
Linux 6.12.51 in two-node guests.

| Architecture | Probe ELF SHA-256 prefix | Vinix kernel SHA-256 prefix |
| --- | --- | --- |
| AArch64 | `a7eef657f92f3224` | `9b9736c7c9c7c719` |
| x86-64 | `61354865a4dcb80c` | `d6deab9e2d24c645` |

The `memfdseals` and `shmabi` regressions passed on both architectures.
Independent review checked inode and policy lifetimes, budget ownership,
and lock ordering. The allocation checker reproduced the baseline
failures and the same 307 AArch64 and 255 x86-64 allocation sites.

The archive was decoded and compared with the full evidence tree in place.
It is at `~/.cache/vinix-r15/tmpfs-policy/qualification.tar.zst`, with
SHA-256 `b146a08efcd40de3c4d407fbdc09a48d2dd2192653948ff749e7c887fe491017`.

## Private file copy-on-write policies

`mbind` on a private ext2 or VJFS mapping sets the policy on that view.
Reads can use the existing file cache. When a write makes a private copy,
the policy selects its node using the file page offset, including a
nonzero mapping offset. Another mapping of the file keeps its own policy
and sees the original data. [Linux indexed VMA policy lookup](https://github.com/gregkh/linux/blob/v6.12.51/mm/mempolicy.c)

The probe primes the cache on node zero and applies weighted interleave to
an interior range of a writable view. It covers both an initial write
fault and a write after a read fault. It checks the node of each copy,
the unaffected ranges and alias policies, and the cached data and node
after each private write.

Both production kernels were built from `b107daaed` plus the archived
source patch. The same probe ELF per architecture passed on ext2 in Vinix
and on ramfs in Linux 6.12.51 with two NUMA nodes. The cache cursor
controls in the fixture and the separate `mmap` and `mbind` regressions
passed on both architectures.

| Architecture | Probe ELF SHA-256 prefix | Vinix kernel SHA-256 prefix |
| --- | --- | --- |
| AArch64 | `61a109668f56edb0` | `2a109b3543574282` |
| x86-64 | `80a969cd8454b591` | `1c780c55c55fe0e0` |

The allocation checker reproduced the baseline failures and the same 307
AArch64 and 255 x86-64 allocation sites.

The archive was decoded and compared with the full evidence tree in place.
It is at `~/.cache/vinix-r15/private-file-policy/qualification.tar.zst`, with
SHA-256 `928cbb7b2e18f37326bb6b4631604020fc8d885f15d0cdc0c5a97260c31a6659`.

## Private tmpfs and memfd range policies

`mbind` through a private tmpfs or memfd view updates the inode's policy by
file offset. Shared and private aliases can query the same policy. New
private copies use the inode number plus the file page index for weighted
placement. After fork, a write that copies a private page uses the current
inode policy and preserves the parent's copy. Clearing the interval restores
the ordinary task allocation policy for future faults.
[Linux shmem policy lookup](https://github.com/gregkh/linux/blob/v6.12.51/mm/shmem.c)

The probe applies weighted interleave through an offset private view of each
backing type. It checks out-of-order writes into sparse pages through
private and shared aliases, verifies that private writes leave backing data
untouched, and changes the policy before a child writes to a page inherited
from its parent. It also checks that clearing the range is visible to the
shared alias.

Both production kernels were built from `8c2553555` plus the archived source
patch. The same probe ELF per architecture passed on Vinix and Linux 6.12.51
in two-node guests. The allocation checker reproduced the baseline failures
and the same 307 AArch64 and 255 x86-64 allocation sites.

| Architecture | Probe ELF SHA-256 prefix | Vinix kernel SHA-256 prefix |
| --- | --- | --- |
| AArch64 | `1d733fb8e865db19d` | `ac365cfb105e4dc3` |
| x86-64 | `68b822355e375c40` | `4317d0b4e65d07c1` |

The archive was decoded and compared with the full evidence tree in place.
It is at `~/.cache/vinix-r15/private-shmem-policy/qualification.tar.zst`,
with SHA-256
`f1ae547dce821a7083212a85bfb21f5da9dbaecc3787296be1484d54dd12e38c`.

## Private tmpfs and memfd read faults

A private mapping can read the inode's existing cache page. It sees
changes through shared aliases until its first write, which makes a copy
on a node selected by the current policy. `MADV_DONTNEED` drops the copy
and lets the next fault read the cache again, including after the last
descriptor closes. [Linux shmem fault implementation](https://github.com/gregkh/linux/blob/v6.12.51/mm/shmem.c)

The inode owns the cache frame. Each private mapping's shadow page table
owns a physical reference, with separate references for forked shadows.
Unmap, copy-on-write, and discard release those references. This uses
the private copy-on-write capability while tmpfs keeps its existing
in-memory write path.

Private faults on borrowed initramfs storage still copy only the pages
they touch. Cold cache faults follow the existing tmpfs allocation
path, whose task-policy fallback supports weighted interleave.
Faults on missing pages beyond EOF have their own qualification.
[Tmpfs and memfd EOF faults](linux-tmpfs-eof.md)

Production kernels built from `e070f0fad` plus the archived patch passed
the same probe ELFs as Linux 6.12.51 on two-node AArch64 and x86-64
guests. The original AArch64 kernel failed the cached-node assertion
with the same ELF. The `memfdseals`, `shmabi`, and `remapfile` regressions
passed on both architectures.

| Architecture | Probe ELF SHA-256 prefix | Vinix kernel SHA-256 prefix |
| --- | --- | --- |
| AArch64 | `7e1137da19796227b` | `ffe0d44a546758af` |
| x86-64 | `dd5b6974cc063239` | `d9641cb9ce851a07` |

After warmup and vnode reclamation, 128 cache-to-copy-to-discard cycles
reduced free memory by one AArch64 page and five x86-64 pages, within the
eight-page guard. The allocation checker had the same baseline failures
and 307 AArch64 and 255 x86-64 sites. Independent review checked the
fault, fork, discard, and teardown references.

The verified archive is at
`~/.cache/vinix-r15/private-shmem-read/qualification.tar.zst`, with SHA-256
`4d0accd6f4e4e87d822515ad5f337ac982e85c05043163743d0ff77faafac254`.
