# What Omarchy's Mesa asks of the kernel

Omarchy packages Mesa `omacom/mesa` `b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`.
Building it needs meson, which is Python, so Vinix has not built it, but
Omarchy's prebuilt package of it runs on Vinix in QEMU
([below](#running-it-on-vinix)). This page lists every kernel interface that
Mesa's Asahi drivers and the code they use on a render node call, from the
pinned source, and where Vinix provides each. It is the checklist for the
migration; it does not replace running Mesa on the GPU.

The audit covers the Gallium and Vulkan (Honeykrisp) drivers in `src/asahi`
and `src/gallium/drivers/asahi`, the shared Vulkan runtime and window-system
code, the loader, EGL and the DRI frontend. Their display (KMS) calls belong to
the display driver and are not listed.

| Interface | Mesa use | Vinix |
| --- | --- | --- |
| The twelve `DRM_IOCTL_ASAHI_*` requests: `GET_PARAMS`, `GET_TIME`, `VM_CREATE`, `VM_DESTROY`, `VM_BIND`, `GEM_CREATE`, `GEM_MMAP_OFFSET`, `GEM_BIND_OBJECT`, `QUEUE_CREATE`, `QUEUE_DESTROY`, `SUBMIT`, `GEM_MADVISE` | `src/asahi/lib/agx_device.c`, `src/asahi/vulkan/hk_*.c` | All twelve, in the packaged ABI's extensible form, in `kernel/gpu/agx/file/file.v` and `modern.v`. ("`MMAP_BO`" in Mesa is only an error message for `GEM_MMAP_OFFSET`.) |
| Feature flags | Mesa checks 20 of them, most for G17 | On G13 Linux-Aurora reports only `SOFT_FAULTS`, with fault control `0xb`; so does Vinix (`modern.v`), so Mesa takes the same paths ([G13 soft faults](m1-agx-soft-faults.md)) |
| `VERSION`, `GET_CAP` (`PRIME`, `SYNCOBJ`, `SYNCOBJ_TIMELINE`) | device open, `vk_drm_syncobj.c` | `kernel/drm/drm.v`; version reply as Linux's ([DRM version](m1-agx-drm-version.md)) |
| `GEM_CLOSE`, `PRIME_HANDLE_TO_FD`, `PRIME_FD_TO_HANDLE` | BO lifetime and sharing | `kernel/drm/drm.v` |
| Sync objects: create, destroy, wait (`WAIT_ALL`, `WAIT_FOR_SUBMIT`, `WAIT_AVAILABLE`), timeline wait, query, signal, timeline signal, transfer, handle/fd and sync-file import and export | `vk_drm_syncobj.c`, `hk_queue.c`, `agx_fence.c`, `agx_batch.c` | `kernel/drm/drm.v` and `kernel/drm/syncobj_*.v`; `tests/drm-syncobj-wait` |
| `SYNC_IOC_MERGE`, `SYNC_IOC_FILE_INFO` | `vk_drm_syncobj.c`, `libsync.h` | `kernel/drm/sync_file_merge.v`, `sync_file_info.v` |
| `DMA_BUF_IOCTL_EXPORT_SYNC_FILE`, `IMPORT_SYNC_FILE`, `SYNC` | `agx_device.c`, `agx_batch.c`, `wsi_common_drm.c` | `GemPrimeResource.ioctl` and `kernel/drm/prime_sync.v`, for Asahi buffers |
| `drmGetDevices2`, `drmGetDevice2`, `drmGetNodeTypeFromFd`, `drmGetRenderDeviceNameFromFd` | `loader.c`, EGL, Vulkan WSI | Through sysfs since [DRM sysfs](m1-agx-drm-sysfs.md): on M1 the GPU is a platform device with Linux's identity. Vinix's current Mesa bypasses these with a patch. |
| `mmap` of a GEM offset on the DRM fd | `agx_device.c` | `kernel/drm/drm.v` and the AGX mmap handlers |
| `/proc/self/fdinfo` | not read by Mesa | provided for monitoring tools ([fdinfo](m1-agx-fdinfo.md)) |

Nothing Mesa calls on the render node is missing. What is unverified is the
behaviour behind each entry with this Mesa: no submission has reached a
physical GPU.

## Opening the M1 GPU

Before any of those calls, Mesa has to accept the device. Each check below
was read in the pinned source and compared with what Vinix gives on base M1.
None of it has run against a real GPU.

1. **Discovery.** Honeykrisp (`hk_create_drm_physical_device`) takes a libdrm
   device only if it has a render node and its bus is `DRM_BUS_PLATFORM`. Its
   `drmGetVersion` name must be `asahi`. EGL's surfaceless and device
   platforms find render nodes the same way. Vinix's GPU is a platform device
   in sysfs ([DRM sysfs](m1-agx-drm-sysfs.md)), and its driver name is
   `asahi`.
2. **Identity.** `agx_open_device` needs a `GET_PARAMS` reply of at least
   `offsetof(memory_limit)` bytes. `agx_chip_from_params` maps generation 13,
   variant `'G'` and 1 to 64 clusters to G13G, which
   `agx_params_driver_supported` admits. The AGX3 kernel-ABI feature check
   does not apply to G13. Mesa's `drm_asahi_params_global` declares the same
   fields as Linux-Aurora's header, from which Vinix's reply is generated.
3. **Values.** Every field of Vinix's modern G13 reply
   (`make_modern_global_params` in `kernel/gpu/agx/file/modern.v`) is the one
   Linux-Aurora's G13 `get_params` gives
   ([file.rs](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs#L375-L449),
   [gpu.rs](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gpu.rs)):

   | Field | Both |
   | --- | --- |
   | `vm_start`, `vm_end` | `0x4000` to `(1 << 39) - 0x8000`, the user range below the dummy page |
   | `vm_kernel_min_size` | `0x20000000` |
   | `max_commands_per_submission`, `max_attachments` | 64, 16 |
   | `command_timestamp_frequency_hz` | 1,000,000,000 |
   | `usc_generation`, `gpu_hal_generation` | 2, 0 (legacy) |
   | `features` | `SOFT_FAULTS` only ([soft faults](m1-agx-soft-faults.md)) |
   | `memory_limit`, `client_memory_limit` | 0: Linux-Aurora sets its limits only when it probes a G17 |
   | `gpu_variant`, `gpu_revision` | the character `'G'`; revision codes `0x00` to `0x21` |
   | `max_frequency_khz` | the highest operating point |
   | generation, chip, dies, clusters, cores, core masks | from the GPU's identity registers and the t8103 configuration, on both |

   So Mesa derives the same address layout as on Asahi. The shader heap is at
   `0x1100000000`, the first 4 GiB boundary above its 64 GiB robustness
   carve-out and printf buffer. A 32 GiB kernel range at the top goes to
   `VM_CREATE`, and the user heap is split for its read-only alias.

On the M1, Vinix's display is a simple framebuffer device, `vinix-dumb`, not
Asahi's display driver `apple`. Mesa maps `apple` to its render-only display
driver (`apple_dri.so`), which allocates on the GPU and scans out on the
display; it has no driver for `vinix-dumb`. So a compositor that drives the
display through Mesa will not get that GPU path. Offscreen rendering, which
the acceptance sequence uses, needs only the render node.

## Evidence

The source came from the GitHub archive of the pinned commit; the bundle keeps
its checksum and every match of the interfaces above, by file and line.

`/Users/alex/.local/state/vinix/omarchy-m1-mesa-interface-20261119/`

| Artifact | SHA-256 |
| --- | --- |
| Mesa archive of the pinned commit | `924e5a7b57f61c6ccee4b538959a3d66d21a299f8346a9b576626c682a77ca5b` |
| `bundle.tar.gz` | `6a4947e938d84ab49661a469b6de1735f66471fc694d8feca1b015d36d377426` |

## The prebuilt package

Omarchy publishes this Mesa prebuilt. Its pacman repository's aarch64 edge
channel (`https://pkgs.omarchy.org/edge/aarch64/omarchy.db`, read on
2026-11-19) lists `mesa-aurora 1:26.3.0_devel.20261107.231485.b7b03c5b3b8-3`,
built from the pinned commit; the stable channel still has an older build. So
the packaged Mesa could be run on Vinix without building it, in a glibc root
alongside the libraries it depends on.

| Field | Value |
| --- | --- |
| File | `mesa-aurora-1:26.3.0_devel.20261107.231485.b7b03c5b3b8-3-aarch64.pkg.tar.zst` |
| Size | 7,214,296 bytes compressed, 35,225,817 installed |
| SHA-256 | `ace83518fcd258ac45ed9cb68709c3c39da1af97431618e0020d5a37dd621e4f` |
| Depends | `expat`, `glibc`, `gcc-libs`, `libdrm`, `libglvnd`, `libx11`, `libxcb`, `libxext`, `libxshmfence`, `libxxf86vm`, `libLLVM.so=23.1-64`, `lm_sensors`, `wayland`, `zlib`, `zstd`, `vulkan-mesa-implicit-layers` |

Everything but Mesa itself comes from Arch Linux ARM, including LLVM 23's
`libLLVM.so`, the largest of them. Arch Linux ARM's `llvm-libs 23.1.5-1.2`
provides `libLLVM.so=23.1-64`.

## Running it on Vinix

`tests/omarchy-mesa` stages the package with everything it needs and runs it,
unmodified, on Vinix in QEMU ([README](../tests/omarchy-mesa/README.md)).
`stage.v` resolves the dependencies the way pacman does and checks every
package against its database. On 2026-11-19 it chose 94 packages: 108 MiB to
download, 558 MiB installed.

| Package | Version | From |
| --- | --- | --- |
| `mesa-aurora`, `vulkan-aurora` | `1:26.3.0_devel.20261107.231485.b7b03c5b3b8-3` | Omarchy edge |
| `llvm-libs` | `23.1.5-1.2` | Arch Linux ARM |
| `glibc` | `2.43+r22+g8362e8ce10b2-2` | Arch Linux ARM |
| `libdrm` | `2.4.134-1` | Arch Linux ARM |
| `vulkan-icd-loader`, `vulkan-tools` | `1.4.363.0-1` | Arch Linux ARM |
| `vulkan-mesa-implicit-layers` | `1:26.3.1-1` | Arch Linux ARM (Omarchy has none) |
| `mesa-utils` | `9.0.0-7` | Arch Linux ARM |

The root goes to QEMU as a read-only disk, and the test chroots into it on a
kernel built from `604be201b`, aarch64 `PROD`. There:

- Every library of the Gallium driver (`libgallium-26.3.0-devel.so`), of
  Honeykrisp (`libvulkan_asahi.so`), of `libEGL_mesa.so.0` and of
  `vulkaninfo`, `eglinfo` and `peglgears` resolves.
- The Vulkan loader loads Honeykrisp and creates an instance. Honeykrisp finds
  no GPU, since QEMU has none, so `vkEnumeratePhysicalDevices` fails the way
  the loader fails with no GPU.
- `eglinfo` gets, on the surfaceless and device platforms, `llvmpipe (LLVM
  23.1.5, 128 bits)` with OpenGL `4.6 (Core Profile) Mesa 26.3.0-devel
  (git-b7b03c5b3b)` and OpenGL ES 3.2. GBM, Wayland and X11 do not initialise:
  there is no render node and no display server.
- The device platform lists only the software device. libdrm 2.4.134 lists no
  DRM device, because QEMU's framebuffer is a DRM device without a parent
  ([DRM sysfs](m1-agx-drm-sysfs.md#devices-without-a-parent)).
- `peglgears` draws 41,375 frames in 5 seconds on llvmpipe.
- As a control, the same root without `libLLVM.so.23.1` reports six problems.

glibc 2.43 tries to register `rseq` (syscall 293 on AArch64) in every process.
Vinix does not implement it and logs `VACANT SC:293`. glibc carries on without
it, as it does on Linux kernels older than 4.18.

So in QEMU, Omarchy's Mesa, LLVM 23 and glibc load and render on Vinix. The
Asahi Gallium driver and Honeykrisp only load there. Their device paths need
the M1, where the same root would find `renderD128` through sysfs, without
Vinix's Mesa patch.

Evidence is under
`/Users/alex/.local/state/vinix/omarchy-m1-mesa-root-20261119/`. The bundle
has the run logs, the package manifest with each SHA-256, the database
checksums and the checksums of the kernel, init and disk image. The packages
(`pkgcache/`) and the staged root (`stage-final/root`) are kept beside it.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `d8e9c8e883c6bc557e01c65ded1902befc680dee72f7891d0db12c67faa70c13` |
| `bundle.tar.gz` inventory | `c37f986454dee719ff09a40f6ff1f9d03c6fd099c9252a9664cd9f8527cc275c` |
| kernel `bin/vinix` at `604be201b` | `9a6774e446e1ce3906aaadb631750285046ee4514cc201803ef513a32ed34dd8` |

## Vinix's own build

`scripts/build-asahi-aarch64.sh` now builds this Mesa for Vinix itself, from
the same pinned commit, with no Vinix patches. It builds for Linux, linked
against the Alpine 3.21 musl sysroot that Vinix's Mesa has always used. The
build includes:

- the Asahi Gallium driver, VirGL and softpipe;
- the Honeykrisp Vulkan driver;
- EGL, GLX, GLES 2 and GBM.

Its staging tree replaces Mesa 25.0.5 in the desktop image, and it also
carries Alpine's Vulkan loader and `libdisplay-info`. The 25.0.5 patches are
no longer needed: one taught Mesa about a "vinix" system and named
`/dev/dri/renderD128` directly because Vinix had no sysfs, and libdrm now
finds the GPU through the DRM sysfs entries.

| | Mesa 25.0.5 (before) | Omarchy's Mesa |
| --- | --- | --- |
| Source | mesa3d.org release with four Vinix patches | `omacom/mesa` `b7b03c5`, unmodified |
| Asahi interface | legacy (`unstable_asahi_drm.h`) | the packaged UAPI, as on Omarchy |
| Vulkan | none | Honeykrisp |
| Finds the GPU | patched to `renderD128` | libdrm, through sysfs |

The build needs Debian's `libclang-rt-19-dev`, so that clang can link for the
musl triple, and `glslang-tools` for Honeykrisp's shaders. The script checks
for both. In a Debian 13 aarch64 VM it builds from scratch in 3 minutes 21
seconds.

On Vinix in QEMU (`tests/vinix-mesa`):

- every library of the drivers, of EGL, GL and GBM, and of `eglinfo` and
  `vulkaninfo` resolves through musl's loader;
- the Vulkan loader loads Honeykrisp, which finds no GPU;
- softpipe creates GL 3.3 and GLES 3.1 contexts from Mesa 26.3.

The M1 image preflight now accepts the release the image's marker names. For
Omarchy's Mesa it also requires Honeykrisp, the Vulkan loader and the ICD
file, and the staging tree passes it.

Two things still use 25.0.5:

- **The fake G17 renderer.** It is a 25.0.5 patch for the legacy interface.
  `VINIX_MESA_RELEASE=25.0.5` builds that release as before. The changed
  script was not run for it.
- **The QEMU VirGL desktop.** Mesa 26.3 lists render nodes only through
  libdrm's sysfs walk. QEMU's virtio-gpu node has no parent in sysfs yet, so
  this Mesa would not find it and would draw with softpipe. The VirGL QEMU
  (KekVM) is not built on this Mac, so this was not run.

Evidence is under
`/Users/alex/.local/state/vinix/vinix-mesa26-20261119/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `3f6d9c2fd23a109bb5138ed8587c98191a322f888edb24a79535e33ae0462d4d` |
| `bundle.tar.gz` inventory | `0f5a20df7bcb4906f2d7a800a29030dfa8810297e1737629f1fbe958150b20e1` |
| `libgallium-26.3.0-devel.so` | `a8e00b4daa6148661bbe66a66833563ce3c499604b8a9fe02a5210821fb37a13` |
| `libvulkan_asahi.so` | `4de422fc10c1af233b48aaeb2a0166babcfd24cd8628e8aa3f6a21c15f4e083f` |
