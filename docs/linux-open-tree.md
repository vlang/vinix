# Native open_tree path references

`open_tree` opens an existing path as an `O_PATH` descriptor. A relative path
uses the attachment of the supplied directory descriptor. An empty path with
`AT_EMPTY_PATH` uses the descriptor or current directory directly. The
resulting descriptor retains the selected inode and mount ID even after
unlink or lazy detach. `OPEN_TREE_CLOEXEC` sets the descriptor flag, and
`AT_SYMLINK_NOFOLLOW` keeps a final symbolic link unless a trailing slash
requires directory traversal.

The syscall validates flags and reserves a descriptor number before importing
the path. A path fault releases the reservation. Metadata-only references
to pipe ends and PTY slaves preserve the original endpoints and their readiness.
[Linux 6.12.51 implementation](https://github.com/gregkh/linux/blob/v6.12.51/fs/namespace.c#L2717)

`OPEN_TREE_CLONE` returns `EPERM` without mount-namespace capability and
`EOPNOTSUPP` when permitted. Detached tree creation and fd-based attachment
remain open. Anonymous pipes work with `AT_EMPTY_PATH` and a followed procfs
descriptor link. Other anonymous resources without a vnode return
`EOPNOTSUPP`. `AT_NO_AUTOMOUNT` is accepted within Vinix's current VFS
model, which has no automount triggers.

## Qualification

One unchanged probe executable per architecture passed on Vinix and Linux
6.12.51. It checks bind mount identity, descriptor flags, empty-path lookup
after unlink and lazy detach, symlink handling, search permissions, and
descriptor exhaustion and reuse. The pipe and PTY cases verify that closing
a pathname reference leaves the live endpoints usable. The baseline Vinix
kernels returned `ENOSYS`.

Production builds used `c6c7e9ca7` plus the archived source patch. Independent
review covered descriptor and mount admission, vnode and resource pins,
and endpoint close accounting. The allocation checker reported the same
existing findings and the same 306 AArch64 and 254 x86-64 sites as the baseline.
The `open`, `namespace`, `statmount`, `pipeabi` and `pipeready` regressions
passed on both architectures. Pipe readiness passed 24,180 AArch64 and
30,960 x86-64 checks, with flat page counts in both 200-cycle cohorts per
architecture.

| Architecture | Probe ELF | Vinix kernel | Vinix serial log | Linux serial log |
| --- | --- | --- | --- | --- |
| AArch64 | `919ea97be9d52c7c` | `99eb859759fa5b5b` | `4fd9fc08788bf127` | `a31ded9f2efc2305` |
| x86-64 | `e4c99fd4d6d205ea` | `377afa9842a245cf` | `5fd0ebd47b615e4b` | `dcfb049648ee8e0b` |

Hashes are SHA-256 prefixes. The restored and verified archive is
`~/.cache/vinix-r15/opentree/qualification.tar.zst`, with SHA-256
`95e9c573bee722da8b79003166a9a7a4cf22e427b46c7127900718d37bd7dba6`.
Decode it with `zstd --long=28 -dc` before extracting the tar stream.
