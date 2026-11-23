# Executable memfd creation

`memfd_create` accepts `MFD_EXEC` alongside `MFD_CLOEXEC` and
`MFD_ALLOW_SEALING`. Explicit executable creation uses the same anonymous
tmpfs inode mode as the default, `0777` independent of umask. The descriptor
is read/write and publishes its close-on-exec bit and its initial seals with
the file. [Linux 6.12.51 creation path](https://github.com/gregkh/linux/blob/v6.12.51/mm/memfd.c#L311)

The kernel copies the complete NUL-terminated name before reserving a
descriptor. The name can contain up to 249 bytes. A fault in the copied
name returns `EFAULT`, and an overlong name returns `EINVAL`. Both precede
descriptor exhaustion. The reserved descriptor becomes visible after the
anonymous vnode is attached, so another thread can duplicate it and resolve
its `/proc/self/fd` name as soon as it sees the descriptor.

## Qualification

The same native musl probe ELF per architecture passed on Vinix and Linux
6.12.51. The probe exercised an empty name at a page boundary, an
inaccessible suffix, exact maximum and overlong names, and a valid name
across two pages. It checked flags, mode, ownership, sealing and `EMFILE`
precedence. It also opened and closed 256 files while another thread
duplicated live descriptors and checked their names. The probe then copied
and ran its own ELF through `execveat(AT_EMPTY_PATH)` on an `MFD_EXEC` file.

Production Vinix kernels came from `ca4f66921` plus this change. Both
baseline kernels failed the name-suffix fault check with the final probe.
The `sharedmem`, `execnames`, and `membsync` regressions passed on both
updated kernels.
The allocation checker reported the same existing failures and the same
306 AArch64 and 254 x86-64 allocation sites as the baseline.

| Architecture | Probe ELF | Vinix kernel | Vinix serial log | Linux serial log |
| --- | --- | --- | --- | --- |
| AArch64 | `039de6667599616b` | `2e1156002ebaef68` | `c2e0f33cf7f77247` | `4aa1fee2c91bd3a4` |
| x86-64 | `e92bfb7778ca56e4` | `8e2ad9c71986062b` | `0ccd7bc4cb889acd` | `61341d05086ec307` |

Hashes are SHA-256 prefixes. The archive is
`~/.cache/vinix-r15/memfd-create/qualification.tar.zst`, with SHA-256
`488663aa35007a1c9c2cbe7b0b4e7f96d0b2428108a8f6c1b94b622d339ede14`.

## Limits

`MFD_NOEXEC_SEAL` is covered by the subsequent [execute-sealed memfd qualification](linux-memfd-noexec.md).
`MFD_HUGETLB` and `vm.memfd_noexec` remain unavailable.
