// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the native DRM fence-fd ABI independently of Vulkan extensions.
#include "measure.h"
#include <drm.h>
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <virtgpu_drm.h>

static void snapshot(const char *phase) {
  FILE *f = fopen("/proc/slabinfo", "r");
  if (!f)
    return;
  char line[256];
  while (fgets(line, sizeof(line), f))
    if (!strncmp(line, "size-", 5))
      printf("VENUS-FD-SLAB %s %s", phase, line);
  fclose(f);
  fflush(stdout);
}

int main(void) {
  int fd = -1;
  for (unsigned i = 128; i < 144; i++) {
    char path[40], name[32] = {0};
    snprintf(path, sizeof(path), "/dev/dri/renderD%u", i);
    int candidate = open(path, O_RDWR | O_CLOEXEC);
    if (candidate < 0)
      continue;
    struct drm_version v = {.name = name, .name_len = sizeof(name) - 1};
    if (!ioctl(candidate, DRM_IOCTL_VERSION, &v) &&
        !strcmp(name, "virtio_gpu")) {
      fd = candidate;
      break;
    }
    close(candidate);
  }
  if (fd < 0)
    return 1;
  struct drm_virtgpu_context_set_param params[] = {
      {.param = VIRTGPU_CONTEXT_PARAM_CAPSET_ID, .value = 4},
      {.param = VIRTGPU_CONTEXT_PARAM_NUM_RINGS, .value = 1},
  };
  struct drm_virtgpu_context_init init = {.num_params = 2,
                                          .ctx_set_params = (uintptr_t)params};
  if (ioctl(fd, DRM_IOCTL_VIRTGPU_CONTEXT_INIT, &init)) {
    perror("context init");
    return 2;
  }
  for (unsigned i = 0; i < 1032; i++) {
    if (i == 8) {
      start_tracking();
      snapshot("before");
    }
    struct drm_virtgpu_execbuffer submit = {
        .flags = VIRTGPU_EXECBUF_FENCE_FD_OUT |
                 ((i & 1) ? VIRTGPU_EXECBUF_RING_IDX : 0),
        .fence_fd = -1,
        .ring_idx = 0,
    };
    if (ioctl(fd, DRM_IOCTL_VIRTGPU_EXECBUFFER, &submit)) {
      perror("fence submit");
      return 3;
    }
    struct pollfd p = {.fd = submit.fence_fd, .events = POLLIN};
    if (submit.fence_fd < 0 || poll(&p, 1, 0) != 1 || !(p.revents & POLLIN)) {
      fprintf(stderr, "completed fence fd is not readable\n");
      return 4;
    }
    close(submit.fence_fd);
  }
  snapshot("after");
  dump_sites("venus-fd");
  close(fd);
  puts("VINIX_VENUS_FENCE_FD_PASS");
  return 0;
}
