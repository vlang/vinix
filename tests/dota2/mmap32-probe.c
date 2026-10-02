/* SPDX-License-Identifier: GPL-2.0-or-later
 * Exercise the x86 Linux mmap contract through the actual Vinix translator.
 * Link directly to the private glibc runtime without cross-development headers.
 */
extern void *mmap(void *, unsigned long, int, int, int, long);
extern void *mmap64(void *, unsigned long, int, int, int, long);
extern int munmap(void *, unsigned long);
extern int *__errno_location(void);
extern int printf(const char *, ...);
extern int puts(const char *);
extern int fflush(void *);

__asm__(".text\n.global _start\n_start:\n"
        "xor %ebp,%ebp\nmov %rdx,%r9\npop %rsi\nmov %rsp,%rdx\n"
        "and $-16,%rsp\npush %rax\npush %rsp\nxor %r8d,%r8d\nxor %ecx,%ecx\n"
        "lea main(%rip),%rdi\ncall *__libc_start_main@GOTPCREL(%rip)\nhlt\n");

#define FAILED ((void *)-1)
#define ANON_PRIVATE (0x20 | 0x02)
#define MAP32 0x40
#define FIXED 0x10
#define NOREPLACE 0x100000
#define RW 3
#define CHECK(condition) do { if (!(condition)) { \
    printf("VINIX-DOTA2-MMAP32-FAIL: line=%d errno=%d\n", __LINE__, *__errno_location()); \
    fflush((void *)0); return 1; \
} } while (0)

static int low(void *value, unsigned long length) {
    unsigned long start = (unsigned long)value;
    return value != FAILED && start >= 0x10000UL && start <= 0x80000000UL - length;
}

static int separate(void *left, unsigned long left_length,
                    void *right, unsigned long right_length) {
    unsigned long a = (unsigned long)left, b = (unsigned long)right;
    return a + left_length <= b || b + right_length <= a;
}

