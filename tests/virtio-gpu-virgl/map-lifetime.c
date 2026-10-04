/*
 * VirtIO GPU GEM mapping lifetime regression. Build with
 * aarch64-linux-musl-gcc -static -O2 -o vinix-virtgpu-map-lifetime map-lifetime.c
 * and run inside a Vinix VirGL VM with /dev/dri/renderD128.
 *
 * Keeping the DRM fd open makes stale mapping references exhaust Vinix's
 * 4096 GEM handles. Both close orders must recycle them while a mapping
 * remains readable after GEM_CLOSE.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

struct virtgpu_create {
    uint32_t target, format, bind, width, height, depth, array_size;
    uint32_t last_level, nr_samples, flags, bo_handle, res_handle, size, stride;
};
struct virtgpu_map { uint64_t offset; uint32_t handle, pad; };
struct gem_close { uint32_t handle, pad; };
#define VIRTGPU_CREATE _IOWR('d', 0x44, struct virtgpu_create)
#define VIRTGPU_MAP _IOWR('d', 0x41, struct virtgpu_map)
#define GEM_CLOSE _IOW('d', 0x09, struct gem_close)

int main(void) {
    int fd = open("/dev/dri/renderD128", O_RDWR | O_CLOEXEC);
    if (fd < 0) { perror("open render node"); return 1; }
    const uint32_t bytes = 4096;
    for (int i = 0; i < 4600; ++i) {
        struct virtgpu_create create = {
            .target = 0, .format = 64, .bind = 1 << 4,
            .width = bytes, .height = 1, .depth = 1, .array_size = 1,
            .size = bytes, .stride = bytes,
        };
        if (ioctl(fd, VIRTGPU_CREATE, &create) < 0) {
            fprintf(stderr, "MAP_LIFETIME_CREATE_FAIL %d errno=%d\n", i, errno);
            return 2;
        }
        struct virtgpu_map map = {.handle = create.bo_handle};
        if (ioctl(fd, VIRTGPU_MAP, &map) < 0) {
            fprintf(stderr, "MAP_LIFETIME_MAP_IOCTL_FAIL %d errno=%d\n", i, errno);
            return 3;
        }
        unsigned char *address = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
                                      MAP_SHARED, fd, map.offset);
        if (address == MAP_FAILED) {
            fprintf(stderr, "MAP_LIFETIME_MMAP_FAIL %d errno=%d\n", i, errno);
            return 4;
        }
        address[0] = (unsigned char)i;
        address[bytes - 1] = (unsigned char)(i + 1);
        struct gem_close close_request = {.handle = create.bo_handle};
        if (i % 2 == 0) {
            if (munmap(address, bytes) < 0) { perror("munmap"); return 5; }
            if (ioctl(fd, GEM_CLOSE, &close_request) < 0) { perror("GEM_CLOSE"); return 6; }
        } else {
            if (ioctl(fd, GEM_CLOSE, &close_request) < 0) { perror("GEM_CLOSE"); return 7; }
            if (address[0] != (unsigned char)i ||
                address[bytes - 1] != (unsigned char)(i + 1)) {
                fprintf(stderr, "MAP_LIFETIME_POST_CLOSE_CORRUPTION %d\n", i);
                return 8;
            }
            if (munmap(address, bytes) < 0) { perror("munmap"); return 9; }
        }
        if ((i + 1) % 500 == 0) {
            printf("MAP_LIFETIME_PROGRESS %d\n", i + 1);
            fflush(stdout);
            sleep(1);
        }
    }
    puts("MAP_LIFETIME_PASS");
    close(fd);
    return 0;
}
