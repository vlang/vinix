# Bind attachment creation and open policy

`--case bind-policy` runs five independent children with private mount
namespaces. `bp-0` through `bp-4` select one child. Each fixture starts with a
writable tmpfs source and a read-only bind of the same inode. Read-only state
must describe the attachment used by the path, rather than whichever mount
record was most recently added for that inode.

| Case | Routes exercised |
| --- | --- |
| 0 | Directory binds and held source/alias directory descriptions |
| 1 | Local descriptions opened after copying the mount namespace |
| 2 | Writable chroot root and read-only cwd naming the same directory |
| 3 | A regular-file bind and its original tmpfs pathname |
| 4 | A sibling thread's private copied namespace and the shared process view |

Both policy directions are checked: writable source/read-only bind, then
read-only source/writable bind. Directory cases create a regular file and a
directory through the writable attachment. In 200 repetitions per direction,
they check `O_WRONLY`, `O_RDWR`, `O_RDONLY | O_TRUNC`, read-back data and refusal
of `O_CREAT`/`mkdirat` through the read-only attachment. Refused creations must
leave both names absent. Successful truncation is followed by restoring the
marker before another route reads it. The file-bind case repeats the open,
truncation and data checks without directory creation.

The private-thread case changes policy only in its copied namespace, using
local descriptions opened after the copy. After joining the worker,
the caller checks the original policy. There is no simultaneous namespace
switch or remount; synchronization uses `pthread_join`.

Creation and writable opens preserve the path walk's mount context, including
retained descriptions. `mkdirat` now snapshots its directory and mount context
together before resolution. A route-aware check combines that attachment's
flags with the inode's backend read-only state. Internal creators that supply
only an inode retain the existing conservative inode-based check. This change
adds no ownership transfer or heap allocation; existing permissions, policy checks,
MAC checks, attributes, budgets and ACL handling remain on the same paths.

Native ARM and x86 qualification builds use the previously qualified isolated
kernel baseline plus the VFS/mount-policy changes. This excludes concurrent
sessions' unrelated edits. Each architecture's exact probe ELF is reused for
the previous-kernel controls, corrected full mount suite and Linux 6.12.51
reference. The previous kernels fail case 0 with `EROFS` at the writable file
creation. Fresh result directories retain all nine fixture sources, generated
C, kernels, probe ELFs, images, logs and hash receipts. The existing identity
suite also checks refusal through detached and retired read-only descriptions.
The subsequent [pathname truncation checks](truncate-policy.md) qualify
`truncate(path, length)` against the same attachment policy, including retained
descriptions, before any size change or overlay copy-up.

Evidence from 2026-10-14 is under `build/development17-20261013`:

| States (both `arm` and `x86`) | Result |
| --- | --- |
| `mount-bindpolicy-*-bp-0-before-c` | Previous kernel returns `EROFS` creating through the writable source. |
| `mount-bindpolicy-*-all-after-b` | Corrected kernel passes the full native mount suite and all five policy cases. |
| `mount-bindpolicy-*-linux-b` | Linux 6.12.51 passes the portable suite using the exact same probe ELF. |

| Architecture | Final kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `a103f09fe5029c2b94babea8a961c07d0e658469a1ee587950f486b861a591dc` | `9ce0944c1d6b67135a3bdd1b9046a74ab9034605ced8aa6d3ce5fa3db7959f8e` |
| x86_64 | `10f93013a8b17c5a98e77644e210e3f0605f5798a3ced20b5feb6ed4d858c2d1` | `22283594b9da27f140a793768e6f9028df02368b708591c4941c4a4cedd49546` |

Each `mount-bindpolicy-{arm,x86}-input` freezes the kernel ELF, generated C,
VFS/mount-policy sources and complete source manifest. Builds use the frozen
`mount-pivotthreads` baseline, pinned V source
`f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link shuffle seed 17. Native ARM uses HVF/four CPUs, x86 uses TCG/two CPUs;
Linux references have two CPUs. Networking is disabled. Native timeout is
300 seconds; Linux timeout is 180 seconds. The evidence audit checks all source
and artifact pins, the identical owned VFS delta against the prior baseline,
all case markers, shared ELF identity and generated policy/authorization order.

`before-a` retains the initial guest declaration mismatch for `mkdirat`;
the probe uses its syscall ABI. `before-b` and `all-after-a` retain the initial
fixture with descriptors inherited across a namespace copy. `linux-a` records
Linux's refusal to remount through those foreign descriptions. Final copied
namespace cases open local descriptions before changing policy. The final
`before-c`, `all-after-b` and `linux-b` qualify the current nine-file fixture.

This qualifies creation and writable/truncating opens. Metadata, symlink/link,
rename, unlink, descriptor truncation, concurrent remount/namespace switching,
mount reclamation, inherited foreign-description policy after a namespace
copy and full OCI/rootless runtime acceptance remain open. The
five cases do not measure allocation growth or qualify read-only disk backends.
