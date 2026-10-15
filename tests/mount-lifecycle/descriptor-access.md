# Inherited descriptor access queries

`faccessat2` with an empty path and `AT_EMPTY_PATH` now uses the actual saved
mount of its descriptor for read-only and `noexec` queries. A namespace copy
with opposite flags cannot change that description's result. Fresh descriptors
and pathname queries continue to follow the copied namespace.

The syscall still pins its descriptor through synchronous checks and releases
it on return. The existing permission helper selects the descriptor policy
readers only for an empty-path file descriptor. Cwd and pathname calls retain
the namespace readers. Policy checks, real/effective credential selection,
regular-file `noexec`, inode permission checks, special-file exceptions and
read-only error ordering remain in place. The anonymous-descriptor branch is
unchanged. No allocation, owner, reference transition or free is added.

[Linux v6.12 `do_faccessat`](https://github.com/torvalds/linux/blob/v6.12/fs/open.c)
checks the resolved file path's mount for `noexec` and read-only flags. These
are advisory queries; a successful query does not authorize a later operation.

Use `--case descaccess` or `da-0` through `da-7`. Native `all` and Linux
`move-reference` include the group:

| Case | Saved mount and target | Copied mount |
| --- | --- | --- |
| 0 | Writable regular file | Read-only |
| 1 | Read-only regular file | Writable |
| 2 | Executable regular file | `noexec` |
| 3 | `noexec` regular file | Executable |
| 4 | Writable/executable unlinked file | Read-only/`noexec` |
| 5 | Read-only/`noexec` unlinked file | Writable/executable |
| 6 | Writable directory | Read-only/`noexec` |
| 7 | Read-only/`noexec` directory | Writable/executable |

Each case duplicates both an ordinary read-only descriptor and an `O_PATH`
descriptor, closes their original descriptors, copies the namespace and
remounts the copy. Statfs establishes the actual and copied mount flags.
Sixteen cycles cover all eight permission combinations and all combinations
of `AT_EACCESS` and `AT_SYMLINK_NOFOLLOW`, together with `AT_EMPTY_PATH`.
Fresh ordinary/`O_PATH` descriptors and pathname queries follow the copy for
linked targets. A forked UID/GID 1000 owner repeats the complete matrix.
Directory search remains available on `noexec`. Combined regular-file queries
retain `EACCES` before `EROFS`. Metadata and timestamps remain unchanged;
regular data and unlinked link counts are checked.

Evidence from 2026-10-15 is retained under `build/development17-20261013`:

| States | Result |
| --- | --- |
| `mount-descaccess-{arm,x86}-da-0-before-a` | Previous kernels wrongly return `EROFS` through inherited writable descriptions when the namespace copy becomes read-only. |
| `mount-descaccess-{arm,x86}-da-1-before-a` | Previous kernels wrongly permit write queries through inherited read-only descriptions when the copy becomes writable. |
| `mount-descaccess-{arm,x86}-da-2-before-a` | Previous kernels wrongly return `EACCES` through inherited executable descriptions when the copy gains `noexec`. |
| `mount-descaccess-{arm,x86}-da-3-before-a` | Previous kernels wrongly permit execute queries through inherited `noexec` descriptions when the copy becomes executable. |
| `mount-descaccess-{arm,x86}-descaccess-after-a` | All eight corrected native cases pass. |
| `mount-descaccess-{arm,x86}-all-after-a` | The complete native mount suites pass. |
| `mount-descaccess-{arm,x86}-linux-a` | The same probe executables pass the portable Linux 6.12.51 suites, including all eight access cases. |

| Architecture | Kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `0b44ecd5b64b1d3ad9cf0576a8e9c8f36771d1c7cb235ef121d38e7d4718b97b` | `674a0bc1f4ca91b723c727fa893370eeb7f49fba617dec845d3a9b6f85f28d3f` |
| x86_64 | `4ced22e20e348e392a85aaa29cfce26bb3ca48c5da4b8dcdb4c1c646ad7e5078` | `d85001263d093fd924720995fa3e4bdb1609c275da11b40e3b387eab228548ac` |

`mount-descaccess-{arm,x86}-input` preserves complete source manifests,
source snapshots, generated C, kernels and hashes. Builds use V source
`f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link seed 17. Native ARM uses HVF/four CPUs; x86 uses TCG/two, with
1024 MiB. Linux uses HVF/TCG, two CPUs and 512 MiB. Controls and Linux runs
allow 600 seconds; focused and cumulative native runs allow 900 seconds.
Networking is disabled. Controls and corrected native runs share the same
twenty-eight fixture sources and probe/C artifacts. Linux reuses the identical
probe executables. Both architectures' probe C has SHA-256
`3b103da1b1835fa28170c9f87b0cde9d8552413ef9192ce9a0ff7f4cf17172a3`.

The isolated inputs extend the qualified [descriptor-mapping builds](descriptor-mmap.md),
changing only the access syscall and helper in `kernel/fs/vfs.v`. The baseline
still excludes the pre-existing open-created descriptor hunks, staged
pointer-return spelling edits and earlier fcntl/descriptor/lock changes
described in [the writer qualification](writer-policy.md). Later checkout
changes are excluded. The complete current checkout kernel was not built or
booted.

The assertion-enabled source/C audit compares all parsed namespace-qualified
functions after temporary/discard/loop-index normalization. Only the access
syscall and helper differ. The complete syscall matches after its three helper
calls select descriptor policy for the pinned empty-path FD and namespace
policy for cwd/path calls. The helper matches after removing its selector and
replacing the two checked stack-valued policy-reader selections with the
original readers. Short-circuit conditions and all authorization, credential,
special-file and error-order checks remain. Every other parsed function,
including both policy readers, is unchanged. Receipt checks pin all twenty-eight
fixture sources, controllers, artifacts, controls, shared native/Linux probe/C
identity and positive markers. A private index separates the VFS commit from
another session's staged edits. The post-commit audit accounts for the same
three excluded open-created VFS hunks in both tested snapshots.
Per-architecture `descriptor-access-c-audit.txt`,
`mount-descaccess-source-evidence-a.log`, `mount-descaccess-evidence-a.log`
and `mount-descaccess-post-commit-a.log` retain the results.

Concurrent remount/setns, combined DAC/ACL/MAC denial cases, empty-path symlink
and anonymous resources, persistent/overlay integration, allocation-flatness,
mount reclamation and desktop performance remain outside this qualification.
Full OCI/rootless acceptance and roadmap section 17 remain in progress.
