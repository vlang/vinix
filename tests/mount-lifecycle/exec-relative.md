# Directory-relative script execution

`execveat(dirfd, "script", ...)` now passes the interpreter a name rooted at
that directory descriptor: `/proc/self/fd/N/script`. Previously it passed
the literal `script`, so an interpreter reopening it from another cwd could
read a different file or fail. The original relative spelling, including
components such as `sub/../script`, is retained after the descriptor prefix.

The syscall pins one directory FD before lookup, validates its directory/node
and copies its mount context from that same FD. Errors and successful image
commit use the existing descriptor-release paths. A scalar records the
normalized descriptor number. Absolute paths and `AT_FDCWD` retain their own
pathname spelling and ignore unrelated descriptor flags.

Only a validated top-level script gets a new name. Its interpreter argv owns
a copy; the temporary name is freed immediately, and the original syscall
path retains its existing cleanup path. The scratch reservation includes the
additional name buffers. Nested interpreter scripts keep their own paths.
ELF and ARM translation paths retain their original pathname input.

A valid directory-relative script with `FD_CLOEXEC` returns `ENOENT` before
interpreter launch. Clearing that flag or duplicating without it allows
execution. Native ELF execution still closes the directory descriptor in the
new image. Existing mount, permission, MAC, W^X and lookup error checks remain.
This preserves the existing nonempty-path mount-policy model; divergent
inherited-directory mount flags remain a separate gap.

