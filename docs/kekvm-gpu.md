# Vinix GPU testing with KekVM

Run the complete local acceleration smoke test on Apple silicon with:

```sh
./test-gpu-kekvm.sh
```

The command uses KekVM's patched VirGL-enabled QEMU build. It boots the current
Vinix AArch64 kernel and userland from a temporary boot disk, submits a real
Mesa draw, waits on the Vinix DRM fence, reads the pixels back, and requires
the renderer to identify both VirGL and the host Apple GPU. A test-only
`/sbin/init` is supplied as the last initramfs module, so the built image and
any persistent VM disk remain unchanged.

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
host Apple GPU
```

This is hardware-accelerated rendering, but it is paravirtualized access—not
direct GPU passthrough. macOS retains ownership of the physical GPU and the
guest submits a portable VirGL command stream through a host API.

Vinix uses 16 KiB pages for AArch64 processes, which satisfies KekVM's guest
page-size requirement for Venus. The kernel retains 4 KiB mappings for its
Limine-compatible higher-half address space. This launch still uses VirGL for
accelerated OpenGL: Vinix's VirtIO-GPU DRM driver does not yet implement the
blob resources, context initialization, and modern VirtIO transport needed by
Venus, so Vulkan acceleration remains disabled.

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

Pass `--desktop-startup` to boot the full desktop image from temporary FAT and
ext2 disks and require its first accelerated frame. The default smoke test uses
the smaller shell image so the GPU check does not wait for the full desktop to
load. The harness opens a graphics window, exits QEMU after receiving the
result marker, and deletes its temporary disks. Override the backend or timeout
with `VINIX_VIRGL_QEMU` and `VINIX_VIRGL_VM_TIMEOUT` respectively.
