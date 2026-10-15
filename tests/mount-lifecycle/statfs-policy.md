# Filesystem statistics and mount policy

`statfs` now retains the resolved path's mount route. `fstatfs` reads the actual
mount saved in its open description, under that mount's lock. It does not map
that mount's stable ID into the caller's namespace: after `unshare`, a remount
of the copy changes pathname and newly opened descriptor reports while
inherited descriptions keep reporting their original mount.

Both queries add `ST_VALID` and the supported `ST_RDONLY`, `ST_NOSUID`,
`ST_NODEV`, `ST_NOEXEC`, `ST_NOATIME`, `ST_NODIRATIME` and `ST_RELATIME` flags.
The encoder translates `MS_RELATIME` to its different statfs bit, omits
`MS_STRICTATIME` and private executable-policy bits, and preserves backend
flags and backend read-only status. Backend counters and the existing zeroed
120-byte serializer remain. Existing pathname authorization, descriptor MAC
checks, error handling and descriptor release are retained. A stack cursor
and scalar flag reads introduce no heap owner, reference transition or free.

[Linux v6.12 `fs/statfs.c`](https://github.com/torvalds/linux/blob/v6.12/fs/statfs.c)
calculates flags from the resolved path or saved `file.f_path` and combines
mount and superblock flags with `ST_VALID`.

Use `--case fsflags` or `sf-0` through `sf-9`. Native `all` and Linux
`move-reference` include all ten cases:

| Case | Routes exercised |
| --- | --- |
| 0 | Directory descriptors, both writable/read-only bind directions |
| 1 | Descriptors opened after a namespace copy, both directions |
| 2 | Separate chroot root and cwd aliases, both directions |
| 3 | Absolute paths and symlinked parents, both directions |
| 4 | Read-only directory retained after lazy detach |
| 5 | Descriptions retained after a worker namespace retires |
| 6 | Read-only source and writable bind established before querying |
| 7 | Descriptions inherited across a namespace copy with unchanged flags |
| 8 | Original writable descriptions, copied mount remounted read-only/nodev/relatime |
| 9 | Original read-only/nosuid/noexec descriptions, copied mount remounted writable |

Live routes exercise eleven flag configurations eight times each, including
individual supported bits, combinations and reset to strict atime. Queries
check exact flags through cwd/marker paths, regular files, `O_PATH` descriptions
and read-only directory descriptions, while the other bind remains writable.
Strict atime is explicit so Linux's default relatime does not obscure the
comparison. Detached, retired and inherited routes retain their baseline
policy. The two divergent-copy cases repeat 128 times. Stable backend fields
and zero spare words are checked; free-space counters may vary with memory
pressure. UID/GID 1000 can inspect the searchable roots and protected file's
statistics; its remount is refused with `EPERM` and reports remain unchanged.
Missing/empty paths, invalid descriptors and invalid output pointers have
separate error checks.

Evidence from 2026-10-15 is retained under `build/development17-20261013`:

| States | Result |
| --- | --- |
| `mount-fsflags-{arm,x86}-sf-{0,4,5,8,9}-before-e` | The prior kernels return zero flags on live, detached, retired and pre-copy mounts. |
| `mount-fsflags-{arm,x86}-fsflags-after-b` | All ten corrected native cases pass. |
| `mount-fsflags-arm-all-after-a` | The cumulative native mount suite passes, including inode flags, writers, node creation and access queries. |
| `mount-fsflags-{arm,x86}-linux-b` | The same final probe ELFs pass the portable Linux 6.12.51 suite. |

| Architecture | Kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `28d66c50d042b7d70e37266fd3d32331c972aaa1af764157d31d9a719b801769` | `9cd3769ae46c412db2de8e3386c311aa4c1bff62189d9af63e291254a91c43ed` |
| x86_64 | `5b16b41197d21dce8ceada40cc24fc346c9458a6f69c8a171b7cd54098203cf4` | `705cc6b189780058c072c1613e84e3252b38d05478a507a77081183a62562b00` |

`mount-fsflags-{arm,x86}-input` retains complete source manifests, generated C,
source snapshots and kernel hashes. Builds use V source
`f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link seed 17. Native ARM uses HVF/four CPUs; x86 uses TCG/two, with
1024 MiB. Linux uses HVF/TCG, two CPUs and 512 MiB. Old controls, cumulative
ARM and Linux runs allow 600 seconds; focused native runs allow 900 seconds.
Networking is disabled.

Earlier compile/precondition failures and the first Linux run's shared fixture
directory collision remain in their original result directories. The first
corrected native runs and x86 Linux attempt hit the host's disk limit. Fresh
final runs use the corrected fixture and verified shared artifacts. Historical
boot images, initramfs archives and build objects were losslessly compressed;
their decompression hashes were checked before removing raw copies. Sources,
generated C, probe ELFs, linked kernels, logs and receipts remain available.

The isolated builds extend the qualified access-query inputs by changing only
`kernel/fs/vfs.v` and `kernel/fs/mount_policy.v`. The baseline still excludes
the pre-existing open-created descriptor hunks, staged pointer-return spelling
edits and earlier fcntl/descriptor/lock changes described in
[the writer qualification](writer-policy.md). The complete current checkout
kernel was not built or booted.

The assertion-enabled source/C audit compares every parsed namespace-qualified
generated function with the prior build after temporary/discard normalization.
Only the two statfs syscalls and serializer change; two helpers are added.
Complete function comparisons retain all prior checks and cleanup, including
the added parent lookup's existing error cleanup. The mount lock is released
before backend dispatch. The receipt audit pins all twenty-two fixture files,
controllers, artifacts, old-kernel controls and native/Linux shared probe and
generated C identity in `mount-fsflags-evidence-a.log`. Per-architecture
`statfs-c-audit.txt` and `mount-fsflags-source-evidence-a.log` record source/C
checks. The post-commit audit accounts for the same three
excluded open-created VFS hunks and preserves other sessions' staged edits.

Concurrent mount/cwd/namespace changes, device and anonymous descriptions,
filesystem-wide remount semantics, broader authorization combinations and
persistent/overlay integration remain open. The other inherited-descriptor
policy lookups are not changed by this reporting fix. No allocation-flatness
or mount reclamation claim is made. A new cumulative native x86 run and desktop
performance scenarios are outside this qualification. Full OCI/rootless
acceptance and roadmap section 17 remain in progress.