int main(void) {
    puts("VINIX-DOTA2-MMAP32-START");
    CHECK(mmap((void *)0, 0, RW, ANON_PRIVATE | MAP32, -1, 0) == FAILED);
    CHECK(*__errno_location() == 22);
    CHECK(mmap((void *)0, ~0UL, RW, ANON_PRIVATE | MAP32, -1, 0) == FAILED);
    CHECK(*__errno_location() == 12);
    CHECK(mmap((void *)0x10000UL, 0x80000000UL, 0, ANON_PRIVATE | MAP32, -1, 0) == FAILED);
    CHECK(*__errno_location() == 12);
    CHECK(mmap64((void *)0, 0x80000000UL, 0, ANON_PRIVATE | MAP32, -1, 0) == FAILED);
    CHECK(*__errno_location() == 12);

    void *first = mmap((void *)0, 4096, RW, ANON_PRIVATE | MAP32, -1, 0);
    CHECK(low(first, 4096));
    *(unsigned char *)first = 0x5a;
    void *second = mmap64((void *)0, 4096, RW, ANON_PRIVATE | MAP32, -1, 0);
    CHECK(low(second, 4096) && second != first);
    *(unsigned char *)second = 0x37;
    CHECK(*(unsigned char *)first == 0x5a);
    /* A second guest page in the same host page must not weaken NOREPLACE.
     * QEMU 9.1's unreserved partial-host-page path otherwise aliases first.
     */
    CHECK(mmap(first, 4096, RW, ANON_PRIVATE | NOREPLACE, -1, 0) == FAILED);
    CHECK(*__errno_location() == 17 && *(unsigned char *)first == 0x5a);
    CHECK(mmap64(second, 4096, RW, ANON_PRIVATE | NOREPLACE, -1, 0) == FAILED);
    CHECK(*__errno_location() == 17 && *(unsigned char *)second == 0x37);

    void *hint = mmap((void *)0x20000001UL, 4096, RW, ANON_PRIVATE | MAP32, -1, 0);
    CHECK(hint == (void *)0x20000000UL);
    *(unsigned char *)hint = 0x6b;
    void *collision = mmap(hint, 4096, RW, ANON_PRIVATE | MAP32, -1, 0);
    CHECK(low(collision, 4096) && collision != hint);
    CHECK(separate(collision, 4096, first, 4096));
    CHECK(separate(collision, 4096, second, 4096));
    *(unsigned char *)collision = 0x42;
    CHECK(*(unsigned char *)hint == 0x6b);
    void *overflow_hint = mmap((void *)0x7ffff000UL, 8192, RW, ANON_PRIVATE | MAP32, -1, 0);
    CHECK(low(overflow_hint, 8192) && overflow_hint != (void *)0x7ffff000UL);
    CHECK(separate(overflow_hint, 8192, first, 4096));
    CHECK(separate(overflow_hint, 8192, second, 4096));
    CHECK(separate(overflow_hint, 8192, hint, 4096));
    CHECK(separate(overflow_hint, 8192, collision, 4096));
    *(unsigned char *)overflow_hint = 0x95;
    *((unsigned char *)overflow_hint + 8191) = 0x28;
    CHECK(*(unsigned char *)first == 0x5a && *(unsigned char *)second == 0x37);
    CHECK(*(unsigned char *)hint == 0x6b && *(unsigned char *)collision == 0x42);
    void *boundary = mmap((void *)0x7fff0000UL, 65536, RW, ANON_PRIVATE | MAP32, -1, 0);
    CHECK(boundary == (void *)0x7fff0000UL);

    /* Both forms of fixed addressing ignore MAP_32BIT, without weakening
     * NOREPLACE's collision protection for callers that explicitly request it.
     */
    void *high = mmap((void *)0x90000000UL, 4096, RW, ANON_PRIVATE | NOREPLACE | MAP32, -1, 0);
    CHECK(high == (void *)0x90000000UL);
    *(unsigned char *)high = 0x79;
    CHECK(mmap(high, 4096, RW, ANON_PRIVATE | NOREPLACE | MAP32, -1, 0) == FAILED);
    CHECK(*__errno_location() == 17 && *(unsigned char *)high == 0x79);
    CHECK(mmap(high, 4096, RW, ANON_PRIVATE | FIXED | MAP32, -1, 0) == high);
    CHECK(*(unsigned char *)high == 0);

    CHECK(munmap(first, 4096) == 0);
    CHECK(munmap(second, 4096) == 0);
    CHECK(munmap(hint, 4096) == 0);
    CHECK(munmap(collision, 4096) == 0);
    CHECK(munmap(overflow_hint, 8192) == 0);
    CHECK(munmap(boundary, 65536) == 0);
    CHECK(munmap(high, 4096) == 0);

    /* The real engine reserves large low regions before loading its modules.
     * Find both the tail gap and a page-sized hole without replacing the
     * existing reservation, then reject a completely occupied search window.
     */
    void *reserved = mmap((void *)0x40000000UL, 0x20000000UL, 0,
                          ANON_PRIVATE | NOREPLACE, -1, 0);
    CHECK(reserved == (void *)0x40000000UL);
    void *tail = mmap((void *)0, 0x08000000UL, 0, ANON_PRIVATE | MAP32, -1, 0);
    CHECK(low(tail, 0x08000000UL) && (unsigned long)tail >= 0x60000000UL);
    CHECK(munmap((void *)0x48000000UL, 4096) == 0);
    void *hole = mmap((void *)0, 4096, RW, ANON_PRIVATE | MAP32, -1, 0);
    CHECK(hole == (void *)0x48000000UL);
    *(unsigned char *)hole = 0x81;
    CHECK(munmap(reserved, 0x20000000UL) == 0);
    CHECK(munmap(tail, 0x08000000UL) == 0);
    void *full = mmap((void *)0x40000000UL, 0x40000000UL, 0,
                      ANON_PRIVATE | NOREPLACE, -1, 0);
    CHECK(full == (void *)0x40000000UL);
    CHECK(mmap((void *)0, 4096, RW, ANON_PRIVATE | MAP32, -1, 0) == FAILED);
    CHECK(*__errno_location() == 12);
    CHECK(munmap(full, 0x40000000UL) == 0);
    puts("VINIX-DOTA2-MMAP32-PASS");
    fflush((void *)0);
    return 0;
}
