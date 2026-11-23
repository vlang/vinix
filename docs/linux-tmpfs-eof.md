# Native tmpfs and memfd mmap faults past EOF

A native mapping may extend beyond the current end of a tmpfs file or
memfd. The final partial page remains accessible. If an
accessible mapping faults on a whole page beyond EOF, the kernel delivers
`SIGBUS` with `BUS_ADRERR` and the faulting address. This applies to both
private and shared views. A protection violation takes precedence and
delivers `SIGSEGV` with `SEGV_ACCERR`. Checked syscall copies report
`EFAULT`.
[Linux shmem faults](https://raw.githubusercontent.com/gregkh/linux/v6.12.51/mm/shmem.c)
[AArch64 signal delivery](https://raw.githubusercontent.com/gregkh/linux/v6.12.51/arch/arm64/mm/fault.c)
[x86-64 signal delivery](https://raw.githubusercontent.com/gregkh/linux/v6.12.51/arch/x86/mm/fault.c)

Tmpfs checks the page offset under the inode lock each time it supplies a
page. A later fault can therefore use a newly grown extent. Shrinking the
file changes the outcome for pages that still have to fault in. The
resident-page qualification below covers aliases populated before the
shrink. Beyond-EOF faults on other filesystems remain open.

## Qualification

The probe uses a nonzero file offset and checks zero padding in an
initially partial last page. It checks 28
signal outcomes across private and shared mappings of a tmpfs file and a
memfd. It verifies the default termination signal, handled fault metadata,
protection precedence, checked user copies, and access after growth or a
shrink below a still-unfaulted page.

The production kernels were built from `bbd75acf2` plus the archived source
patch. The same probe ELFs passed on Vinix and Linux 6.12.51 on both
architectures. Both original kernels failed the first private read past EOF
by returning a zero byte.

| Architecture | Probe ELF SHA-256 prefix | Vinix kernel SHA-256 prefix |
| --- | --- | --- |
| AArch64 | `bf3a6dbbd5d3e8db` | `a3fda1703a944264` |
| x86-64 | `11934a0e0ffe53c3` | `b9d7a89d60b6f635` |

The `memfdseals`, `remapfile`, `weighted`, `runtime`, `seccomp`, and
`altstackhandler` cases passed on both architectures. The `tidfault` case
also passed on both, with flat tracked storage across all four cohorts.
The first x86-64 run timed out in the third cohort. The retry used the
same kernel and fixture ELF with a 900-second limit. The allocation checker
reproduced the existing baseline failures and the same 307 AArch64 and
255 x86-64 sites.

The verified archive is at `~/.cache/vinix-r15/tmpfs-eof/qualification.tar.zst`,
with SHA-256
`7735a1ca3adb1bd19158d82e81b1b97ac790f01ff6d48b6adeb481fc43fd6d0d`.
The verified x86-64 retry is at
`~/.cache/vinix-r15/tmpfs-eof/tidfault-retry.tar.zst`, with SHA-256
`2a51fc204f50eaefae03d2c93537469ca1782343b804a41894c12623a489d7d5`.

## Truncation of resident tmpfs and memfd mappings

Shrinking a tmpfs file or memfd revokes whole pages beyond its new end from
shared and private views, including pages inherited through fork and private
copy-on-write pages. The kernel waits for the translation invalidations before
releasing the frames. A fault that obtained an old page before the shrink
revalidates the mapping before installing it. Growth can then fault in fresh
pages. [Linux shmem shrink and invalidation](https://raw.githubusercontent.com/gregkh/linux/v6.12.51/mm/shmem.c)

The retained partial cache page keeps its prefix and gets a zeroed tail.
A private copy of that page keeps its own bytes. The inode's block count
drops when whole cache pages are released.

Revocation holds the affected page-map locks and the file-mapping registry
through the translation invalidations. A contended map causes a retry
before any translation changes. Borrowed initramfs snapshots of retained
partial pages remain outside this qualification.

The probe covers offset aliases, a split private mapping, a checked copy
into a cold private page, and a child that touches its inherited page
before the parent truncates. It checks the retained partial page, the
inode block count, and zero-filled refaults after regrowth.

The production kernels were built from `6cf645904` plus the archived
patch. Both original kernels returned the old byte on the first resident
read past the new EOF. The same probe ELFs passed on the corrected Vinix
kernels and on Linux 6.12.51.

| Architecture | Probe ELF SHA-256 prefix | Vinix kernel SHA-256 prefix |
| --- | --- | --- |
| AArch64 | `06378141eaa5b826` | `cd97749d6ffba978` |
| x86-64 | `beca6eb39290c1c6` | `609235f3ac4dce0f` |

Free memory stayed flat after 128 measured grow, fault, copy-on-write, and
shrink cycles on each architecture. The allocation checker reproduced the
baseline failures and the same 307 AArch64 and 255 x86-64 sites. Independent
review covered lock ordering, fault revalidation, fork, and frame ownership.

The `memfdseals`, `remapfile`, `weighted`, `shmabi`, `truncateabi`,
`truncatepath`, and `futexkeys` regressions passed on both architectures.
The resumed runs used the same final kernels as the resident-page probe.

The qualification archive is at
`~/.cache/vinix-r15/tmpfs-truncate/qualification.tar.zst`, with SHA-256
`b33cc9215bfe7dc7c342210d1ee79c3f7c99ddc1d536d27a46ed94fe41a25089`.

## Shared futex keys across shrink and regrowth

Shared mappings of tmpfs and memfd identify a futex by an inode ID and a file
byte offset. The page map lock keeps the mapping and its resident translation
stable while the kernel takes that key. The queue stores only the numeric ID
and offset. Shared wake requires a readable address, so a wake on a truncated
page returns `EFAULT`. [Linux futex key lookup](https://raw.githubusercontent.com/gregkh/linux/v6.12.51/kernel/futex/core.c)

The probe confirms a legacy `FUTEX_WAIT` is queued by moving it to a second
word on the page with `FUTEX_CMP_REQUEUE`. It shrinks the file, checks the
truncated address, then touches a different inode before regrowing the
original file. It checks that another inode, page, or word cannot wake the
waiter. A futex2 wake through a mapping of the second file page returns one.
The probe runs this sequence on tmpfs and memfd after its 20 existing alias
and flag checks.

The production kernels were built from `92f3048d9` plus the archived patch.
The previous Vinix kernels returned zero on the alias wake after regrowth.
The same probe ELF passed on the corrected Vinix kernel and on Linux 6.12.51
for each architecture.

| Architecture | Probe ELF SHA-256 prefix | Vinix kernel SHA-256 prefix |
| --- | --- | --- |
| AArch64 | `1d8fbe777141b3e8` | `2ebf0431d31f34fa` |
| x86-64 | `7ec0a27f6205677b` | `0c222847b93995c0` |

The `futexqueue`, `futex2`, `futex`, `futexbits`, `shmabi`, `mmap`, and
`memfdseals` regressions passed on both architectures. The static allocation
checker reproduced the baseline failures and the same 307 AArch64 and 255
x86-64 sites. The generated Linux dispatch coverage check passed.

The qualification archive is at `~/.cache/vinix-r15/tmpfs-futex/qualification.tar.zst`,
with SHA-256 `4b1a3c8cf942adac1422767a38b8377d4251a3c8a72e557234c4e17325f673c2`.
