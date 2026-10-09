/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Test-only native guarded stack. Never included in the production runner. */
#ifndef VINIX_IOS_STACK_PROBE_TEST_H
#define VINIX_IOS_STACK_PROBE_TEST_H
#ifdef IOS_STACK_PROBE_TEST
#include <sys/mman.h>
#include <unistd.h>
#include <stdint.h>
void ios_stack_probe_guard_call(void *stack, uint64_t count);
static int ios_stack_probe_guard_test(int fault) {
    long page = sysconf(_SC_PAGESIZE);
    if (page < 4096) return -1;
    size_t length = (size_t)page * 3;
    unsigned char *region = mmap(NULL, length, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (region == MAP_FAILED) return -1;
    int result = -1;
    if (!mprotect(region + page, (size_t)page * 2, PROT_READ | PROT_WRITE)) {
        uint64_t sizes[] = {0, 1, 4095, 4096, 4097, (uint64_t)page - 1,
            (uint64_t)page, (uint64_t)page + 1, (uint64_t)page * 2};
        if (fault) {
            /* One byte enters the inaccessible guard page and must fault. */
            ios_stack_probe_guard_call(region + length, (uint64_t)page * 2 + 1);
        } else {
            for (size_t i = 0; i < sizeof sizes / sizeof sizes[0]; ++i)
                ios_stack_probe_guard_call(region + length, sizes[i]);
        }
        result = 0;
    }
    if (munmap(region, length)) return -1;
    return result;
}
#else
static int ios_stack_probe_guard_test(int fault) { (void)fault; return -1; }
#endif
#endif
