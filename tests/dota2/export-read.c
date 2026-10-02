/* Compare host-selected real game bytes after traversing Vinix ext2 over NBD. */
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <unistd.h>

#define CHECK(condition) do { if (!(condition)) { \
    printf("DOTA2 EXPORT: FAIL line %d errno=%d\n", __LINE__, errno); return 1; \
} } while (0)

int main(void)
{
    printf("DOTA2 EXPORT: START\n");
    CHECK(mount("/root", "/root", "qemu-persist", MS_REMOUNT | MS_RDONLY, "") == 0);
    FILE *samples = fopen("/samples.bin", "rb");
    CHECK(samples != NULL);
    unsigned char magic[8];
    uint32_t count;
    long page_size = sysconf(_SC_PAGESIZE);
    CHECK(page_size > 0);
    CHECK(fread(magic, 1, sizeof(magic), samples) == sizeof(magic));
    CHECK(memcmp(magic, "VNXDOTA1", 8) == 0);
    CHECK(fread(&count, sizeof(count), 1, samples) == 1 && count > 0 && count < 1000);
    for (uint32_t index = 0; index < count; ++index) {
        uint16_t name_length;
        char path[4096] = "/root/";
        uint64_t offset;
        uint32_t length;
        unsigned char expected[8192], actual[8192];
        CHECK(fread(&name_length, sizeof(name_length), 1, samples) == 1);
        CHECK(name_length < sizeof(path) - 7);
        CHECK(fread(path + 6, 1, name_length, samples) == name_length);
        path[6 + name_length] = 0;
        CHECK(fread(&offset, sizeof(offset), 1, samples) == 1);
        CHECK(fread(&length, sizeof(length), 1, samples) == 1 && length > 0 && length <= sizeof(expected));
        CHECK(fread(expected, 1, length, samples) == length);
        int fd = open(path, O_RDONLY);
        CHECK(fd >= 0);
        CHECK(pread(fd, actual, length, (off_t)offset) == length);
        CHECK(memcmp(expected, actual, length) == 0);
        off_t aligned = (off_t)(offset / (uint64_t)page_size * (uint64_t)page_size);
        size_t map_length = (size_t)(offset - aligned) + length;
        void *area = mmap(NULL, map_length, PROT_READ, MAP_PRIVATE, fd, aligned);
        CHECK(area != MAP_FAILED);
        CHECK(memcmp(expected, (unsigned char *)area + offset - aligned, length) == 0);
        CHECK(munmap(area, map_length) == 0);
        CHECK(close(fd) == 0);
        errno = 0;
        CHECK(open(path, O_WRONLY) == -1 && errno == EROFS);
        uint64_t hash = UINT64_C(14695981039346656037);
        for (uint32_t byte = 0; byte < length; ++byte) hash = (hash ^ expected[byte]) * UINT64_C(1099511628211);
        printf("DOTA2 EXPORT: bytes=%u offset=%" PRIu64 " fnv64=%016" PRIx64 " %s\n",
               length, offset, hash, path + 6);
    }
    CHECK(fclose(samples) == 0);
    printf("DOTA2 EXPORT: PASS\n");
    fflush(stdout);
    for (;;) pause();
}
