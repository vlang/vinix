# OpenBSD security features

`test.c` checks Vinix's OpenBSD mitigations from userspace (see
[docs/openbsd-security.md](../../docs/openbsd-security.md)). Each case runs in
a child process, so a pledge violation that kills the child is something the
parent can check. The test runs as PID 1 and prints
`VINIX OPENBSD SECURITY: PASS` or `FAIL` on the serial console.

Build the kernel for the architecture under test, then boot it with the test:

```sh
make -C kernel CC=clang ARCH=aarch64 LIMINE_MP=1 V=/path/to/v
tests/openbsd-security/run.sh aarch64

V=/path/to/v ./build-amd64.sh --no-userland --no-iso
tests/openbsd-security/run.sh amd64
```

The aarch64 run compiles against the musl sysroot from
`./build-userland-aarch64.sh` (or `VINIX_AARCH64_SYSROOT`) and boots through
`run-aarch64.sh --guest-init` with its own boot disk, EFI variables and
persistent volume. The amd64 run compiles with `x86_64-linux-musl-gcc` (or
`CC_AMD64`), builds a throwaway ISO around `build-amd64-kernel/bin/vinix`, and
boots it under TCG. Both runs leave nothing behind. `VINIX_QEMU_TIMEOUT`
changes the default 600-second deadline.

On aarch64 the runner also expects the kernel's report of a violation on
serial. amd64 production kernels print only to the framebuffer, so that check
is skipped there. The amd64 Linux ABI has no `clone`, `rename`, `link`,
`symlink` or `mount` yet; the cases that need them accept `ENOSYS` there, and
the thread case runs on aarch64 only.