[Linux v6.12 executable naming](https://github.com/torvalds/linux/blob/v6.12/fs/exec.c)
uses `/dev/fd/N/script` for directory-relative requests, and its
[script loader](https://github.com/torvalds/linux/blob/v6.12/fs/binfmt_script.c)
refuses names made inaccessible by close-on-exec. The fixture accepts either
descriptor prefix while requiring the original directory number and suffix.

Use `--case execrel` or `er-0` through `er-7`. Native `all` and portable Linux
`move-reference` include the eight cases:

| Case | Checks |
| --- | --- |
| 0 | Read-only directory descriptor; cwd contains a different script with the same name. |
| 1 | `O_PATH` directory renamed after opening, as UID/GID 1000. |
| 2 | Literal `sub/../target` spelling and a nested script interpreter. |
| 3 | Close-on-exec refusal, flag clearing and independent duplicate flags, as UID/GID 1000. |
| 4 | Native ELF through a close-on-exec directory; the image verifies it closed. |
| 5 | Absolute paths with close-on-exec/invalid descriptors and relative `AT_FDCWD`, as UID/GID 1000. |
| 6 | Missing target, non-directory and invalid descriptors; final symlink follow/refusal. |
| 7 | `noexec` and unsupported-flag refusal with a close-on-exec directory, as UID/GID 1000. |

The matrix uses all four legal flag combinations and zero/nonzero upper
descriptor-register words. Successful images check real/effective IDs and
exit 43. Interpreters check the exact script name, reopen it and verify the
intended script contents; cwd contains a decoy. Target identity, ownership,
mode, size, links and mtime/ctime remain intact; reads may update atime.

Evidence from 2026-10-15 is retained under
`/Users/alex/.cache/vinix-linux-compat/execrel-20261015`:

| States | Result |
| --- | --- |
| `{arm,x86}-er-{0,3}-before-b` | Previous kernels launch interpreters with `target` instead of the directory-derived name, including a close-on-exec directory. |
| `{arm,x86}-execrel-after-b` | All eight corrected cases pass. |
| `{arm,x86}-{execcloexec,execfd,execflags,descexec,descwx}-after-b` | All five existing execution groups pass. |
| `{arm,x86}-linux-c` | Identical probe ELFs pass the complete portable Linux 6.12.51 suites, including all eight new cases. |

| Architecture | Fixed kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `785cd66117ce52b6b571074792995e44b5d59ba02684d0304836f31204a7f2b6` | `5be09b947ce7ed731afb7603d5a28c9fc6d91784bcc2d6ca2932c6fef022b435` |
| x86_64 | `2757ac3b00e96b8c4f54a46aaa68f1b86a5ee29517cc63b5c831c6e7748f4c04` | `883adddb11b953f283cc15dd5c328287eb508d509c0d9eca5e19b368d335c518` |

Both probe C files have SHA-256
`1148a01833b91b8459fe2c2ad8d069da6e0d25f40d53b9d75daf18d0c6c6bb2d`.
All retained successful native and Linux runs share the same thirty-four
fixture sources and probe/C artifacts. Receipts pin controllers, sources,
kernels and images, plus the Linux wrapper, initramfs, QEMU and serial log.
Every requested case marker and final verdict is checked.

Isolated worktrees start at committed baseline
`bc1b0274ee5dc8f017ba0fd1931b9d933a033903`. Only the retained five-file
`owned.patch` changes kernel sources. `before-{arm,x86}` and `after-{arm,x86}`
preserve tracked source manifests, the five changed files, generated C, kernels
and hashes. No baseline hunks are removed. Uncommitted checkout edits and
later concurrent commits are excluded. The entire current checkout kernel
and cumulative native `all` suites were not tested for this change.

Builds reuse the pinned host inputs documented in [descriptor ABI checks](exec-fd.md):
V source `f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`9e506a9fbd95e2e7c227cc144da023b57a288d0974ea902f1d12270e28bc416b`,
Clang with `-fstack-usage` and link seed 17. The final audit rechecks all
15,146 compiler inputs, 1,495 shared dependency files/symlink targets and the
retained musl-cross 0.9.11 SDK with GCC 14.2.0 support files. `sdk` and the
V Clang wrapper refer to that previous qualification area; the copied compiler,
SDK, dependency and tool manifests retain their pins. Shared dependencies
are not private source copies frozen before these builds. Host V generates
the x86 sampler from the baseline generator and builds probes/controllers.
These remain host inputs, not native Vinix toolchain qualification.

Native ARM uses HVF/four CPUs; x86 uses TCG/two, each with 1024 MiB.
Linux uses HVF/TCG, two CPUs and 512 MiB. Networking is disabled; runtime
invocations allow 600 seconds.

The assertion-enabled source/C audit compares every parsed namespace-qualified
function after normalizing compiler temporary/discard/loop-index numbers and
string-pool identifiers by their complete literal values. Only the syscall,
script loader, descriptor-release helper and one new naming helper differ.
The complete loader matches its reviewed budget, first-script guard and
clone-before-free edits after existing array-setter temporary normalization;
release differs only by clearing the scalar. The audit also checks directory
pin/context/cleanup and stack-builder invariants.

The separate read-only source and generated C review in `lifetime-review.txt`
found no unresolved lifetime, cleanup, authorization or ABI defect. Its initial
ARM translator finding was resolved before these kernel builds by restricting
synthesis to validated scripts. It verifies balanced directory pin releases,
stack Text placement, builder consumption, clone-before-free, original path
ownership, nested interpreters, commit ordering and the Thread scalar layout.
`source-evidence-a.log`, `after-{arm,x86}/c-audit.txt`, `evidence-a.log` and
`post-commit-a.log` retain the checks, including exact committed source identity
and preservation of unrelated staged changes.

The initial `-a` fixture failed C compilation because a conditional vararg
string needed an explicit character-pointer cast; it never reached the guest.
Fresh `-b` native probes include that correction. Their first Linux runs
reached the new script check but failed because the minimal reference guest
lacked `/dev/fd`. The reference init now creates `/dev/fd -> /proc/self/fd`
after mounting procfs. Fresh `-c` Linux states reuse the identical `-b` probe
ELFs and reopen the actual kernel-supplied name with that conventional link.
These earlier failures and their artifacts are retained; no kernel change
was made for either harness correction.

Concurrent close/reuse or flag mutation, namespace/remount races, divergent
inherited-directory policy, translated-image runtime qualification, arbitrary
failure injection, persistent/overlay integration and complete OCI/rootless
acceptance remain open. Roadmap section 17 remains in progress.
