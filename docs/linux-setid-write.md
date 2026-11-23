# Set-ID bits on file writes and truncation

On tmpfs, ext2 and VJFS, a write or userspace truncation of a regular file
clears setuid unless the caller has `CAP_FSETID` in the initial user namespace.
It also clears setgid if group execute is set or the caller is outside the
file's group. Group membership uses the filesystem GID and supplementary
groups. Zero-byte writes preserve the bits. Explicit truncation to the existing
size and file extension through `fallocate` still apply the rule.
[Linux 6.12 attribute checks](https://github.com/torvalds/linux/blob/v6.12/fs/attr.c)
and [truncate path](https://github.com/torvalds/linux/blob/v6.12/fs/open.c).

Tmpfs changes the mode under the file lock. Ext2 stages the cleared mode
before changing data and publishes it to the live inode cache. VJFS commits
the mode in the transaction that makes the write or new EOF visible.

## Qualification

Run `build-support/run-v-tool.sh tests/linux-compat/run-mount.v --case setid`
with `--arch`, `--kernel-dir`, and a fresh `--state-dir`. Add `--journal` for
a private VJFS volume. The probe runs ten operations in three group/mode
combinations as root and as UID/GID 1000. It checks the resulting mode and
file size, then remounts the disk and checks them again. The same probe ELF
runs the tmpfs cases on Linux using the `--case setid` option of
`tests/linux-compat/syscall-reference.v`.

The optimized Vinix kernels contain the kernel sources from `7bf207117`
and this change, built with `PROD=true`. On both architectures, all 60
operations per filesystem passed for tmpfs, ext2 and VJFS. The disk modes
and sizes matched again after remount. Linux 6.12.51 passed all 60 tmpfs
operations on both architectures with the same probe ELF as Vinix.
The original Vinix kernel left mode `06777` after UID 1000 wrote the first
test file, where the reference leaves `0777`.

| Architecture | Probe ELF | Vinix kernel | Linux kernel |
| --- | --- | --- | --- |
| AArch64 | `6355b803b17e3c4a` | `896b842ff73d2e97` | `c8d8cdec004d4259` |
| x86-64 | `cada4dd0a572d33e` | `b129bca1b0dcbd01` | `ec9073e710b26f59` |

Hashes are SHA-256 prefixes. The receipts and full checksums are under
`~/.cache/vinix-r15/setid/{arm,x86}-{ext2,vjfs,linux}-verified`. The
`{arm,x86}-regress` runs on the same Vinix kernels passed `fchmodat2`,
`fsuid`, `truncateaccess` and `shmremap`. The default mount regression also
passed on both architectures in `{arm,x86}-mount-verified`.

## Limits

This qualification covers direct writes, append, `truncate`, `ftruncate`,
`O_TRUNC` and extension through `fallocate` on the three local filesystems.
Vinix currently treats `fallocate` entirely within EOF as a no-op. Mapped stores,
remote filesystem behavior, file capabilities and set-ID credential changes
during exec are separate parts of the Linux ABI. Chromium's setuid sandbox
helper still requires the exec changes.
