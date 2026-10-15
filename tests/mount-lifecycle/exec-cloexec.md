# Empty-path script execution and close-on-exec

An empty-path `execveat` of a valid script now returns `ENOENT` when its
descriptor has `FD_CLOEXEC`. The interpreter needs the synthesized
`/proc/self/fd/N` name after execution; closing that descriptor would make
the script inaccessible. Previously Vinix started the interpreter anyway.
Native ELF images can still execute through close-on-exec descriptors, which
are closed before the new image runs. Clearing the flag makes scripts usable
again, and `dup` retains its independent descriptor flags.

[Linux v6.12 script loading](https://github.com/torvalds/linux/blob/v6.12/fs/binfmt_script.c)
checks script syntax before refusing an inaccessible descriptor-derived name
with `ENOENT`. The Vinix check likewise follows shebang parsing and the existing
mount, permission, MAC and W^X checks. Malformed shebangs retain `ENOEXEC`.

Both architecture loaders use the syscall's existing pinned descriptor. The
new failure branch frees the two strings owned by `parse_shebang`, before
constructing interpreter arguments or handing ownership to another loader.
The caller then frees its existing path/arguments/environment; the syscall
defer releases its descriptor and restores MAC state. No new allocation,
reference or shared lifetime is introduced. Ordinary pathname execution and
recursive interpreter loading do not apply this direct-description check.

`--case execcloexec` selects all eight cases; `ec-0` through `ec-7` select
individual cases. Native `all` and portable Linux `move-reference` include
them:

| Case | Checks |
| --- | --- |
| 0 | Linked read-only script opened with `O_CLOEXEC`, root. |
| 1 | Linked `O_PATH` script opened with `O_CLOEXEC`, UID/GID 1000. |
| 2 | Unlinked read-only script with `F_SETFD`, root. |
| 3 | Unlinked `O_PATH` script duplicated with `F_DUPFD_CLOEXEC`, UID/GID 1000. |
| 4 | Linked native ELF with close-on-exec, root; the image verifies its descriptor closed. |
| 5 | Unlinked `O_PATH` native ELF with close-on-exec, UID/GID 1000. |
| 6 | Clearing/restoring `FD_CLOEXEC` and executing a `dup` with independent flags. |
| 7 | `noexec`, unsupported flags, malformed shebang, denied execute permission and invalid descriptor errors as UID/GID 1000. |

Both supported empty-path flag combinations are tested. Successful images
verify real/effective IDs, their descriptor's open/closed state and exit 41.
Script interpreters also reopen their descriptor-derived script name. Failed
calls must return the exact error without changing descriptor flags; each
case preserves executable identity, ownership, mode, size, links and mtime/ctime.
Executable reads may update atime.

Evidence from 2026-10-15 is retained under
`/Users/alex/.cache/vinix-linux-compat/execcloexec-20261015`:

| States | Result |
| --- | --- |
| `{arm,x86}-ec-{0,3}-before-a` | Previous kernels start the interpreter for linked read-only and unlinked `O_PATH` scripts; the child marker and closed-descriptor failure prove the incorrect launch. |
| `{arm,x86}-execcloexec-after-a` | All eight corrected cases pass. |
| `{arm,x86}-{execfd,execflags,descexec,descwx}-after-a` | All four existing execution groups pass. |
| `{arm,x86}-linux-a` | Identical probe ELFs pass the complete portable Linux 6.12.51 mount suites, including all eight new cases. |

| Architecture | Fixed kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `9bcd13b3c8c9677ad2062b7966d471e349af6b0efb7a2c3d753fb7aeb3edd248` | `c0f3b3eedf46b5ae5181b0baa5a77f1f191eddac8c8048962455ebfb3f11ffaa` |
| x86_64 | `ce977edd537a7d763e77f74a0e5c51043a1a8337ea7e97a0cb420a0a9a0dabd3` | `4cba12fb1ceb8d96b15ee60c68dc503e7c5cae5f32e4a0a618372c386d3febd0` |

Both probe C files have SHA-256
`2013d8e610117a0bb47faf5097bbe7f4146e3a08712acef1a8420bce78a37aed`. All native states share the same thirty-three fixture
sources and probe/C artifacts; Linux reuses the identical probe ELFs. Receipts
pin controllers, sources, kernels and images, and the Linux wrapper, initramfs,
QEMU and serial log. Every requested case marker and final verdict is checked.

Isolated worktrees start at committed baseline
`22f1f2effa7d2610202d59daa59254c06e4b6e2d`. Only the retained three-file
`owned.patch` changes kernel sources. `before-{arm,x86}` and `after-{arm,x86}`
preserve source manifests, the three changed files, generated C, kernels and
hashes. No baseline source hunks are removed. Uncommitted checkout edits and
later concurrent commits are excluded; the entire current checkout kernel
and cumulative native `all` suites were not tested for this change.

Builds reuse the pinned host inputs documented in [descriptor ABI checks](exec-fd.md):
V source `f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`9e506a9fbd95e2e7c227cc144da023b57a288d0974ea902f1d12270e28bc416b`,
Clang with `-fstack-usage` and link seed 17. The final audit rechecks all
15,146 compiler inputs, 1,495 shared dependency files/symlink targets and the
retained musl-cross 0.9.11 SDK with GCC 14.2.0 support files. `sdk` and the
V Clang wrapper refer to the previous qualification area. `tool-inputs.json`,
`compiler-inputs.json`, `dependency-inputs.json`, `sdk-inputs.json` and
`compiler-recovery.json` retain their pins/provenance. Shared dependencies
are not private source copies frozen before these builds. Host V generates
the x86 sampler from the baseline generator and builds the probes/controllers.
These remain host inputs, not native Vinix toolchain qualification.

Native ARM uses HVF/four CPUs; x86 uses TCG/two, each with 1024 MiB.
Linux uses HVF/TCG, two CPUs and 512 MiB. Networking is disabled; each
runtime invocation allows 600 seconds.

The assertion-enabled source/C audit compares every parsed namespace-qualified
function. Only the scalar descriptor-flag helper and the exact post-parse
`ENOENT` branch differ after compiler temporary/discard/loop-index normalization.
For the loader comparison it also normalizes the three existing array-setter
pointer/index temporary numbers. The helper allocates nothing; the branch
frees only the two owned parser strings and unwinds the existing exec-depth
defer. Argument cleanup, descriptor release, authorization, ELF loading and
process commit bodies remain unchanged. The initial audit stopped at those
renumbered array-setter temporaries; the corrected audit changes no kernel
or probe artifacts.

`source-evidence-a.log` retains the initial comparison failure and
`source-evidence-b.log` the helper regex error. `source-evidence-c.log`,
`after-{arm,x86}/c-audit.txt` and `evidence-a.log` retain the passing source
and runtime checks. `post-commit-a.log` verifies all eleven committed paths,
the exact three-file kernel patch, identity with tested sources and
preservation of unrelated staged edits.

Relative pathname scripts through close-on-exec directory descriptors,
concurrent descriptor close/reuse or `F_SETFD`, namespace/remount races,
dynamic/translated images, full OCI/rootless acceptance and the remaining
roadmap section 17 gates remain open.
