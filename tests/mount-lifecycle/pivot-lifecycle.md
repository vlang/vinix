# Pivot publication and old-root teardown

`pivot_root` moves the existing old and new mount records. The old root keeps
its stable identity and flags while becoming a child of the mount containing
`put_old`; the new root takes the old root's former parent attachment. Both
move epochs advance, so held descriptors and cwd can rebase their saved parent
routes. The new root's old pathname becomes the underlying directory again.
The operation checks the proposed parent graph, including every active
attachment's 64-step cursor capacity, before publishing either move under the
existing VFS writer lock. These helpers add no allocations or ownership changes.

Lazy unmount follows the current mount parent IDs to detach the selected subtree.
It includes children even after their parent record has been marked detached.
It preserves the new root and its mounts after a pivot, including when a bind
root still shares inode ancestry with the old filesystem. Held descriptions keep
their data and read-only policy; detached identities cannot authorize new mounts.
This mirrors the mount-object reattachment and subtree removal model in the
[Linux 6.12.51 namespace implementation](https://github.com/gregkh/linux/blob/v6.12.51/fs/namespace.c).

Run the maintained controller with `--case pivot-life`, or select `pl-0` through
`pl-3`. Every case forks a private mount namespace, mounts an independent tmpfs
caller root, and creates a read-only old-root child before pivoting. The parent
checks that its root identity is unchanged when the child exits.

| Case | Regression and positive checks |
| --- | --- |
| `pl-0` | Held old-root descriptors observe writable/read-only remount changes at the new attachment. A second pivot preserves the original old root's identity, policy and new parent. Lazy removal of both former roots leaves the latest root usable. |
| `pl-1` | A nested tmpfs containing `put_old` becomes the old root's actual parent; `fchdir` through its previously held descriptor resolves `..` there. |
| `pl-2` | A directory bind root leaves its original mountpoint. Looking up that pathname through a held old-root descriptor returns the underlying directory's original device/inode. |
| `pl-3` | Lazy removal of the old root leaves the new root active: a fresh tmpfs mount and ordinary unmount succeed inside it. |

The first three cases check all held-descriptor policy, parent and extracted
source properties. All four verify UID/GID 1000 receives `EPERM` for old-root
detachment. After privileged lazy removal, they repeat 200 times for each of the
old root and its separately mounted child: ordinary descriptor-based lookup and
marker reads still work, creation/writable access remain read-only, and new
mounts through `/proc/self/fd` return `ENOENT`. Each case finishes with
`MOUNT PIVOT LIFE CASE: N PASS`; the group requires
`MOUNT PIVOT LIFECYCLE: PASS` as well as the suite's final verdict.

Qualification from 2026-10-14 is preserved under `build/development17-20261013`:

| States (both `arm` and `x86`) | Result |
| --- | --- |
| `mount-pivotlife-*-pl-0-before-a` | Previous kernels leave the held old-root fd read-only after remounting its new attachment writable (`EROFS`). |
| `mount-pivotlife-*-pl-1-before-b` | Previous kernels leave the held old-root descriptor's parent route stale. |
| `mount-pivotlife-*-pl-2-before-b` | Previous kernels keep the new root mounted at its former pathname. |
| `mount-pivotlife-*-pl-3-before-b` | Previous kernels lose the new root during lazy removal; a mount inside it fails with `ENOENT`. |
| `mount-pivotlife-*-all-after-a` | Patched kernels pass the complete maintained native mount suite, including all four lifecycle cases. |
| `mount-pivotlife-*-linux-a` | Linux 6.12.51 passes every portable group, including the four new cases, using the identical native probe ELF. |

The `build-a` attempts and ARM `pl-1-before-a` state were interrupted by host
disk exhaustion; they are retained but are not qualification. The resumed
`build-b` builds and fresh `before-b` controls completed successfully. Cleanup
removed only completed private tests' unpinned firmware copies and recorded
their hashes in `mount-pivotlife-firmware-pruned-a.json`; pinned evidence remains.

| Architecture | Final kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `8aa5b58043d284426e140d19dd17fcd5ad0cfe05425ea7345c04b4e0bfa639d6` | `232993974ea7644cd15aa21da250a036ff657a83124f50535383de1aa67e39d3` |
| x86_64 | `5e5fcb6b9bc240791279e0bba19e63919f7367339abd68b58b7ae4c3629090da` | `805b2a0b7368d6daba5c6dabedc11cae5384cbf45f172e2b423e609f862de17f` |

The isolated worktrees reuse the frozen `mount-pivot2` baseline, replacing only
`kernel/fs/mount.v`. They exclude other sessions' checkout edits and retain the
VFS baseline limitation described in [identities.md](identities.md). Each
`mount-pivotlife-{arm,x86}-input` retains its ELF, generated C, mount source and
complete source manifest. Builds use V source
`f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link shuffle seed 17. Controls and final native runs share each first
`pl-0-before-a` probe. The controller pins all six fixture files and requires
identical source/artifact hashes before reusing the ELF/C. ARM uses HVF, x86 uses
TCG, and neither native nor reference guests have network devices.

`mount-pivotlife-evidence.log` verifies every receipt and pinned artifact, all
positive markers, the four previous-kernel failures, shared ELF identity and
unchanged baseline sources. Generated C checks verify preparation precedes
publication, no duplicate mount record is created, both epochs advance, and
parent-graph/preparation/publication/subtree helpers allocate no temporary
objects. Complete mount operations are not claimed allocation-flat: existing
mount records and filesystem caches remain permanently owned.

This qualifies conventional distinct-directory pivots from a mounted caller
root, their retained descriptors, a second pivot and lazy old-root removal.
Runtime cursor-depth boundary tests, namespace-root self mounts, same-directory
pivot stacking, mount-aware reporting through other bind aliases, other
processes' root/cwd alias updates, concurrent publication/namespace switching,
busy-reference accounting and reclamation remain open. Propagation semantics,
full OCI/rootless acceptance and the rest of roadmap section 17 remain open.

The subsequent [pivot alias checks](pivot-aliases.md) qualify root/cwd updates
for separate process aliases and the caller's private `CLONE_FS` state.
