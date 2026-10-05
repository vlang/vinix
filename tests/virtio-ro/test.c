/* A read-only shared mapping must never poison the backing block cache. */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <unistd.h>

static int failures;
#define REQUIRE(test) do { if (!(test)) { \
    printf("VIRTIO-RO FAIL: line=%d errno=%d\n", __LINE__, errno); return 1; \
} } while (0)
#define VERIFY(test) do { if (!(test)) { \
    printf("VIRTIO-RO CHECK-FAIL: line=%d errno=%d\n", __LINE__, errno); ++failures; \
} } while (0)

static unsigned char expected_byte(uint64_t offset, unsigned int seed)
{
    return (unsigned char)(seed + 17 * (offset / 4096) + 13 * (offset % 4096));
}

static int matches(const unsigned char *bytes, size_t size, uint64_t offset,
                   unsigned int seed)
{
    for (size_t index = 0; index < size; ++index)
        if (bytes[index] != expected_byte(offset + index, seed)) return 0;
    return 1;
}

static int root_is_readonly(void)
{
    FILE *mounts = fopen("/proc/mounts", "r");
    if (!mounts) return 0;
    char line[1024];
    int found = 0;
    while (fgets(line, sizeof line, mounts)) {
        char source[128], target[128], type[128], options[128];
        if (sscanf(line, "%127s %127s %127s %127s", source, target, type, options) == 4
            && strcmp(source, "/dev/vdb") == 0 && strcmp(target, "/root") == 0
            && (strcmp(options, "ro") == 0 || strncmp(options, "ro,", 3) == 0)) found = 1;
    }
    fclose(mounts);
    return found;
}

int main(void)
{
    setbuf(stdout, NULL);
    puts("VIRTIO-RO START");
    VERIFY(root_is_readonly());
    /* Both kernels get the game's per-mount protection. The backend's own
     * immutable state must also reach ext2's mapped-page release path. */
    REQUIRE(mount("/root", "/root", "qemu-persist", MS_REMOUNT | MS_RDONLY, "") == 0);
    int mapped = open("/root/mapped.bin", O_RDONLY);
    int churn = open("/root/a-churn.bin", O_RDONLY);
    int probe = open("/root/z-probe.bin", O_RDONLY);
    REQUIRE(mapped >= 0 && churn >= 0 && probe >= 0);
    long page_size = sysconf(_SC_PAGESIZE);
    REQUIRE(page_size > 0 && page_size <= 65536);
    struct stat device_stat, churn_stat;
    REQUIRE(stat("/dev/vdb", &device_stat) == 0 && fstat(churn, &churn_stat) == 0);
    uint64_t capacity = (uint64_t)device_stat.st_size / 65536;
    if (capacity < 128) capacity = 128;
    if (capacity > 262144) capacity = 262144;
    uint64_t cache_bytes = capacity * 4096;
    REQUIRE((uint64_t)churn_stat.st_size > cache_bytes + (uint64_t)page_size);
    printf("VIRTIO-RO CACHE: device=%lld capacity_bytes=%llu churn=%lld page_size=%ld\n",
           (long long)device_stat.st_size, (unsigned long long)cache_bytes,
           (long long)churn_stat.st_size, page_size);
    unsigned char *area = mmap(NULL, (size_t)page_size, PROT_READ, MAP_SHARED, mapped, 0);
    REQUIRE(area != MAP_FAILED && matches(area, (size_t)page_size, 0, 91));
    REQUIRE(munmap(area, (size_t)page_size) == 0);
    errno = 0;
    int sync_result = fsync(mapped), sync_error = errno;
    printf("VIRTIO-RO SHARED-RELEASE: fsync=%d errno=%d\n", sync_result, sync_error);
    VERIFY(sync_result == 0);

    unsigned char bytes[16384];
    uint64_t offset = 0;
    int read_error = 0;
    for (; offset < (uint64_t)churn_stat.st_size; offset += sizeof bytes) {
        size_t wanted = sizeof bytes;
        if ((uint64_t)churn_stat.st_size - offset < wanted)
            wanted = (size_t)((uint64_t)churn_stat.st_size - offset);
        errno = 0;
        ssize_t got = pread(churn, bytes, wanted, (off_t)offset);
        if (got != (ssize_t)wanted || !matches(bytes, wanted, offset, 7)) {
            read_error = errno;
            break;
        }
    }
    printf("VIRTIO-RO EVICTION: read=%llu expected=%lld errno=%d\n",
           (unsigned long long)offset, (long long)churn_stat.st_size, read_error);
    VERIFY(offset == (uint64_t)churn_stat.st_size);
    errno = 0;
    ssize_t got = pread(probe, bytes, sizeof bytes, 0);
    int probe_error = errno;
    printf("VIRTIO-RO COLD-INODE: read=%lld errno=%d\n", (long long)got, probe_error);
    VERIFY(got == (ssize_t)sizeof bytes && matches(bytes, sizeof bytes, 0, 203));
    errno = 0;
    got = pread(mapped, bytes, sizeof bytes, 0);
    VERIFY(got == (ssize_t)sizeof bytes && matches(bytes, sizeof bytes, 0, 91));

    REQUIRE(mount("/root", "/alias", NULL, MS_BIND, NULL) == 0);
    errno = 0;
    int remounted = mount("/alias", "/alias", NULL, MS_REMOUNT | MS_BIND, NULL);
    int remount_error = errno;
    printf("VIRTIO-RO BIND-REMOUNT: result=%d errno=%d\n", remounted, remount_error);
    VERIFY(remounted == -1 && remount_error == EROFS);
    REQUIRE(mount("/dev/vdb", "/other", "qemu-persist", 0, "") == 0);
    errno = 0;
    remounted = mount("/other", "/other", NULL, MS_REMOUNT, NULL);
    remount_error = errno;
    VERIFY(remounted == -1 && remount_error == EROFS);
    errno = 0;
    int writer = open("/other/mapped.bin", O_WRONLY);
    int open_error = errno;
    VERIFY(writer == -1 && open_error == EROFS);
    if (writer >= 0) close(writer);

    /* An aligned raw write distinguishes early EROFS from the old device's
     * rejected VirtIO request, which reported EIO after submission. */
    int raw = open("/dev/vdb", O_RDWR);
    REQUIRE(raw >= 0);
    memset(bytes, 0, 512);
    errno = 0;
    ssize_t written = pwrite(raw, bytes, 512, 0);
    int write_error = errno;
    printf("VIRTIO-RO RAW-WRITE: written=%lld errno=%d\n", (long long)written, write_error);
    VERIFY(written == -1 && write_error == EROFS);
    REQUIRE(close(raw) == 0 && close(mapped) == 0 && close(churn) == 0 && close(probe) == 0);
    if (failures) {
        printf("VIRTIO-RO FAIL: checks=%d\n", failures);
        return 1;
    }
    puts("VIRTIO-RO PASS");
    for (;;) pause();
}
