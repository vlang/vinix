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
