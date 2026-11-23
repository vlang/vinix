# Execute-sealed memfds

`memfd_create(MFD_NOEXEC_SEAL)` creates a `0666` file with `F_SEAL_EXEC`
already set. The initial mode is independent of umask. Combining
`MFD_NOEXEC_SEAL` with `MFD_EXEC` returns `EINVAL` before name import.
The descriptor can accept additional seals
with or without `MFD_ALLOW_SEALING`. Adding seals requires a writable
description. [Linux 6.12.51 memfd creation](https://github.com/gregkh/linux/blob/v6.12.51/mm/memfd.c#L311) [Linux 6.12.51 seal checks](https://github.com/gregkh/linux/blob/v6.12.51/mm/memfd.c#L215)

Tmpfs serializes `F_SEAL_EXEC` and execute-bit changes with the inode's
lock. Descriptor and pathname chmod use the same guard, as do Vinix POSIX
ACL changes that affect the mode. Read and write permission changes still
work. The sealed `0666` mode causes `execveat` to return `EACCES` for a
valid ELF. `mmap` continues to apply its usual protection rules. [Linux 6.12.51 tmpfs mode check](https://github.com/gregkh/linux/blob/v6.12.51/mm/shmem.c#L1121)

## Qualification

The same native probe ELF per architecture passed on Vinix and Linux
6.12.51. It covered flag conflicts, initial seals, direct and path-based
chmod, empty-path chmod through an `O_PATH` alias, read-only seal queries,
later growth seals, shared writable and private executable mappings, and
`execveat` on both executable and execution-sealed copies of the probe.
The Vinix runs also checked that an ACL can change read and write permissions
and that an ACL requesting execute bits fails with `EPERM`.

Production Vinix kernels came from `03a04c5fe` plus this change. Both
baseline kernels rejected `MFD_NOEXEC_SEAL` with `EINVAL` using the final
probe. The `sharedmem`, `fchmodat2`, and `membsync` regressions passed on
both updated kernels. The allocation checker reported the same existing
failures and the same 306 AArch64 and 254 x86-64 allocation sites as the
baseline.

| Architecture | Probe ELF | Vinix kernel | Vinix serial log | Linux serial log |
| --- | --- | --- | --- | --- |
| AArch64 | `7f0bd65efcaf7233` | `99519b85ce473f10` | `0eaa783d6dfd7dc7` | `155c669bb1c223fc` |
| x86-64 | `f36afd295d1db619` | `caa0304c927dd281` | `d194b961b73ecc71` | `cb3e7ac37d25542a` |

Hashes are SHA-256 prefixes. The archive is
`~/.cache/vinix-r15/memfd-noexec/qualification.tar.zst`, with SHA-256
`1d6ef06695c5af4d07e97188650f3c772f6b03797dc50f5e9d7aec49b05e0b10`.

## Limits

`MFD_HUGETLB` remains open. The automatic shrink,
grow, write, and future-write seals that Linux applies when `F_SEAL_EXEC`
is added to an already executable inode remain open. [Linux 6.12.51 implied seals](https://github.com/gregkh/linux/blob/v6.12.51/mm/memfd.c#L245)

See [PID namespace memfd policy](linux-memfd-policy.md) for when the kernel
applies `MFD_NOEXEC_SEAL` automatically.
