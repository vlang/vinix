#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/statfs.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { printf("READAHEAD FAIL line=%d errno=%d FAIL END\n", __LINE__, errno); for (;;) pause(); } } while (0)
enum { FILE_BYTES = 384 * 1024 + 137 };
static unsigned char buffer[16384];

static long metric(const char *name)
{
    FILE *f = fopen("/proc/meminfo", "r"); CHECK(f != NULL);
    char line[256], key[64]; long value, found = -1;
    while (fgets(line, sizeof line, f))
        if (sscanf(line, "%63s %ld", key, &value) == 2 && !strcmp(key, name)) found = value;
    fclose(f); CHECK(found >= 0); return found;
}

static void bytes(int fd, off_t offset, size_t count, int positional)
{
    CHECK(count <= sizeof buffer);
    ssize_t n = positional ? pread(fd, buffer, count, offset) : read(fd, buffer, count);
    CHECK(n == (ssize_t)count);
    for (size_t i = 0; i < count; i++) CHECK(buffer[i] == (unsigned char)((offset + (off_t)i) % 251));
}

static void cold(int fd, int advice)
{
    CHECK(posix_fadvise(fd, 0, 0, POSIX_FADV_DONTNEED) == 0);
    CHECK(posix_fadvise(fd, 0, 0, advice) == 0);
    CHECK(lseek(fd, 0, SEEK_SET) == 0);
}

static long window(int fd, int advice, int positional)
{
    cold(fd, advice);
    long before = metric("Cached:");
    bytes(fd, 0, 1024, positional);
    long first = metric("Cached:");
    bytes(fd, 1024, 1024, positional);
    long second = metric("Cached:");
    CHECK(first - before < 32);
    printf("READAHEAD advice=%d positional=%d first_kb=%ld second_kb=%ld\n", advice, positional, first - before, second - first);
    if (positional) CHECK(lseek(fd, 0, SEEK_CUR) == 0);
    return second - first;
}

int main(void)
{
    setbuf(stdout, NULL);
#ifdef __x86_64__
    int serial = open("/dev/com1", O_WRONLY | O_NOCTTY);
    if (serial >= 0) { dup2(serial, 1); dup2(serial, 2); close(serial); }
#endif
    puts("READAHEAD START");
    struct statfs filesystem;
    CHECK(statfs("/root", &filesystem) == 0 && filesystem.f_type == 0xef53);
    int fd = open("/root/readahead-data", O_CREAT | O_TRUNC | O_RDWR, 0600); CHECK(fd >= 0);
    for (off_t offset = 0; offset < FILE_BYTES;) {
        size_t amount = FILE_BYTES - offset < (off_t)sizeof buffer ? (size_t)(FILE_BYTES - offset) : sizeof buffer;
        for (size_t i = 0; i < amount; i++) buffer[i] = (unsigned char)((offset + (off_t)i) % 251);
        CHECK(write(fd, buffer, amount) == (ssize_t)amount); offset += amount;
    }
    CHECK(fsync(fd) == 0);
    CHECK(window(fd, POSIX_FADV_RANDOM, 0) < 32);
    long normal = window(fd, POSIX_FADV_NORMAL, 0); CHECK(normal >= 64);
    long sequential = window(fd, POSIX_FADV_SEQUENTIAL, 0); CHECK(sequential >= normal + 64);
    CHECK(window(fd, POSIX_FADV_NORMAL, 1) >= 64);
    cold(fd, POSIX_FADV_RANDOM);
    long before = metric("Cached:");
    CHECK(posix_fadvise(fd, 0, 128 * 1024, POSIX_FADV_WILLNEED) == 0);
    CHECK(metric("Cached:") >= before + 64);
    puts("READAHEAD PASS: sequential windows, random suppression and explicit hints");

    cold(fd, POSIX_FADV_RANDOM);
    int alias = dup(fd); CHECK(alias >= 0);
    CHECK(posix_fadvise(alias, 0, 0, POSIX_FADV_NORMAL) == 0);
    bytes(fd, 0, 1024, 0); before = metric("Cached:");
    bytes(alias, 1024, 1024, 0); CHECK(metric("Cached:") >= before + 64);
    CHECK(lseek(fd, 0, SEEK_CUR) == 2048);
    CHECK(close(alias) == 0);
    before = metric("Cached:");
    CHECK(lseek(fd, 320 * 1024, SEEK_SET) == 320 * 1024);
    bytes(fd, 320 * 1024, 1024, 0); CHECK(metric("Cached:") - before < 32);
    CHECK(posix_fadvise(fd, 0, 0, POSIX_FADV_RANDOM) == 0);
    for (off_t offset = 0; offset < FILE_BYTES;) {
        size_t amount = FILE_BYTES - offset < (off_t)sizeof buffer ? (size_t)(FILE_BYTES - offset) : sizeof buffer;
        bytes(fd, offset, amount, 1); offset += amount;
    }
    CHECK(pread(fd, buffer, sizeof buffer, FILE_BYTES) == 0);
    puts("READAHEAD PASS: shared descriptions, offset resets and exact tail bytes");

    /* Warm metadata and descriptor caches, then measure retained slab after
     * discarding speculative data. Each cycle allocates clustered fill pages. */
    for (int round = 0; round < 2; round++) {
        cold(fd, POSIX_FADV_NORMAL);
        long slab = metric("Slab:");
        for (int i = 0; i < 200; i++) {
            cold(fd, POSIX_FADV_NORMAL);
            bytes(fd, 0, 1024, 0); bytes(fd, 1024, 1024, 0);
        }
        cold(fd, POSIX_FADV_NORMAL);
        long after = metric("Slab:");
        printf("READAHEAD retained round=%d slab_before_kb=%ld slab_after_kb=%ld\n", round, slab, after);
        if (round == 1) CHECK(after <= slab + 16);
    }
    CHECK(close(fd) == 0);
    puts("READAHEAD DONE pass ino=0");
    for (;;) pause();
}
