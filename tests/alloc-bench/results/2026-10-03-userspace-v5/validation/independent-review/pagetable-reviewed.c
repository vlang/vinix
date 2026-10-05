/* SPDX-License-Identifier: BSD-2-Clause */
/* Guest regression for reclaiming sparse page tables and their ancestors.
 * Define VINIX_PAGETABLE_STANDALONE to build a separate executable, or call
 * vinix_pagetable_boundaries() from the core regression's worker. */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <errno.h>
#include <setjmp.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/sysinfo.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef MAP_FIXED_NOREPLACE
#define MAP_FIXED_NOREPLACE 0x100000
#endif

#define PT_CHECK(expression) do {                                      \
    if (!(expression)) {                                               \
        printf("PAGETABLE FAIL line %d: %s (errno=%d)\n",                \
            __LINE__, #expression, errno);                             \
        return 1;                                                      \
    }                                                                  \
} while (0)

static sigjmp_buf pt_jump;
static volatile sig_atomic_t pt_fault;

static void pt_fault_handler(int signal)
{
    pt_fault = signal;
    siglongjmp(pt_jump, 1);
}

static int pt_absent(volatile unsigned char *address)
{
    struct sigaction action = {.sa_handler = pt_fault_handler}, previous;
    sigemptyset(&action.sa_mask);
    PT_CHECK(sigaction(SIGSEGV, &action, &previous) == 0);
    pt_fault = 0;
    if (sigsetjmp(pt_jump, 1) == 0)
        (void)*address;
    PT_CHECK(sigaction(SIGSEGV, &previous, NULL) == 0);
    PT_CHECK(pt_fault == SIGSEGV);
    return 0;
}

static int pt_wait(pid_t child)
{
    int status;
    pid_t waited;
    do {
        waited = waitpid(child, &status, 0);
    } while (waited < 0 && errno == EINTR);
    PT_CHECK(waited == child);
    PT_CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    return 0;
}

