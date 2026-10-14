# Timestamp attachment policy

Timestamp changes use the attachment selected by the path or descriptor,
together with the inode's backend read-only state. The previous inode-only
check let the latest bind alias decide policy for other routes to that inode.
It could reject a writable source or permit a read-only source, including
descriptions retained after a detach or private namespace retirement.

`set_file_times` snapshots the starting directory and mount for pathname and
empty-path cwd operations. Path lookup uses the existing
`retain_path_target_on_mount` helper. Descriptor and empty-path fd operations
copy the saved mount from their pinned description. Existing FD/target cleanup,
MAC, ownership/write-access and immutable-attribute checks remain in place.
The attachment check precedes overlay copy-up, timestamp mutation and backend
persistence. No new reference owner, pin or heap allocation is introduced.
Anonymous resources retain their existing behavior.

The route-based guard corresponds to the mount-write requirement in
[Linux v6.12 timestamp operations](https://github.com/torvalds/linux/blob/v6.12/fs/utimes.c).
Linux's [inode clock](https://github.com/torvalds/linux/blob/v6.12/fs/inode.c)
can round current-time updates below a precise clock observation; the probe
allows one second below that observation while retaining a precise upper bound.
Explicit seconds/nanoseconds and denied updates are compared exactly.

Use `--case times` or `tp-0` through `tp-7`. Cases run in isolated child mount
namespaces using tmpfs and an eight-byte marker.

| Case | Routes exercised |
| --- | --- |
| 0 | Writable source/read-only directory bind, then reversed flags |
| 1 | Local descriptions after a namespace copy, both flag directions |
| 2 | Chroot root and cwd through different aliases, both directions |
| 3 | Regular-file bind and original pathname, both directions |
| 4 | Directory description through a read-only bind after lazy detach |
| 5 | Descriptions retained after a worker's private namespace retires |
| 6 | Read-only source/writable bind established before the first call |
| 7 | Empty pathname with `AT_EMPTY_PATH` and `AT_FDCWD`, both flag directions |

Each file-route pair runs 200 iterations of pathname `utimensat`, null-path
descriptor updates (`futimens` ABI), empty-path descriptor updates and the
`utime`, `utimes` and `futimesat` libc APIs. Directory binds also exercise
symlink no-follow `utimensat`. The libc calls cover the older syscall wrappers
on x86 and libc's `utimensat` translation on ARM. Retained legacy paths use
`/proc/self/fd`; chroot and file-bind paths use their original names.

The `utimensat` routes verify explicit values, null times, two `UTIME_NOW`
values and an explicit access time with `UTIME_OMIT` modification time.
Successful changes preserve mode, UID/GID, size and device/inode identity.
No-follow updates affect the symlink and preserve its target's timestamps;
ordinary updates preserve the symlink. Read-only operations must return `EROFS`
without changing access, modification or change times. Marker data stays intact.
UID/GID 1000 receives `EPERM` for explicit values through writable file routes
and `EACCES` for current-time updates to the mode-0600 file; read-only routes
return `EROFS`. Empty-path cwd checks compare explicit directory timestamps.

All twelve fixture V files, generated C, probe/kernel ELFs, image, serial log
and hash receipt are retained in fresh native state directories. The same
native probe ELF runs the portable suite on Linux 6.12.51. Frozen kernels
start from the qualified `mount-metadata` baseline with only the owned VFS
change, excluding other sessions' checkout edits.

Evidence from 2026-10-15 is under `build/development17-20261013`:

| States (both `arm` and `x86`) | Result |
| --- | --- |
| `mount-times-*-tp-{0,7}-before-b` | Previous kernel rejects writable source and empty-path cwd updates when their bind alias is read-only. |
| `mount-times-*-tp-{4,5,6}-before-b` | Previous kernel accepts updates through detached, retired and live read-only routes. |
| `mount-times-*-all-after-a` | Corrected kernel passes the full native suite and all eight timestamp cases. |
| `mount-times-*-linux-b` | Linux 6.12.51 passes the portable suite with the same probe ELF. |

| Architecture | Final kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `4587b5f0a81fd75087c199590fcb254957ca78fc4b34d54aed073f9a3eaaace1` | `4224257c475d450122b94d8dfe54418bbce70fb069ff546cf93aa1a0f7b7ef96` |
| x86_64 | `6f2f29cce37f6202a740e18286d81372c2733c1f528a78e0575f05daa7ba6baa` | `c545da7724ceaaad7abfb6b506940556724fa268b59b60890f6a6715ddcb2668` |

Each `mount-times-{arm,x86}-input` freezes the kernel ELF, generated C,
VFS/socket-lookup sources and complete source manifest. Builds use V source
`f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link shuffle seed 17. Native ARM uses HVF/four CPUs, x86 uses TCG/two CPUs;
Linux references have two CPUs. Networking is disabled. Full native timeout
is 300 seconds; Linux timeout is 180 seconds.

`mount-times-evidence-b.log` records the V audit of every receipt/artifact/source
hash. It checks the exact owned VFS delta against the frozen previous baseline,
all case markers and shared ELF identity. Generated C uses a stack mount context
and runs both
existing conditional FD cleanup and target cleanup on all 18 exits after
the target declaration. The cwd snapshot adds one possible failure exit,
with the same cleanup. Mount-policy/retention helper implementations are
unchanged. No new direct heap allocation or promotion appears in
`set_file_times`; per-architecture `times-c-audit.txt` records these checks.

Initial `linux-a` states preserve the probe's overly precise current-time
comparison failure. The final probe accounts for the coarse inode clock;
fresh `before-b` controls and `linux-b` references use that final ELF.

Both-`UTIME_OMIT` short-circuit semantics, invalid-times/flags error ordering,
concurrent remount or namespace/cwd switching, anonymous-resource timestamps,
overlay/disk persistence, allocation-flat loops and complete OCI/rootless
acceptance remain outside this qualification. Xattrs, inode flags and other
metadata operations still need attachment-policy coverage. Roadmap section 17
remains in progress.
