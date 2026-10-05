// SPDX-License-Identifier: GPL-2.0-or-later
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { printf("BIG IO FAIL: line=%d errno=%d\n", __LINE__, errno); return 1; } } while (0)
static unsigned char payload[65536];
static char slabinfo[65536];

static int large_pages(unsigned long long *pages)
{
    int fd = open("/proc/slabinfo", O_RDONLY);
    CHECK(fd >= 0);
    ssize_t n = read(fd, slabinfo, sizeof(slabinfo) - 1);
    CHECK(n > 0 && close(fd) == 0);
    slabinfo[n] = 0;
    char *large = strstr(slabinfo, "large - - ");
    CHECK(large && sscanf(large, "large - - %llu", pages) == 1);
    return 0;
}

int main(void)
{
    int zero = open("/dev/zero", O_RDONLY);
    int sink = open("/dev/null", O_WRONLY);
    CHECK(zero >= 0 && sink >= 0);
    // Warm backend state before snapshotting allocator accounting.
    CHECK(read(zero, payload, sizeof(payload)) == sizeof(payload));
    CHECK(write(sink, payload, sizeof(payload)) == sizeof(payload));
    unsigned long long before, after;
    // Let the boot thread and deferred startup storage finish retiring.
    for (int warm = 0; warm < 3; ++warm) CHECK(large_pages(&before) == 0);
    CHECK(sleep(7) == 0);
    CHECK(large_pages(&before) == 0);
    for (int round = 0; round < 300; ++round) {
        memset(payload, 0x5a, sizeof(payload));
        CHECK(read(zero, payload, sizeof(payload)) == sizeof(payload));
        for (unsigned i = 0; i < sizeof(payload); ++i) CHECK(payload[i] == 0);
        CHECK(write(sink, payload, sizeof(payload)) == sizeof(payload));
        errno = 0;
        CHECK(read(zero, (void *)(uintptr_t)1, sizeof(payload)) == -1 && errno == EFAULT);
        errno = 0;
        CHECK(write(sink, (void *)(uintptr_t)1, sizeof(payload)) == -1 && errno == EFAULT);
    }
    CHECK(large_pages(&after) == 0);
    printf("BIG IO MEASURE: before=%llu after=%llu\n", before, after);
    CHECK(after == before);
    CHECK(close(zero) == 0 && close(sink) == 0);
    printf("BIG IO PASS: 300 large reads writes and failed read/write-copy frees; pages=%llu\n", after);
    fflush(stdout);
    for (;;) pause();
}
