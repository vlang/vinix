/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_FORMAT_TEST_H
#define VINIX_LINUXKPI_FORMAT_TEST_H
#include <vinix/format.h>
#include <linux/ioport.h>
#include <linux/printk.h>

/* Golden strings below preserve Linux 6.6.157 lib/test_printf.c semantics;
 * Linux intentionally differs from libc for zero and omitted precision.
 * Every ordinary vector is checked at every truncation boundary, size zero,
 * and size one, with both sides of the destination guarded. */
static void format_test_golden_bytes(const char *expected, size_t length, const char *fmt, ...)
{
    assert(length < 480);
    va_list args;
    va_start(args, fmt);
    for (size_t size = 0; size <= length + 2; size++) {
        unsigned char guard[512];
        memset(guard, 0xa5, sizeof(guard));
        unsigned int status = ~0U;
        va_list copy;
        va_copy(copy, args);
        int count = vinix_linuxkpi_vformat((char *)guard + 8, size, fmt, copy, &status);
        va_end(copy);
        assert(count == (int)length);
        assert(status == (length && length >= size ? VINIX_FORMAT_TRUNCATED : 0));
        for (size_t i = 0; i < 8; i++) assert(guard[i] == 0xa5);
        if (size) {
            size_t retained = length < size ? length : size - 1;
            assert(!memcmp(guard + 8, expected, retained));
            assert(guard[8 + retained] == 0);
        }
        for (size_t i = 8 + size; i < sizeof(guard); i++) assert(guard[i] == 0xa5);
    }
    va_end(args);
}
#define FORMAT_GOLDEN(expected, fmt, ...) \
    format_test_golden_bytes(expected, sizeof(expected) - 1, fmt, ##__VA_ARGS__)

static void format_test_numbers_strings(void)
{
    FORMAT_GOLDEN("", "");
    FORMAT_GOLDEN("100%", "100%%");
    FORMAT_GOLDEN("xxx%yyy", "xxx%cyyy", '%');
    FORMAT_GOLDEN("xxx\0yyy", "xxx%cyyy", '\0');
    FORMAT_GOLDEN("0x1234abcd  ", "%#-12x", 0x1234abcdU);
    FORMAT_GOLDEN("  0x1234abcd", "%#12x", 0x1234abcdU);
    FORMAT_GOLDEN("0|001| 12|+123| 1234|-123|-1234",
        "%d|%03d|%3d|%+d|% d|%+d|% d", 0, 1, 12, 123, 1234, -123, -1234);
    FORMAT_GOLDEN("0|1|1|128|255", "%hhu|%hhu|%hhu|%hhu|%hhu", 0, 1, 257, 128, -1);
    FORMAT_GOLDEN("0|1|1|-128|-1", "%hhd|%hhd|%hhd|%hhd|%hhd", 0, 1, 257, 128, -1);
    FORMAT_GOLDEN("2015122420151225", "%ho%ho%#ho", 1037, 5282, -11627);
    FORMAT_GOLDEN("00|0|0|0|0", "%.2d|%.1d|%.0d|%.*d|%1.0d", 0, 0, 0, 0, 0, 0);
    FORMAT_GOLDEN("0x0|0|0X0", "%#x|%#o|%#X", 0U, 0U, 0U);
    FORMAT_GOLDEN("-9223372036854775808|18446744073709551615",
        "%lld|%llu", (long long)LLONG_MIN, (unsigned long long)ULLONG_MAX);
    FORMAT_GOLDEN("-2147483648|4294967295|-32768|65535|-128|255",
        "%d|%u|%hd|%hu|%hhd|%hhu", INT_MIN, UINT_MAX, -32768, 65535, -128, 255);
    FORMAT_GOLDEN("-17|17|-18|18|-19|19", "%ld|%lu|%zd|%zu|%td|%tx",
        -17L, 17UL, (ssize_t)-18, (size_t)18, (ptrdiff_t)-19, (ptrdiff_t)0x19);
    FORMAT_GOLDEN("-00042|0000002a|0000002A", "%06d|%08x|%08X", -42, 42U, 42U);
    FORMAT_GOLDEN("00000042", "%08.4d", 42);
    FORMAT_GOLDEN("1|s", "%*d|%*s", -(1 << 23), 1, -(1 << 23), "s");
    FORMAT_GOLDEN("  +0042|0042  ", "%+7.4d|%-6.4d", 42, 42);
    FORMAT_GOLDEN("ABCD|abc|123", "%s|%.3s|%.*s", "ABCD", "abcdef", 3, "123456");
    FORMAT_GOLDEN("1  |  2|3  |  4|5  ", "%-3s|%3s|%-*s|%*s|%*s", "1", "2", 3, "3", 3, "4", -3, "5");
    FORMAT_GOLDEN("1234      ", "%-10.4s", "123456");
    FORMAT_GOLDEN("      1234", "%10.4s", "123456");
    FORMAT_GOLDEN("    ", "%4.*s", -5, "123456");
    FORMAT_GOLDEN("123456", "%.s", "123456");
    FORMAT_GOLDEN("a||", "%.s|%.0s|%.*s", "a", "b", 0, "c");
    FORMAT_GOLDEN("a  |   |   ", "%-3.s|%-3.0s|%-3.*s", "a", "b", 0, "c");
    FORMAT_GOLDEN("  Q|Q  ", "%3c|%-3c", 'Q', 'Q');
    FORMAT_GOLDEN(" 17", "% i", 17);
    FORMAT_GOLDEN("(null)|(efault)|(efa", "%s|%s|%.4s", NULL, (char *)1, (char *)1);
}

static void format_test_pointer_values(void)
{
    FORMAT_GOLDEN("(____ptrval____)|(____ptrval____)", "%p|%pK", (void *)0xab, (void *)0x1234);
    FORMAT_GOLDEN("0000000000000000|fffffffffffffff5", "%p|%p", NULL, ERR_PTR(-11));
    FORMAT_GOLDEN("00000000000000ab|              ab", "%px|%16px", (void *)0xab, (void *)0xab);
    FORMAT_GOLDEN("0xffff0123456789ab|0xffff0123456789ab", "%pS|%ps", (void *)0xffff0123456789abUL, (void *)0xffff0123456789abUL);
    FORMAT_GOLDEN("-1234|-11|     -11|-11     ", "%pe|%pe|%8pe|%-8pe", ERR_PTR(-1234), ERR_PTR(-11), ERR_PTR(-11), ERR_PTR(-11));
    FORMAT_GOLDEN("(____ptrval____)", "%pe", (void *)0x1234);
    phys_addr_t physical = 0x1234;
    dma_addr_t dma = 0x123456789abcdef0ULL;
    FORMAT_GOLDEN("0x0000000000001234|0x123456789abcdef0", "%pa|%pad", &physical, &dma);
    FORMAT_GOLDEN("(null)|(efault)|(efault)", "%pa|%pad|%p4cc", NULL, (void *)1, ERR_PTR(-EIO));
    u32 fourcc = 0x3231564e;
    FORMAT_GOLDEN("NV12 little-endian (0x3231564e)", "%p4cc", &fourcc);
    fourcc = 0xb231564e;
    FORMAT_GOLDEN("NV12 big-endian (0xb231564e)", "%p4cc", &fourcc);
    fourcc = 0x10111213;
    FORMAT_GOLDEN(".... little-endian (0x10111213)", "%p4cc", &fourcc);
    fourcc = 0x20303159;
    FORMAT_GOLDEN("Y10  little-endian (0x20303159)", "%p4cc", &fourcc);
    unsigned char unaligned[sizeof(fourcc) + 1];
    memcpy(unaligned + 1, &fourcc, sizeof(fourcc));
    FORMAT_GOLDEN("Y10  little-endian (0x20303159)", "%p4cc", unaligned + 1);
}

static void format_test_bytes_bitmaps_resources(void)
{
    const unsigned char bytes[3] = {0xc0, 0xff, 0xee};
    FORMAT_GOLDEN("c0 ff ee|c0:ff:ee|c0-ff-ee|c0ffee", "%3ph|%3phC|%3phD|%3phN", bytes, bytes, bytes, bytes);
    FORMAT_GOLDEN("c0 ff ee|c0:ff:ee|c0-ff-ee|c0ffee", "%*ph|%*phC|%*phD|%*phN", 3, bytes, 3, bytes, 3, bytes, 3, bytes);
    FORMAT_GOLDEN("|c0", "%*ph|%ph", 0, NULL, bytes);
    FORMAT_GOLDEN("c0", "%*ph", -(1 << 23), bytes);
    FORMAT_GOLDEN("(null)|(efault)", "%ph|%ph", NULL, (void *)1);
    unsigned char long_bytes[65];
    for (unsigned int i = 0; i < ARRAY_SIZE(long_bytes); i++) long_bytes[i] = i;
    FORMAT_GOLDEN("00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f "
        "10 11 12 13 14 15 16 17 18 19 1a 1b 1c 1d 1e 1f "
        "20 21 22 23 24 25 26 27 28 29 2a 2b 2c 2d 2e 2f "
        "30 31 32 33 34 35 36 37 38 39 3a 3b 3c 3d 3e 3f",
        "%*ph", 65, long_bytes);
    unsigned long bits[2] = {0,0};
    FORMAT_GOLDEN("|", "%*pb|%*pbl", -(1 << 23), bits, -(1 << 23), bits);
    FORMAT_GOLDEN("00000|00000", "%20pb|%*pb", bits, 20, bits);
    FORMAT_GOLDEN("|", "%20pbl|%*pbl", bits, 20, bits);
    bits[0] = 0xa28ac;
    FORMAT_GOLDEN("a28ac|a28ac", "%20pb|%*pb", bits, 20, bits);
    FORMAT_GOLDEN("2-3,5,7,11,13,17,19", "%20pbl", bits);
    bits[0] = 0xfffff;
    FORMAT_GOLDEN("fffff|0-19", "%20pb|%20pbl", bits, bits);
    bits[0] = 0xffffffffffffffffUL; bits[1] = 1;
    FORMAT_GOLDEN("1,ffffffff,ffffffff|0-64", "%65pb|%65pbl", bits, bits);
    bits[0] = 1UL << 63; bits[1] = 1;
    FORMAT_GOLDEN("1,80000000,00000000|63-64", "%65pb|%65pbl", bits, bits);
    unsigned long large_bits[65536 / (8 * sizeof(unsigned long))] = {0};
    for (unsigned int i = 1; i <= 20; i++) set_bit(i, large_bits);
    for (unsigned int i = 60000; i < 60015; i++) set_bit(i, large_bits);
    FORMAT_GOLDEN("1-20,60000-60014", "%*pbl", 65536, large_bits);
    struct resource res = { .start = 0x1000, .end = 0x1fff, .flags = IORESOURCE_MEM };
    FORMAT_GOLDEN("[mem 0x00001000-0x00001fff]", "%pR", &res);
    FORMAT_GOLDEN("[mem 0x00001000-0x00001fff flags 0x200]", "%pr", &res);
    res.flags |= IORESOURCE_MEM_64 | IORESOURCE_PREFETCH | IORESOURCE_WINDOW | IORESOURCE_DISABLED;
    FORMAT_GOLDEN("[mem 0x00001000-0x00001fff 64bit pref window disabled]", "%pR", &res);
    res.flags = IORESOURCE_MEM | IORESOURCE_UNSET;
    FORMAT_GOLDEN("[mem size 0x00001000]", "%pR", &res);
    res = (struct resource){ .start = 0x3f8, .end = 0x3ff, .flags = IORESOURCE_IO };
    FORMAT_GOLDEN("[io  0x03f8-0x03ff]", "%pR", &res);
    res = (struct resource){ .start = 9, .end = 9, .flags = IORESOURCE_IRQ };
    FORMAT_GOLDEN("[irq 9]", "%pR", &res);
    res.flags = IORESOURCE_DMA;
    FORMAT_GOLDEN("[dma 9]", "%pR", &res);
    res = (struct resource){ .start = 0, .end = 0xff, .flags = IORESOURCE_BUS };
    FORMAT_GOLDEN("[bus 00-ff]", "%pR", &res);
    res = (struct resource){ .start = 1, .end = 1, .flags = 0 };
    FORMAT_GOLDEN("[??? 0x00000001 flags 0x0]", "%pR", &res);
}

static void format_test_nested(const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    struct va_format inner = { .fmt = fmt, .va = &args };
    FORMAT_GOLDEN("[CRTC:7:eDP-1] mismatch in pipe mode=1920/ok\n",
        "[CRTC:%d:%s] mismatch in %s %pV\n", 7, "eDP-1", "pipe", &inner);
    FORMAT_GOLDEN("mode=1920/ok|mode=1920/ok", "%pV|%pV", &inner, &inner);
    assert(va_arg(args, unsigned int) == 1920);
    assert(!strcmp(va_arg(args, const char *), "ok"));
    va_end(args);
}

static int format_test_metadata(char *buf, size_t size, unsigned int *status, const char *fmt, ...)
{
    va_list args; va_start(args, fmt);
    int count = vinix_linuxkpi_vformat(buf, size, fmt, args, status);
    va_end(args); return count;
}

static void format_test_nested_invalid(const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    struct va_format inner = { .fmt = fmt, .va = &args };
    char buf[64]; unsigned int status;
    assert(format_test_metadata(buf, sizeof(buf), &status, "%pV/tail", &inner) == 9);
    assert(!strcmp(buf, "head/tail") && status == VINIX_FORMAT_INVALID);
    /* The forbidden nested conversion did not consume its argument. */
    int *untouched = va_arg(args, int *);
    assert(*untouched == 0x13579bdf);
    va_end(args);
}

static void format_test_public_va(const char *fmt, ...)
{
    char buf[64];
    va_list args, copy;
    va_start(args, fmt);
    va_copy(copy, args); assert(vsnprintf(buf, sizeof(buf), fmt, copy) == 6); va_end(copy);
    assert(!strcmp(buf, "42/yes"));
    va_copy(copy, args); assert(vscnprintf(buf, 4, fmt, copy) == 3); va_end(copy);
    assert(!strcmp(buf, "42/"));
    va_copy(copy, args); assert(vsprintf(buf, fmt, copy) == 6); va_end(copy);
    assert(!strcmp(buf, "42/yes"));
    va_end(args);
}

static void format_test_errors_lengths(void)
{
    char buf[64]; unsigned int status;
    int untouched = 0x13579bdf;
    assert(format_test_metadata(buf, sizeof(buf), &status, "prefix%n%s", &untouched, "ignored") == 6);
    assert(!strcmp(buf, "prefix") && status == VINIX_FORMAT_INVALID && untouched == 0x13579bdf);
    assert(format_test_metadata(buf, sizeof(buf), &status, "prefix%f%s", 1.0, "ignored") == 6);
    assert(!strcmp(buf, "prefix") && status == VINIX_FORMAT_INVALID);
    assert(format_test_metadata(buf, sizeof(buf), &status, "prefix%b%s", 1U, "ignored") == 6);
    assert(!strcmp(buf, "prefix") && status == VINIX_FORMAT_INVALID);
    assert(format_test_metadata(buf, sizeof(buf), &status, "prefix%") == 6);
    assert(!strcmp(buf, "prefix") && status == VINIX_FORMAT_INVALID);
    format_test_nested_invalid("head%nignored", &untouched);
    assert(format_test_metadata(buf, sizeof(buf), &status, "%pI4 %s", (void *)1, (char *)1) == 18);
    assert(!strcmp(buf, "(unsupported %pI4)") && status == VINIX_FORMAT_UNSUPPORTED);
    memset(buf, 0xa5, sizeof(buf));
    assert(format_test_metadata(buf, (size_t)INT_MAX + 1, &status, "%s", "untouched") == 0);
    assert((unsigned char)buf[0] == 0xa5 && status == VINIX_FORMAT_INVALID);
    assert(snprintf(buf, sizeof(buf), "%u/%s", 42U, "yes") == 6 && !strcmp(buf, "42/yes"));
    assert(scnprintf(buf, 4, "%u/%s", 42U, "yes") == 3 && !strcmp(buf, "42/"));
    assert(scnprintf(NULL, 0, "%u", 42U) == 0);
    assert(sprintf(buf, "%u/%s", 42U, "yes") == 6 && !strcmp(buf, "42/yes"));
    format_test_public_va("%u/%s", 42U, "yes");
    assert(snprintf(NULL, 0, "%*d", INT_MIN, 1) == ((1 << 23) - 1));
    assert(snprintf(NULL, 0, "%.*d", INT_MAX, 1) == ((1 << 15) - 1));
}

/* Call the host's formatter by its link name despite the test-only macro
 * aliases. Differential cases deliberately exclude documented Linux quirks. */
#ifdef __APPLE__
extern int format_host_libc_vsnprintf(char *, size_t, const char *, va_list) __asm__("_vsnprintf");
#else
extern int format_host_libc_vsnprintf(char *, size_t, const char *, va_list) __asm__("vsnprintf");
#endif
static void format_test_libc(const char *fmt, ...)
{
    char expected[256], actual[256];
    va_list args, copy;
    va_start(args, fmt);
    va_copy(copy, args); int expected_count = format_host_libc_vsnprintf(expected, sizeof(expected), fmt, copy); va_end(copy);
    va_copy(copy, args); int actual_count = vsnprintf(actual, sizeof(actual), fmt, copy); va_end(copy);
    assert(actual_count == expected_count && !memcmp(actual, expected, expected_count + 1));
    va_end(args);
}

struct format_test_key_control { unsigned int ready, published; };
static void *format_test_key_reader(void *argument)
{
    struct format_test_key_control *control = argument;
    char buf[32];
    assert(snprintf(buf, sizeof(buf), "%p", (void *)0x0706050403020100UL) == 16);
    assert(!strcmp(buf, "(____ptrval____)"));
    __atomic_add_fetch(&control->ready, 1, __ATOMIC_RELEASE);
    while (!__atomic_load_n(&control->published, __ATOMIC_ACQUIRE)) {
        assert(snprintf(buf, sizeof(buf), "%p", (void *)0x0706050403020100UL) == 16);
        assert(!strcmp(buf, "(____ptrval____)") || !strcmp(buf, "000000009a932462"));
    }
    assert(snprintf(buf, sizeof(buf), "%p", (void *)0x0706050403020100UL) == 16);
    assert(!strcmp(buf, "000000009a932462"));
    return NULL;
}

static void format_tests(void)
{
    size_t before = live_pages;
    format_test_numbers_strings();
    format_test_pointer_values();
    format_test_bytes_bitmaps_resources();
    format_test_nested("mode=%u/%s", 1920U, "ok");
    format_test_errors_lengths();
    for (int value = -128; value <= 128; value++)
        format_test_libc("[%+8d][%08x][%-8u][%.4d]", value, (unsigned int)value, (unsigned int)value, value);
    format_test_libc("%lld|%llu|%zx|%td", (long long)LLONG_MIN, (unsigned long long)ULLONG_MAX, (size_t)SIZE_MAX, (ptrdiff_t)-12);
    format_test_libc("[%12.3s][%-9s][%3c]", "long-string", "test", 'Q');
    const u64 key[2] = {0x0706050403020100ULL, 0x0f0e0d0c0b0a0908ULL};
    assert(vinix_linuxkpi_format_set_key(NULL) == -EINVAL);
    unsigned long irq = vinix_linuxkpi_irq_save();
    assert(vinix_linuxkpi_format_set_key(key) == -EWOULDBLOCK);
    vinix_linuxkpi_irq_restore(irq);
    preempt_disable();
    assert(vinix_linuxkpi_format_set_key(key) == -EWOULDBLOCK);
    preempt_enable();
    struct format_test_key_control control = {0};
    pthread_t readers[4];
    for (unsigned int i = 0; i < ARRAY_SIZE(readers); i++) assert(!pthread_create(&readers[i], NULL, format_test_key_reader, &control));
    while (__atomic_load_n(&control.ready, __ATOMIC_ACQUIRE) != ARRAY_SIZE(readers)) sched_yield();
    assert(!vinix_linuxkpi_format_set_key(key));
    __atomic_store_n(&control.published, 1, __ATOMIC_RELEASE);
    for (unsigned int i = 0; i < ARRAY_SIZE(readers); i++) assert(!pthread_join(readers[i], NULL));
    assert(vinix_linuxkpi_format_set_key(key) == -EALREADY);
    FORMAT_GOLDEN("000000009a932462|000000009a932462|000000009a932462", "%p|%pK|%pe",
        (void *)0x0706050403020100UL, (void *)0x0706050403020100UL, (void *)0x0706050403020100UL);
    FORMAT_GOLDEN("9a932462|  9a932462|9a932462  ", "%8p|%10p|%-10p", (void *)0x0706050403020100UL, (void *)0x0706050403020100UL, (void *)0x0706050403020100UL);
    assert(live_pages == before && interrupts && !preempt_count());
}
#undef FORMAT_GOLDEN
#endif
