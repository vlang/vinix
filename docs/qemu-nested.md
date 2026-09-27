# Run Vinix in Vinix with QEMU

The AArch64 QEMU system layer runs a second Vinix kernel using TCG software
emulation. Hardware virtualization is not required inside Vinix.

On the build host, stage QEMU and build a desktop image containing it:

```sh
./build-qemu-system-aarch64.sh
./build-desktop-aarch64.sh --with-qemu-system
./run-desktop-aarch64.sh --no-build
```

The builder uses Alpine 3.21's native AArch64 QEMU package and copies the
AArch64 UEFI firmware from the host QEMU installation. Set
`VINIX_QEMU_FIRMWARE_CODE` and `VINIX_QEMU_FIRMWARE_VARS` if the firmware is
installed elsewhere.

Build a bootable raw image for the inner VM from the current kernel and base
userland initramfs:

```sh
./build-vinix-guest-disk.sh
```

The image is written to `build-aarch64-qemu-system/vinix-guest.img`. The
builder refuses to overwrite an existing image; move or remove it when you
intend to rebuild. You can pass an output path and a different uncompressed
initramfs tar as the first two arguments.

Copy that image into Vinix. For a Vinix desktop running in the host QEMU, a
simple way is to serve it from the host:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory build-aarch64-qemu-system
```

Then, in the Vinix terminal:

```sh
curl -fLo /root/vinix-guest.img http://10.0.2.2:8765/vinix-guest.img
vinix-qemu /root/vinix-guest.img
```

`vinix-qemu` creates a writable UEFI variables file under
`$HOME/.vinix-qemu`, enables the memory permissions QEMU's TCG needs, and
boots the raw image with a serial console. Set `VINIX_QEMU_GUEST_MEM` (MiB)
or `VINIX_QEMU_GUEST_SMP` to change the inner VM's memory or CPU count. The
default is 2048 MiB and one CPU. The inner image is writable and keeps its
changes across runs.

For a two level boot check with a tiny inner initramfs, run
`./tests/qemu-nested/run.sh` on the build host. It reports
`VINIX NESTED QEMU: PASS` only when PID 1 in the inner Vinix prints the marker.
