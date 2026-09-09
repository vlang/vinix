# Vinix GPU testing with KekVM

Run the complete local acceleration smoke test on Apple silicon with:

```sh
./test-gpu-kekvm.sh
```

The command uses KekVM's private VirGL-enabled QEMU build. It boots the current
Vinix AArch64 kernel and desktop image, submits a real Mesa draw, waits on the
Vinix DRM fence, reads the pixels back, and requires the renderer to identify
both VirGL and the host Apple GPU. A test-only `/sbin/init` is supplied as the
last initramfs module, so the built image and any persistent VM disk remain
unchanged.

The accelerated path is:

```text
Vinix application / Mesa
        ↓
Vinix VirtIO-GPU DRM driver
        ↓
QEMU virtio-gpu-gl-device
        ↓
virglrenderer
        ↓
ANGLE / Metal
        ↓
host Apple GPU
```

This is hardware-accelerated rendering, but it is paravirtualized access—not
direct GPU passthrough. macOS retains ownership of the physical GPU and the
guest submits a portable VirGL command stream through a host API.

Consequently, this test covers the Vinix VirtIO DRM implementation, GEM and
fence lifecycle, Mesa/EGL/GLES integration, command transport, and real pixel
rendering. It does **not** cover the native Apple AGX backend's device-tree
probe, PMP/RTKit boot, DART/UAT page tables, Apple firmware command execution,
or physical completion interrupts. Those remain M1 hardware tests; the fake
G17 VM backend separately validates native descriptor construction without
claiming to rasterize it.

If the harness cannot find the backend, prepare KekVM first:

```sh
make -C ~/code/kekvm setup-gpu
```

The harness creates a temporary sparse FAT boot disk, opens a Cocoa graphics
window while the test runs, exits QEMU after receiving the result marker, and
deletes the temporary disk afterward. Override the backend or timeout with
`VINIX_VIRGL_QEMU` and `VINIX_VIRGL_VM_TIMEOUT` respectively.
