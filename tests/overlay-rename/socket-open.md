# Ordinary socket pathname opens

An ordinary `open()` of a bound UNIX socket pathname used to acquire the live
endpoint as a new transport description. Reading, accepting or closing that
description could affect the original socket. The preceding `O_PATH` fix limited
metadata descriptions, but ordinary pathname opens still succeeded.
[Linux open(2)](https://man7.org/linux/man-pages/man2/open.2.html) requires `ENXIO`
for an accessible UNIX socket pathname.

VFS now refuses non-`O_PATH` socket opens after existing permission and read-only
checks, before resource-open or FD creation. No endpoint reference is acquired.
The copied user pathname is freed by the existing defer. Independent review
approved the V source and both generated C outputs: no new allocations or
reference releases, and existing permission, symlink, directory and exclusive
creation errors keep their ordering.

The V probe checks all three access modes while the pathname has mode 0000;
each returns `EACCES`, and `O_PATH` metadata access still succeeds. With mode
0777, all three modes are tested with no extra flag and with `O_NONBLOCK`,
`O_APPEND`, `O_TRUNC`, `O_CREAT`, `O_SYNC`, `O_CLOEXEC` and `O_NOFOLLOW`: all 24
calls return `ENXIO`. Exclusive creation keeps `EEXIST`; directory-only lookup
keeps `ENOTDIR`. A symlink to the socket returns `ENXIO` when followed and
`ELOOP` with ordinary `O_NOFOLLOW`. `O_PATH|O_NOFOLLOW|O_CLOEXEC` holds the symlink
itself. Inode identity, ownership, mode and link count remain unchanged. The
listener then accepts a real connection and transfers data, including after
unlink and grace. Earlier metadata refusal and descriptor-transfer checks remain
part of every cycle.

Results on 14 October 2026 are retained under `build/development17-20261013`:

| State | Result |
| --- | --- |
| `socketopen-arm-before-b`, `socketopen-x86-before-c` | Saved kernels from the metadata fix return descriptor 6 for plain `O_RDONLY`; assertion 477 fails. |
| `socketopen-arm-basic-a`, `socketopen-x86-basic-a` | Expanded disk-free native probe passes as UID/GID 1000, with groups cleared and networking disabled. |
| `socketopen-arm-linux-a`, `socketopen-x86-linux-b` | Each identical native probe ELF passes in the Linux 6.12.51-0-virt reference guest. |
| `socketopen-arm-after-b`, `socketopen-x86-after-a` | Direct ext2 and overlay-upper socket checks, permission refusals and read-only remount pass. Two batches of 32 cycles per backend retain equal live slab/large counts. |
| `socketopen-arm-all-a`, `socketopen-x86-all-a` | Complete existing overlay regressions pass, including flat mixed-lifetime samples. |

All 18 ARM slab classes plus the large count, and all 14 x86 slab classes plus
the large count, match between repeated batches. Writes-after-free counters
remain zero. All four final volumes pass read-only `e2fsck -f -n`. The allocation
allowlist audit still reports the same 182 baseline file/kind findings; no
allowlist entries were added.

| Input | SHA-256 |
| --- | --- |
| Fixed ARM kernel | `cdbea3d86cb8e2f08325fe8b34f0acd2a13e3bc3fd9cd6f50f051d01504c9046` |
| Fixed x86 kernel | `0b583faf13b420f4a0d8594c32dee5d51415b45f31e64bc6137811735b49f680` |
| Expanded operation fixture | `12fa487641627e22d8c0b5c1832316d37d3a6018bd3c00552c887a57dfbee36a` |
| Expanded socket fixture | `91b6c95f2814b560b31a82550bdb2e576adb273629405a23bdbd05aaecd8cadb` |
| Shared ARM native/Linux probe | `e2c0df5aff56a5caa6219e263ed27a51dde18c946dd9bfadfc578bb2562363d5` |
| Shared x86 native/Linux probe | `c054686b16654e6147957a6e16e37aa44f0481c68d8437a715e9222262c07a21` |

Builds use the existing isolated worktrees, preserved `f6358ec` V compiler and
link seed 17. The assertion-enabled `socketopen-evidence.v` checks source/input
hashes, both controls, native/Linux probe identity, complete allocation samples
and filesystem consistency; its result is `socketopen-evidence-final.log`.
It normalizes only the three concurrent per-open creation bookkeeping changes
outside the isolated worktrees. Review is saved in `socketopen-lifetime-review.md`.
Earlier fixture compilation and host disk exhaustion attempts remain separate.
Only owned staging/firmware and regenerable objects were reclaimed; kernels,
generated C, ISO/volume images, sources and receipts were retained.

Repeat the native and Linux checks using [the controller instructions](README.md).
The Linux kernels and reference boot policy match the preceding
[metadata qualification](socket-access.md). This qualifies pathname-open
authorization and repeated clean storage operations; broader open flag/error
precedence, crash recovery and full OCI/rootless/server acceptance remain open.

The subsequent [pathname permission correction](socket-permissions.md) requires
write access for connections and addressed datagrams, using an expanded fixture.
