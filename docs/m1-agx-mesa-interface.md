# What Omarchy's Mesa asks of the kernel

Omarchy packages Mesa `omacom/mesa` `b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`.
Building it needs meson, which is Python, so it has not been built or run on
Vinix. This page lists every kernel interface that Mesa's Asahi drivers and the
code they use on a render node call, from the pinned source, and where Vinix
provides each. It is the checklist for the migration; it does not replace
running the build.

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
behaviour behind each entry with this Mesa: the build has not run, and no
submission has reached a physical GPU.

## Evidence

The source came from the GitHub archive of the pinned commit; the bundle keeps
its checksum and every match of the interfaces above, by file and line.

`/Users/alex/.local/state/vinix/omarchy-m1-mesa-interface-20261119/`

| Artifact | SHA-256 |
| --- | --- |
| Mesa archive of the pinned commit | `924e5a7b57f61c6ccee4b538959a3d66d21a299f8346a9b576626c682a77ca5b` |
| `bundle.tar.gz` | `6a4947e938d84ab49661a469b6de1735f66471fc694d8feca1b015d36d377426` |
