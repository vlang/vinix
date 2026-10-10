# Host compiler selection checks

Run `./tests/compiler-selection/test-find-v.sh` for V compiler discovery and
`./tests/compiler-selection/test-kernel-ar` for kernel archiver selection.

The native archiver test copies the kernel makefile from one committed Git
snapshot into a temporary fixture tree, excluding concurrent kernel edits.
It also snapshots the untracked compiler-runtime dependency's makefile there.
It checks macOS LLVM discovery, configured and explicit archiver precedence,
missing-tool errors, cleanup goals, and Linux's ordinary `ar` default. A native
V stand-in for `uname` supplies both host profiles. It also compiles and lists
a real one-object AArch64 ELF archive using Clang and LLVM, then removes its
temporary tree on success or failure. It does not build a kernel.

For the native cleanup check, set `VINIX_ARCHIVER_CHECK` to a compiled test
command and run `v -nocache -cc cc test tests/compiler-selection/archivercheck`.
This verifies a successful real archive run and a forced compiler failure,
including removal of each run's temporary directory.
