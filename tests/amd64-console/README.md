# amd64 console guest regression

Compile with an x86_64 musl toolchain:

```sh
musl-gcc -static -O2 -Wall -Wextra -Werror tests/amd64-console/test.c -o init
mkdir -p test-root/sbin
cp init test-root/sbin/init
tar --format=ustar -cf test-initramfs.tar -C test-root .
VINIX_AMD64_INITRAMFS="$PWD/test-initramfs.tar" \
VINIX_AMD64_ISO="$PWD/test-console.iso" ./build-support/build-amd64-iso.sh
```

Build the amd64 kernel first (`./build-amd64.sh --no-userland --no-iso`). Boot the diagnostic ISO in an isolated QEMU/KVM x86_64 guest with UEFI, VGA, HPET, and COM1 serial capture. The init forks a test worker and prints `TEST RESULT: PASS` or `FAIL` on COM1. It then sleeps; terminate only the test VM from the host. Use a host-side timeout to detect a kernel crash or blocked syscall. The process-group test re-execs `/sbin/init`, so retain that installation path. Do not run these guest tests on the host.
