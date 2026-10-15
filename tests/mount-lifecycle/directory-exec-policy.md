# Inherited directory executable policy

Relative `execveat(dirfd, "target", ...)` checks `noexec` and `wxallowed` on
the final resolved attachment itself. An inherited executable directory
remains usable after its namespace copy gains `noexec`; an inherited
`noexec` directory gains no execution authority when the copy loses that
flag. W^X approval follows the same rule. Previously the loaders remapped
the attachment by namespace ID, so a remount of the copy could incorrectly
deny execution or grant it through the original directory.

Both loaders select the existing raw mount-policy reader for the first load
when the syscall holds an image or directory description. The selector is
one local boolean. It does not change allocation, ownership, references,
argument cleanup, descriptor release, Thread layout or interpreter/translator
inputs. Empty-path script naming remains distinct from directory-relative
script naming.

Policy follows the resolved attachment rather than blindly reading the
directory FD's flags. A relative symlink retains its route; an absolute
symlink resets lookup to the caller's root and observes that namespace's
mount. A script's interpreter is checked separately through its pathname.
Explicit `VINIX_ALLOW_WX=1`, ordinary inode permissions, MAC, pledge/unveil,
the privileged W^X override and default W^X retain their checks.

[Linux v6.12 path initialization](https://github.com/torvalds/linux/blob/v6.12/fs/namei.c)
starts a relative descriptor lookup from the file's saved path.
Its [executable opener](https://github.com/torvalds/linux/blob/v6.12/fs/exec.c)
checks `noexec` on the opened file's resulting path. `wxallowed` remains
Vinix-specific and is excluded from the Linux reference suite.

Use `--case descexec` (`de-0` through `de-9`) and native `--case descwx`
(`dw-0` through `dw-9`). Each group retains its previous eight cases and
adds two native ELF cases. Cases 6/7 now also cover inherited directories
for scripts. Cases 8/9 use UID/GID 1000 owners, with opposite original/copy
flags in each direction.

The fixture duplicates ordinary read-only and `O_PATH` directory descriptions
and closes the original descriptors before copying the namespace. Repeated
fork/execs exercise the retained directories, fresh directory/image FDs,
absolute requests and ordinary `execve`. Relative `target` and symlink names
retain saved policy; absolute symlink targets follow the copy. The `noexec`
group also checks `sub/../target` and uses `fstatfs` to establish both retained
directory policies. Successful images verify real/effective IDs and exit 37.
W^X images exercise actual RWX `mmap`/`mprotect`, including after fork, before
exiting 38. Request-free execution retains default W^X, and removing the
interpreter's approval still refuses the script. A `noexec` interpreter is
also refused. Target identity, mode, ownership, size, links and mtime/ctime
remain unchanged; reads may update atime.

Evidence from 2026-10-15 is retained under
`/Users/alex/.cache/vinix-linux-compat/dirroute-20261015`:

| States | Result |
| --- | --- |
| `{arm,x86}-de-8-before-b` | Original executable directories wrongly return `EACCES` after the copy gains `noexec`. |
| `{arm,x86}-de-9-before-b` | Original `noexec` directories wrongly launch ELF images, reaching status 37 after the copy becomes executable. |
| `{arm,x86}-dw-8-before-b` | Approved original directories wrongly return `EPERM` after copied approval is removed. |
| `{arm,x86}-dw-9-before-b` | Unapproved original directories wrongly grant RWX and reach status 38 after copied approval is added. |
| `{arm,x86}-all-after-b` | Complete native mount suites pass, including both extended ten-case execution groups. |
| `{arm,x86}-linux-b` | Identical probe ELFs pass the complete portable Linux 6.12.51 suites, including ten noexec execution cases. |

| Architecture | Fixed kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `3229da26eaf90113501d57d7dcde80d20ec8c7c5652f215859e20311bf414a50` | `b6eae8069856834b61f9f544bab8ccc6aa386e7a12c7e440d1ce3cdcbeda61b8` |
| x86_64 | `7f5319652b7a0ce4d472aec469cdbcafe41afca4d895fc4eb91b59cd668f1ec4` | `bb45189c78ca7758953807477fce6347777e94411ac1780f19069029e9b614a2` |

Both probe C files have SHA-256
`6b9b6f31cd6ddf06d45e5d7b626a4a35de861023a5233ffe5cf6fe8fde35f38c`.
All successful runs and the four before-controls per architecture share the
same thirty-four fixture sources and probe/C artifacts. Receipts pin the
controllers, sources, kernels, images, Linux wrapper/initramfs, QEMU and logs.
The final audit checks each case marker and final verdict.

Isolated worktrees start at committed baseline
`31a63051241fb3140f0c6403b5733994583852aa`. Only the retained two-file
`owned.patch` changes kernel sources. Tracked source manifests, both loader
files, generated C, kernel artifacts and hashes are saved in
`before-{arm,x86}` and `after-{arm,x86}`. No baseline hunks are excluded.
Concurrent uncommitted checkout changes and subsequent commits are excluded
from these builds; the full dirty checkout kernel was not tested.

Builds reuse the host inputs documented in [the relative script qualification](exec-relative.md):
V source `f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`9e506a9fbd95e2e7c227cc144da023b57a288d0974ea902f1d12270e28bc416b`,
Clang with `-fstack-usage` and link seed 17. The final audit rechecks all
15,146 compiler inputs, 1,495 shared dependency files/symlink targets, tools
and retained musl-cross 0.9.11 SDK with GCC 14.2.0 support files. `sdk` and
the V Clang wrapper refer to the previous qualification area; copied input
manifests retain their pins. Shared dependencies are not private copies
frozen before these builds. Host V generates the x86 sampler from the
baseline generator and builds probes/controllers. These are host inputs,
not native Vinix toolchain qualification.

Native ARM uses HVF/four CPUs and x86 TCG/two, each with 1024 MiB. Linux
uses HVF/TCG, two CPUs and 512 MiB. Networking is disabled and runtime
invocations allow 600 seconds.

The assertion-enabled source/C audit compares all parsed namespace-qualified
functions after normalizing compiler temporary/discard/loop-index numbers and
string-pool IDs by complete literal values. Only `load_program_image` differs.
Its complete body matches the one added scalar and its use at the existing
noexec/W^X sites. Reference, allocation, free, cleanup and ABI declarations
retain their bodies. `source-evidence-a.log`, `after-{arm,x86}/c-audit.txt`,
`evidence-a.log` and `post-commit-a.log` retain the checks, including exact
committed source identity and preservation of unrelated staged changes.

The initial `-a` probe failed C compilation because the fixed array of
C strings needed explicit character-pointer elements; it never reached the
guest. Fresh `-b` states include that fixture correction and retain the same
kernels. Initial driver logs also retain rejected attempts to save an already
saved kernel snapshot. Final `drive-{arm,x86}-c` runs use those verified
snapshots and complete all controls and suites. Earlier artifacts are retained.

Cross-mount `..` and child-mount discovery through inherited directories,
concurrent close/reuse/remount/setns, dynamic ELF interpreters, translated-image
runtime qualification, credential transitions, persistent/overlay integration,
allocation-flatness and desktop performance remain outside this qualification.
No general path-walker policy model is changed. Full OCI/rootless acceptance
and roadmap section 17 remain in progress.
