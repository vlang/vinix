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
`MPOL_F_NODE` query returns the first node in the weighted mask for the
indexed subset. The allocation-order cursor for kernel and page-cache
allocations, shared anonymous mapping phase, explicit shared range policies,
optional mode flags, and translated or 32-bit policy calls remain open.

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
