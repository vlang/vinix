// SPDX-License-Identifier: GPL-2.0-or-later
// Probe capabilities without opening Vulkan or depending on Linux sysfs.
#include <drm.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <virtgpu_drm.h>
int main(void) {
  for (unsigned i = 128; i < 144; i++) {
    char path[40], name[32] = {0};
    snprintf(path, sizeof(path), "/dev/dri/renderD%u", i);
    int fd = open(path, O_RDWR | O_CLOEXEC);
    if (fd < 0)
      continue;
    struct drm_version version = {.name = name, .name_len = sizeof(name) - 1};
    int ready =
        !ioctl(fd, DRM_IOCTL_VERSION, &version) && !strcmp(name, "virtio_gpu");
    const unsigned params[] = {VIRTGPU_PARAM_RESOURCE_BLOB,
                               VIRTGPU_PARAM_HOST_VISIBLE,
                               VIRTGPU_PARAM_CONTEXT_INIT};
    for (unsigned j = 0; ready && j < 3; j++) {
      uint64_t value = 0;
      struct drm_virtgpu_getparam p = {.param = params[j],
                                       .value = (uintptr_t)&value};
      ready = !ioctl(fd, DRM_IOCTL_VIRTGPU_GETPARAM, &p) && value;
    }
    uint64_t capsets = 0;
    struct drm_virtgpu_getparam caps = {.param =
                                            VIRTGPU_PARAM_SUPPORTED_CAPSET_IDs,
                                        .value = (uintptr_t)&capsets};
    ready = ready && !ioctl(fd, DRM_IOCTL_VIRTGPU_GETPARAM, &caps) &&
            (capsets & (1u << 4));
    close(fd);
    if (ready)
      return 0;
  }
  return 1;
}
