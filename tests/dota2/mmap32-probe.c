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

    void *hint = mmap((void *)0x20000001UL, 4096, RW, ANON_PRIVATE | MAP32, -1, 0);
    CHECK(hint == (void *)0x20000000UL);
    *(unsigned char *)hint = 0x6b;
    void *collision = mmap(hint, 4096, RW, ANON_PRIVATE | MAP32, -1, 0);
    CHECK(low(collision, 4096) && collision != hint);
    CHECK(*(unsigned char *)hint == 0x6b);
    void *overflow_hint = mmap((void *)0x7ffff000UL, 8192, RW, ANON_PRIVATE | MAP32, -1, 0);
    CHECK(low(overflow_hint, 8192) && overflow_hint != (void *)0x7ffff000UL);
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
    puts("VINIX-DOTA2-MMAP32-PASS");
    fflush((void *)0);
    return 0;
}
