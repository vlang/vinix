# Linux executable write exclusion

Vinix now returns `ETXTBSY` when a native exec opens a regular file held
by a writable open description. The inverse applies to writable opens,
`O_TRUNC` and pathname `truncate` while the file is executing. Read-only
opens and `O_PATH` remain usable. A hard link conflicts using the same
device and inode numbers. This follows [Linux 6.12.51 exec](https://github.com/gregkh/linux/blob/v6.12.51/fs/exec.c)
and [its inode write-access checks](https://github.com/gregkh/linux/blob/v6.12.51/include/linux/fs.h).

A writable open description is shared by descriptor copies and stays alive
through mappings that retain it. Denial for the main executable belongs to
its address space. Fork copies it, `CLONE_VM` shares it, and the last address
space owner releases it on exit or replacement. Scripts and ELF interpreters
hold a temporary denial during loading. A failed load releases all its claims.
The claims use storage in the existing open description, address space or
syscall frame, with no claim allocations.

## Qualification

Use `tests/linux-compat/run --cases textbusy` for the native tmpfs tests.
Run `build-support/run-v-tool.sh tests/linux-compat/run-mount.v --case textbusy`
with `--arch`, `--kernel-dir`, and a fresh `--state-dir` to include persistent
ext2 hard links. `tests/linux-compat/syscall-reference.v --case textbusy`
can run the same ELF against Linux 6.12.51.

Optimized Vinix kernels built from `340c91b7e` plus this change pass on
AArch64 and x86-64. Both guests verify the write lock in both directions
after hard links are read back from disk, and they verify release when the
last image owner exits. The identical ELF passes the tmpfs controls on
Linux 6.12.51 on each architecture. The x86-64 baseline admitted `execveat`
while the target still had a writable descriptor.

| Architecture | Probe ELF | Vinix kernel | Vinix serial log |
| --- | --- | --- | --- |
| AArch64 | `56fcf8b6e479d48f` | `e2c8af409e449b5c` | `00880a208f38d0fb` |
| x86-64 | `9bfa60c3ec907e7a` | `347a8700d44d6b6c` | `9375141ee9797633` |

The hashes are SHA-256 prefixes. Receipts and full checksums are in
`~/.cache/vinix-r15/etxtbsy/{arm,x86}-disk-final` and the `arm-reference`
and `x86-reference-finaldev` directories there. The allocation checker
reports the same site counts and existing allow-list failures as the
previous baseline. Its output is in `allocs.log` in the same directory.
The `execown`, `open` and `mmap` regressions passed on both final kernels.
The `execown` runs kept slab objects and large pages flat over 200 cycles
each as root and UID 1000. Their receipts are in `{arm,x86}-regress`.

## Limits

The coverage here concerns the backing inode of a native image. Overlayfs
metadata copy-up may change the backing inode of an overlay name while its
previous inode is in use. Translated payloads keep a temporary claim during
handoff to the native interpreter. Remote mutations are outside local inode
accounting. Ext2 shares inode ownership among hard links within a mounted tree,
including after a remount. Independently mounted views of a device still build
separate inode state. [Hard-link lifetime qualification](linux-ext2-hardlinks.md)

Set-ID exec credential transitions and Chromium's packaged sandbox still
need separate implementation and qualification.
