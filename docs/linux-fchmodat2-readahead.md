# fchmodat2(2) and readahead(2)

Both were vacant and returned ENOSYS on both architectures. glibc 2.39 and
later implement `lchmod` and `fchmodat(..., AT_SYMLINK_NOFOLLOW)` with
fchmodat2; readahead is the prefetch call of databases, boot-time readers and
`readahead`-style tools. `fs.syscall_fchmodat2` (452 on both architectures)
and `file.syscall_readahead` (213 on AArch64, 187 on x86-64) implement them.

## fchmodat2

Established with an exploratory probe on Linux 6.12.51 and checked by the
final probe:

- Only `AT_SYMLINK_NOFOLLOW` and `AT_EMPTY_PATH` are accepted; any other flag
  is EINVAL, before the path is looked up.
- Linux never changes a symbolic link's mode: naming one without following
  it, dangling or not, is EOPNOTSUPP, as is `AT_EMPTY_PATH` on an O_PATH
  descriptor of a link. This comes after the read-only and immutable checks
  and before ownership, the order of Linux's `notify_change`, so an
  unprivileged caller gets EOPNOTSUPP for root's link and EPERM for root's
  file.
- `AT_EMPTY_PATH` with an empty path changes the descriptor's own file,
  O_PATH descriptors included, and the working directory at `AT_FDCWD`. An
  empty path without the flag is ENOENT; a NULL path is EFAULT.
- `mode` is a 16-bit `umode_t` of which the permission bits count; `dirfd`
  and `flags` are C ints. Everything else matches fchmodat: EBADF, ENOTDIR,
  ENOENT, following links without the flag, and the type bits kept.

## readahead

- The descriptor must be open for reading: write-only and O_PATH
  descriptors, including a pipe's write end, are EBADF.
- Then only regular files and block devices are accepted; directories,
  pipes, sockets and character devices are EINVAL.
- Then a count beyond the signed 64-bit range is EINVAL. Any offset is
  accepted; a negative one names no page to read. A count of 0 and ranges
  past the end succeed.
- The request is passed to the file's advice hook as `POSIX_FADV_WILLNEED`,
  as Linux's `ksys_readahead` does with `vfs_fadvise`.

## Qualification

`tests/linux-compat/run --cases fchmodat2,readahead` boots each fixture as
init; `syscall-reference.v --case fchmodat2` and `--case readahead` boot the
same ELFs on Linux 6.12.51.

Source revision: the commit that adds this file. Kernels: `PROD=true`,
`LIMINE_MP=1` (AArch64 `30ff22a1a4256572`, x86-64 `2081de4d7b60a523`).

| Run | fchmodat2 | Probe ELF | Serial log | readahead | Probe ELF | Serial log |
| --- | --- | --- | --- | --- | --- | --- |
| Vinix AArch64 | 33 + 3 checks | `3c4ef668a4964aeb` | `1e5ffcb1b1b0d817` | 22 checks | `23e420dfcb6476f1` | `691f63e32f1804d1` |
| Linux AArch64 6.12.51 | 33 + 3 checks | `3c4ef668a4964aeb` | `f474d056019bf80d` | 22 checks | `23e420dfcb6476f1` | `574f4fef90f1414a` |
| Vinix x86-64 | 33 + 3 checks | `c9e5ea5b8a969d82` | `1f148026759988b4` | 22 checks | `2451fece2bd198d1` | `8d44792bbdd392fd` |
| Linux x86-64 6.12.51 | 33 + 3 checks | `c9e5ea5b8a969d82` | `b3699d5e07147ba0` | 22 checks | `2451fece2bd198d1` | `4b143992867e4848` |

Every run has 0 failures. Hashes are SHA-256 prefixes. Bundles are kept
outside Git in `~/.cache/vinix-r15/runs/chmod-{arm,x86}-1` and
`{fchmodat2,readahead}-{arm,x86}-linux-1`; the exploratory Linux log is
`~/.cache/vinix-r15/explore/chmodx-arm-1` (`ac2e9a48cf650bd6`).

## Limits

- What readahead prefetches depends on each filesystem's advice hook; tmpfs
  has nothing to read ahead.
- `AT_EMPTY_PATH` at `AT_FDCWD` is handled here; the older fchownat path
  still reports EBADF for it.