static int pt_boundary(uintptr_t boundary, size_t page, int optional)
{
    uintptr_t base = boundary - 4 * page;
    const size_t length = 8 * page;
    const int flags = MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE;
    volatile unsigned char *area = mmap((void *)base, length,
        PROT_READ | PROT_WRITE, flags, -1, 0);
    if (area == MAP_FAILED && optional && errno == EINVAL) {
        printf("PAGETABLE SKIP: boundary=0x%lx beyond user address limit\n",
            (unsigned long)boundary);
        return 0;
    }
    PT_CHECK(area == (void *)base);
    for (size_t i = 0; i < 8; ++i)
        area[i * page] = (unsigned char)(0x30 + i);

    /* No successor at the final slot: the earlier live entries must keep
     * its table alive. Then remove the other side of the boundary while
     * that later sibling still owns present pages. */
    PT_CHECK(munmap((void *)(base + 6 * page), page) == 0);
    PT_CHECK(area[5 * page] == 0x35 && area[7 * page] == 0x37);
    PT_CHECK(munmap((void *)(base + 7 * page), page) == 0);
    PT_CHECK(area[4 * page] == 0x34 && area[5 * page] == 0x35);
    PT_CHECK(pt_absent(area + 6 * page) == 0);
    PT_CHECK(pt_absent(area + 7 * page) == 0);

    /* The child owns its forked pages even when the parent's empty leaf and
     * ancestor tables are reclaimed and the address is reused for zeroes. */
    int ready[2];
    PT_CHECK(pipe(ready) == 0);
    pid_t child = fork();
    PT_CHECK(child >= 0);
    if (child == 0) {
        char token;
        close(ready[1]);
        if (read(ready[0], &token, 1) != 1)
            _exit(1);
        for (size_t i = 0; i < 6; ++i)
            if (area[i * page] != (unsigned char)(0x30 + i))
                _exit(2);
        area[4 * page] = 0x71;
        _exit(area[4 * page] == 0x71 ? 0 : 3);
    }
    PT_CHECK(close(ready[0]) == 0);
    /* Make an interior hole, then finish clearing that side in ascending
     * order. These removals exercise both the successor and fallback paths. */
    PT_CHECK(munmap((void *)(base + page), page) == 0);
    PT_CHECK(area[0] == 0x30 && area[2 * page] == 0x32);
    PT_CHECK(munmap((void *)base, page) == 0);
    PT_CHECK(munmap((void *)(base + 2 * page), 2 * page) == 0);
    PT_CHECK(area[4 * page] == 0x34 && area[5 * page] == 0x35);
    PT_CHECK(pt_absent(area + 3 * page) == 0);
    void *replacement = mmap((void *)base, 4 * page,
        PROT_READ | PROT_WRITE, flags, -1, 0);
    PT_CHECK(replacement == (void *)base);
    for (size_t i = 0; i < 4; ++i) {
        PT_CHECK(area[i * page] == 0);
        area[i * page] = (unsigned char)(0x80 + i);
    }
    PT_CHECK(write(ready[1], "x", 1) == 1);
    PT_CHECK(close(ready[1]) == 0);
    PT_CHECK(pt_wait(child) == 0);
    PT_CHECK(area[4 * page] == 0x34 && area[5 * page] == 0x35);
    PT_CHECK(munmap((void *)base, length) == 0);
    PT_CHECK(pt_absent(area) == 0);
    PT_CHECK(pt_absent(area + 5 * page) == 0);

    /* Reuse the completely detached tree repeatedly with contiguous pages.
     * Leave the final page resident while removing all its predecessors. */
    for (unsigned round = 0; round < 4; ++round) {
        area = mmap((void *)base, length, PROT_READ | PROT_WRITE,
            flags, -1, 0);
        PT_CHECK(area == (void *)base);
        for (size_t i = 0; i < 8; ++i) {
            PT_CHECK(area[i * page] == 0);
            area[i * page] = (unsigned char)(0xa0 + i);
        }
        PT_CHECK(munmap((void *)base, 7 * page) == 0);
        PT_CHECK(area[7 * page] == 0xa7);
        PT_CHECK(munmap((void *)(base + 7 * page), page) == 0);
    }
    printf("PAGETABLE PASS: boundary=0x%lx page=%zu\n",
        (unsigned long)boundary, page);
    return 0;
}

int vinix_pagetable_boundaries(void)
{
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    PT_CHECK(page == 4096 || page == 16384);
    struct sysinfo before, after;
    PT_CHECK(sysinfo(&before) == 0);
    if (page == 4096) {
        PT_CHECK(pt_boundary(UINT64_C(64) << 20, page, 0) == 0);
        PT_CHECK(pt_boundary(UINT64_C(32) << 30, page, 0) == 0);
        PT_CHECK(pt_boundary(UINT64_C(4) << 40, page, 0) == 0);
        PT_CHECK(pt_boundary(UINT64_C(1) << 48, page, 1) == 0);
    } else {
        /* 16 KiB tables have 2,048 entries: 32 MiB leaves, 64 GiB parents. */
        PT_CHECK(pt_boundary(UINT64_C(128) << 20, page, 0) == 0);
        PT_CHECK(pt_boundary(UINT64_C(512) << 30, page, 0) == 0);
    }
    PT_CHECK(sysinfo(&after) == 0);
    unsigned long unit = after.mem_unit ? after.mem_unit : 1;
    PT_CHECK(after.freeram * unit + 1024UL * 1024 >=
        before.freeram * (before.mem_unit ? before.mem_unit : 1));
    puts("PAGETABLE CHECK: PASS sparse tables, sibling survival, holes, COW and reuse");
    return 0;
}

#ifdef VINIX_PAGETABLE_STANDALONE
int main(void)
{
    return vinix_pagetable_boundaries();
}
#endif
