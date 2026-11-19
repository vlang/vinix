# Vinix's Mesa build in QEMU

```sh
VINIX_AARCH64_SYSROOT=... tests/omarchy-mesa/run --kernel-dir KERNEL \
    --root ROOT --state NEW_DIR --guest tests/vinix-mesa/guest.c --marker VINIX-MESA
```

`scripts/build-asahi-aarch64.sh` builds Omarchy's pinned Mesa
(`omacom/mesa` `b7b03c5`) for Vinix's musl userland: the Asahi Gallium and
Honeykrisp Vulkan drivers, VirGL and softpipe, with no Vinix patches.

`ROOT` is the script's staging tree with Alpine 3.21's `mesa-utils`,
`vulkan-tools`, `wayland-libs-client` and `libffi` added, for `eglinfo` and
`vulkaninfo`. The runner attaches it as a read-only ext2 disk, and `guest.c`
chroots into it. QEMU has no Apple GPU, so the guest checks that:

- every library of the Gallium and Honeykrisp drivers, of EGL, GL and GBM, and
  of both clients resolves through musl's loader;
- the Vulkan loader loads Honeykrisp and creates an instance, and Honeykrisp
  finds no GPU;
- softpipe creates GL 3.3 and GLES 3.1 contexts from Mesa 26.3.

It prints `VINIX-MESA PASS`, or `VINIX-MESA INCOMPLETE problems=N`.
