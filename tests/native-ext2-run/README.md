# Native ext2 guest controller

`tests/ext2-xattr/run` uses V for kernel/source receipts, fixture compilation,
initramfs staging, ACL preparation, isolated guest supervision and host disk
validation. It retains the current controller's C-source and immutable prebuilt
fixture options, alongside the maintained V fixture selected by default.

```sh
./tests/ext2-xattr/run --source tests/ext2-xattr/test.c --state-dir /tmp/ext2-c
./tests/ext2-xattr/run --prebuilt-fixture /immutable/init --state-dir /tmp/ext2-elf
./tests/ext2-xattr/run --arch x86_64 --source tests/ext2-xattr/test.c \
    --kernel-dir /worktree/kernel --state-dir /tmp/ext2-x86
```

The pinned compiler currently emits unresolved `memdup` calls for address-taking
in the unchanged V fixture. The controller preserves and reports that build
failure; it supplies no allocator shim, changes no fixture assertion and does not
relax compiler guards. Use the independent C source or an immutable SDK fixture
while that separate fixture/toolchain issue is resolved. A short state path also
keeps its Unix QMP address within Darwin's socket limit.

The controller copies the tested kernel before building, records source and ELF
hashes, stages native USTAR, preserves the original ext2/mtools recipes and writes
the same on-disk ACL version corruption. The private PTY owner reserves the
leader identity through group cleanup and sole reap. Expected guest verdicts
settle for two seconds; monitor/Ctrl-A-x, TERM and KILL receive the original
three-second phases. Final serial logs survive failure and cancellation. Serial
capture is bounded at 64 MiB; CLI timeouts must be positive.

Qualification uses actual static ARM/x86 C fixture builds, native V serial
objects, native archives, real mke2fs/debugfs/e2fsck and controlled PTY/QMP guest
processes. Standalone ACL checks compare complete disk blocks before and after
the exact four-byte corruption, and independently confirm detection by e2fsck.
Controls cover C and prebuilt workflows, both integrated ACL layouts, explicit
V-fixture build failures, missing attributes/reboot, early exit, timeout and
signals. They establish no new kernel/guest retained-allocation result.

The concurrently edited `tests/ext2-xattr/run.py` and its kernel-gap imports are
preserved. This new maintained command executes no Python; Python-file retirement
is pending the remaining legacy caller closure.
