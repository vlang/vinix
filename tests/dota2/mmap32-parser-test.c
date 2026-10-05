/* SPDX-License-Identifier: GPL-2.0-or-later
 * Compile with clang -Wall -Wextra -Werror to exercise the actual shim parser.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define open fixture_open
#define read fixture_read
#define close fixture_close
#define __errno_location fixture_errno
#define dlsym fixture_dlsym
#define munmap fixture_munmap
#define mmap fixture_mmap
#define mmap64 fixture_mmap64
#include "../../build-support/dota2/mmap32.c"
#undef dlsym
#undef munmap
#undef mmap
#undef mmap64
static int dota_maps_gap(unsigned long start, unsigned long length, unsigned long *output) {
    return next_gap(start < LOW_FALLBACK ? LOW_FALLBACK : start, length, LOW_END, output);
}
#undef open
#undef read
#undef close
#undef __errno_location

void *fixture_dlsym(void *handle, const char *name) {
    (void)handle; (void)name; abort();
}
int fixture_munmap(void *address, unsigned long length) {
    (void)address; (void)length; abort();
}

static const char *text;
static unsigned long position, size, chunk;
static int opens, closes, reads, error, open_fail, fault_read, fault_code;

int fixture_open(const char *path, int flags, ...) {
    if (strcmp(path, "/proc/self/maps") || flags != 0x80000) abort();
    ++opens;
    return open_fail ? -1 : 17;
}

long fixture_read(int fd, void *data, unsigned long count) {
    if (fd != 17) abort();
    ++reads;
    if (reads == fault_read) {
        error = fault_code;
        return -1;
    }
    if (count > chunk) count = chunk;
    if (count > size - position) count = size - position;
    memcpy(data, text + position, count);
    position += count;
    return (long)count;
}

int fixture_close(int fd) {
    if (fd != 17) abort();
    ++closes;
    return 0;
}

int *fixture_errno(void) { return &error; }

static void reset(const char *data, unsigned long limit) {
    text = data;
    position = 0;
    size = strlen(data);
    chunk = limit;
    opens = closes = reads = error = open_fail = fault_read = fault_code = 0;
}

static int count;

static void check(const char *data, unsigned long start, unsigned long length,
                  int expected, unsigned long address) {
    for (unsigned long split = 1; split <= 257; ++split) {
        reset(data, split);
        unsigned long output = 0x12345;
        int result = dota_maps_gap(start, length, &output);
        if (result != expected || (result == 1 ? output != address : output != 0x12345) ||
            opens != 1 || closes != 1) {
            fprintf(stderr, "case %d split %lu: got %d/%lx expected %d/%lx opens%d closes%d\n",
                    count, split, result, output, expected, address, opens, closes);
            abort();
        }
    }
    ++count;
}

int main(void) {
    check("00000000-40000000 ---p 0 00:00 0\n", 0, 4096, 1, 0x40000000);
    check("40000000-40001000 rw-p 0 00:00 0", 0, 4096, 1, 0x40001000);
    check("40000000-50000000 ---p 0 00:00 0\n50000000-60000000 ---p 0 00:00 0\n", 0, 4096, 1, 0x60000000);
    check("40000000-40002000 rw-p 0 00:00 0\n40001000-40004000 rw-p 0 00:00 0\n", 0, 4096, 1, 0x40004000);
    check("40000000-40001000 rw-p 0 00:00 0\n40000000-40008000 rw-p 0 00:00 0\n", 0, 4096, 1, 0x40008000);
    check("40000000-70000000 ---p 0 00:00 0\n", 0, 0x10000000, 1, 0x70000000);
    check("40000000-70000000 ---p 0 00:00 0\n", 0, 0x10000001, 0, 0);
    check("40000000-80000000 ---p 0 00:00 0\n", 0, 4096, 0, 0);
    check("40000000-40000001 rw-p 0 00:00 0\n", 0, 4096, 1, 0x40001000);
    check("50000000-58000000 rw-p 0 00:00 0\n", 0, 0x20000000, 1, 0x58000000);
    check("40000000-40001000 rw-p 0 00:00 0\n", 0x40003001, 1, 1, 0x40004000);
    check("0000000140000000-0000000180000000 rw-p 0 00:00 0\n", 0, 4096, 1, 0x40000000);
    check("40000000-FFFFFFFFFFFFFFFF rw-p 0 00:00 0\n", 0, 4096, 0, 0);
    check("", 0, 4096, -1, 0);
    check("\n\n", 0, 4096, -1, 0);
    check("50000000-50001000 rw-p 0 00:00 0\n40000000-40001000 rw-p 0 00:00 0\n", 0, 4096, -1, 0);
    check("40000000-40000000 rw-p 0 00:00 0\n", 0, 4096, -1, 0);
    check("40001000-40000000 rw-p 0 00:00 0\n", 0, 4096, -1, 0);
    check("10000000000000000-10000000000001000 rw-p 0 00:00 0\n", 0, 4096, -1, 0);
    check("40000000-10000000000000000 rw-p 0 00:00 0\n", 0, 4096, -1, 0);
    check("40000000-40001000\n", 0, 4096, -1, 0);
    check("40000000-40001000", 0, 4096, -1, 0);
    check("x40000000-40001000 rw-p 0 00:00 0\n", 0, 4096, -1, 0);
    char *large = malloc(16384);
    strcpy(large, "40000000-40001000 rw-p 0 00:00 0 /");
    unsigned long used = strlen(large);
    memset(large + used, 'a', 8192);
    strcpy(large + used + 8192, "\n40001000-40002000 rw-p 0 00:00 0\n");
    check(large, 0, 4096, 1, 0x40002000);
    free(large);

    reset("40000000-40001000 rw-p 0 00:00 0\n", 1);
    fault_read = 7;
    fault_code = 4;
    unsigned long output = 0;
    if (dota_maps_gap(0, 4096, &output) != 1 || output != 0x40001000 || opens != 1 || closes != 1) abort();
    reset("40000000-40001000 rw-p 0 00:00 0\n", 1);
    fault_read = 7;
    fault_code = 5;
    if (dota_maps_gap(0, 4096, &output) != -1 || opens != 1 || closes != 1) abort();
    reset("", 1);
    open_fail = 1;
    if (dota_maps_gap(0, 4096, &output) != -1 || opens != 1 || closes || reads) abort();
    reset("", 1);
    if (dota_maps_gap(0, 0, &output) != -1 || dota_maps_gap(0, ~0UL, &output) != -1 ||
        dota_maps_gap(0, 4096, (void *)0) != -1 || dota_maps_gap(0x80000000, 4096, &output) != 0 ||
        dota_maps_gap(0, 0x40000001, &output) != 0 || opens || closes || reads) abort();
    reset("00010000-40000000 ---p 0 00:00 0\n", 1);
    if (next_gap(0x40000000, 4096, 0x40001000, &output) != 1 || output != 0x40000000 || closes != 1) abort();
    reset("00010000-40000000 ---p 0 00:00 0\n", 1);
    if (next_gap(0x40000001, 4096, 0x40001000, &output) != 0 || closes || opens) abort();
    reset("", 1);
    if (next_gap(0, 4096, ~0UL, &output) != -1 || next_gap(0x40000000, 4096, 0x10000, &output) != 0 || opens) abort();
    printf("mmap32 maps parser: %d cases x257 read sizes plus I/O/argument cases passed\n", count);
    return 0;
}
