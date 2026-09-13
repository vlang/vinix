# amd64 kill guest regression

Compile with an x86_64 musl toolchain:

```sh
musl-gcc -static -O2 -Wall -Wextra -Werror tests/amd64-kill/test.c -o init
mkdir -p test-root/sbin
cp init test-root/sbin/init
tar --format=ustar -cf test-initramfs.tar -C test-root .
VINIX_AMD64_INITRAMFS="$PWD/test-initramfs.tar" \
VINIX_AMD64_ISO="$PWD/test-kill.iso" ./build-support/build-amd64-iso.sh
```

Build the amd64 kernel first (`./build-amd64.sh --no-userland --no-iso`). Boot the diagnostic ISO in an isolated QEMU/KVM x86_64 guest with UEFI, VGA, HPET, and COM1 serial capture. The init forks a test worker and prints `TEST RESULT: PASS` or `FAIL` on COM1. It then sleeps; terminate only the test VM from the host. Use a host-side timeout to detect a kernel crash or blocked syscall. The process-group test re-execs `/sbin/init`, so retain that installation path. Do not run these guest tests on the host.

The positive-signal checks verify PID/group selection through interruption of a wait. They do not claim Linux signal-handler dispatch: amd64 currently requires the native `sigentry`, which the Linux ABI does not install. A musl `sigaction(SIGUSR1, ...)` followed by `kill(getpid(), SIGUSR1)` queues the signal but does not invoke the handler on the tested upstream revision. Completing Linux signal frames/dispatch is a separate change. Credential denial cases cannot be exercised from this Linux ABI because amd64 does not expose the credential-changing syscalls yet.
