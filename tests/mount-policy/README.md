# Mount policy regression tests

Build the kernel for the selected architecture, then run
`tests/mount-policy/run.sh aarch64` or `tests/mount-policy/run.sh amd64`.
`VINIX_KERNEL_DIR` selects an isolated ARM64 kernel worktree and
`VINIX_AMD64_KERNEL` selects the built x86-64 binary. The musl sysroot and VM
configuration use the same variables as the OpenBSD security suite.

The static guest init checks noexec for ELF executables, scripts, symlinks,
ELF interpreters, descriptor and directory-relative exec, and file mappings.
Protection ceilings survive range splitting, fork and mremap. Nodev blocks
character and block device opens while permitting O_PATH and regular files.
Bind aliases retain independent policy through cwd, directory descriptors,
proc magic links, moved mounts, self binds and namespace remounts, including
inherited descriptors after lazy unmount. Partial argv faults and aggregate
E2BIG errors check argument cleanup. An ordinary dynamic
launch is checked before restricting its interpreter, and 200 rejected dynamic
launches check that slab memory remains within 64 KiB after warmup.

W^X tests cover the default protection rule, unauthorized environment opt-in,
an effective-root launcher with and without CAP_SYS_ADMIN, and a wxallowed
executable mount. Bind inheritance, administrator remounts, rejected user
remounts and an unauthorized script using an authorized interpreter are checked.

The VFS still shares child mounts between bind aliases of an inode. Traversing
`..` from such a shared child uses the mount's recorded parent, which can differ
from the alias used to enter it. This nested alias case needs further mount
context work; these tests do not claim to cover it.

The runner requires every feature marker and the final PASS exactly once;
ENOSYS, kernel faults, guest failures and timeouts fail the run. It reuses the
existing security suite's isolated QEMU boot and serial validation code.
