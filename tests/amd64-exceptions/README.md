# AMD64 user exception stack regression

`test.c` runs as PID 1 in an isolated QEMU guest. It faults 48 children while
file, pipe and UNIX socket descriptors remain open, then checks signal status
and socket EOF. Two threads also raise 256 trap/illegal-instruction exceptions;
their returning signal handlers block on a pipe while a peer releases them.
Run with one CPU to force blocking context switches and four CPUs to exercise
concurrent faults.

Build the x86_64 kernel, then prepare an initramfs and ISO from this checkout:

```sh
work=$(mktemp -d)
mkdir -p "$work/rootfs"/{sbin,dev,proc,sys,tmp,mnt,root}
x86_64-linux-musl-gcc -static -O2 -Wall -Wextra -Werror \
  tests/amd64-exceptions/test.c -lpthread -o "$work/rootfs/sbin/init"
COPYFILE_DISABLE=1 tar --format=ustar -cf "$work/initramfs.tar" \
  -C "$work/rootfs" .
VINIX_AMD64_KERNEL="$PWD/kernel/bin/vinix" \
VINIX_AMD64_INITRAMFS="$work/initramfs.tar" \
VINIX_AMD64_ISO="$work/test.iso" \
VINIX_AMD64_ISO_BUILD_DIR="$work/iso" \
  sh build-support/build-amd64-iso.sh
```

Boot the ISO with an x86_64 UEFI firmware image; repeat with `-smp 4`:

```sh
qemu-system-x86_64 -machine q35,smm=off -accel tcg -cpu max -m 1024 \
  -smp 1 -drive "if=pflash,format=raw,unit=0,readonly=on,file=$UEFI_FIRMWARE" \
  -cdrom "$work/test.iso" -display none -monitor none -serial stdio -no-reboot
```

Success ends with `EXCEPTION TEST: PASS`. PID 1 then waits forever; stop QEMU
after reading that marker. The test creates files on the initramfs tmpfs and
requires no data disk. It covers descriptor teardown and blocking handlers;
it does not exercise disk-backed writeback on fatal exit.
