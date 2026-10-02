/* SPDX-License-Identifier: GPL-2.0-only */
/* Fixed public-API vectors; kernel strings are borrowed for the call only. */
#ifndef VINIX_KSTRTOX_TEST_H
#define VINIX_KSTRTOX_TEST_H
#include <linux/kstrtox.h>
#include <linux/string.h>
#include <linux/errno.h>
#include <vinix/runtime.h>
#include <assert.h>
#include <sys/mman.h>
#include <unistd.h>

struct kstrtox_unsigned_case {
    const char *text;
    unsigned int base;
    unsigned long long value;
    int error;
};
struct kstrtox_signed_case {
    const char *text;
    unsigned int base;
    long long value;
    int error;
};

static void kstrtox_check_guards(const unsigned char before[8],
                                const unsigned char after[8])
{
    for (unsigned int i = 0; i < 8; i++) {
        assert(before[i] == 0xa5);
        assert(after[i] == 0x5a);
    }
}

#define KSTRTOX_CHECK_NUMERIC(function, type, cases) do { \
    for (size_t kstrtox_i = 0; kstrtox_i < sizeof(cases) / sizeof((cases)[0]); kstrtox_i++) { \
        struct { unsigned char before[8]; type value; unsigned char after[8]; } output; \
        memset(output.before, 0xa5, sizeof(output.before)); \
        memset(output.after, 0x5a, sizeof(output.after)); \
        output.value = (type)90; \
        int error = function((cases)[kstrtox_i].text, (cases)[kstrtox_i].base, &output.value); \
        assert(error == (cases)[kstrtox_i].error); \
        assert(output.value == (error ? (type)90 : (type)(cases)[kstrtox_i].value)); \
        kstrtox_check_guards(output.before, output.after); \
    } \
} while (0)

static void kstrtox_check_bool(const char *text, int expected_error, bool expected_value)
{
    for (unsigned int initial = 0; initial < 2; initial++) {
        struct { unsigned char before[8]; bool value; unsigned char after[8]; } output;
        memset(output.before, 0xa5, sizeof(output.before));
        memset(output.after, 0x5a, sizeof(output.after));
        output.value = !!initial;
        int error = kstrtobool(text, &output.value);
        assert(error == expected_error);
        assert(output.value == (error ? !!initial : expected_value));
        kstrtox_check_guards(output.before, output.after);
        output.value = !!initial;
        error = strtobool(text, &output.value);
        assert(error == expected_error);
        assert(output.value == (error ? !!initial : expected_value));
        kstrtox_check_guards(output.before, output.after);
    }
}

static void kstrtox_tests(void)
{
    static const struct kstrtox_unsigned_case unsigned_common[] = {
        { "0", 0, 0, 0 }, { "+0", 10, 0, 0 }, { "42", 0, 42, 0 },
        { "42\n", 10, 42, 0 }, { "+42", 10, 42, 0 },
        { "052", 0, 42, 0 }, { "00042", 0, 34, 0 }, { "00042", 10, 42, 0 },
        { "0x2a", 0, 42, 0 }, { "0X2A", 0, 42, 0 },
        { "+0x2A\n", 0, 42, 0 }, { "0x2a", 16, 42, 0 },
        { "2A", 16, 42, 0 }, { "101010", 2, 42, 0 },
        { "1120", 3, 42, 0 }, { "222", 4, 42, 0 },
        { "132", 5, 42, 0 }, { "110", 6, 42, 0 },
        { "60", 7, 42, 0 }, { "52", 8, 42, 0 },
        { "46", 9, 42, 0 }, { "42", 10, 42, 0 },
        { "39", 11, 42, 0 }, { "36", 12, 42, 0 },
        { "33", 13, 42, 0 }, { "30", 14, 42, 0 }, { "2c", 15, 42, 0 },
        { "", 0, 0, -EINVAL }, { "\n", 0, 0, -EINVAL },
        { "+", 0, 0, -EINVAL }, { "+\n", 10, 0, -EINVAL },
        { "-0", 10, 0, -EINVAL }, { "-1", 10, 0, -EINVAL },
        { " 42", 10, 0, -EINVAL }, { "\t42", 10, 0, -EINVAL },
        { "42 ", 10, 0, -EINVAL }, { "42\n\n", 10, 0, -EINVAL },
        { "42x", 10, 0, -EINVAL }, { "++42", 10, 0, -EINVAL },
        { "0x", 0, 0, -EINVAL }, { "0x", 16, 0, -EINVAL },
        { "0Xg", 0, 0, -EINVAL }, { "0xg", 16, 0, -EINVAL },
        { "08", 0, 0, -EINVAL }, { "2", 2, 0, -EINVAL },
        { "0x2a", 10, 0, -EINVAL }, { "\377", 16, 0, -EINVAL },
        { "18446744073709551616", 10, 0, -ERANGE },
        { "18446744073709551616x", 10, 0, -ERANGE },
    };
    static const struct kstrtox_signed_case signed_common[] = {
        { "0", 0, 0, 0 }, { "-0", 10, 0, 0 }, { "+0", 10, 0, 0 },
        { "42", 10, 42, 0 }, { "-42", 10, -42, 0 },
        { "+42\n", 10, 42, 0 }, { "-42\n", 10, -42, 0 },
        { "-052", 0, -42, 0 }, { "-0X2a", 0, -42, 0 },
        { "-2A", 16, -42, 0 }, { "-101010", 2, -42, 0 },
        { "", 10, 0, -EINVAL }, { "-", 0, 0, -EINVAL },
        { "+", 0, 0, -EINVAL }, { "-+42", 10, 0, -EINVAL },
        { "--42", 10, 0, -EINVAL }, { " -42", 10, 0, -EINVAL },
        { "-42\n\n", 10, 0, -EINVAL }, { "-42x", 10, 0, -EINVAL },
        { "-0x", 0, 0, -EINVAL }, { "-0x", 16, 0, -EINVAL },
        { "9223372036854775808", 10, 0, -ERANGE },
        { "-9223372036854775809", 10, 0, -ERANGE },
        { "18446744073709551615", 10, 0, -ERANGE },
        { "18446744073709551616x", 10, 0, -ERANGE },
    };
    static const struct kstrtox_unsigned_case u8_limits[] = {
        { "255", 10, 255, 0 }, { "ff", 16, 255, 0 },
        { "256", 10, 0, -ERANGE }, { "100", 16, 0, -ERANGE },
        { "0400", 0, 0, -ERANGE }, { "256\n", 10, 0, -ERANGE },
        { "256x", 10, 0, -EINVAL },
    };
    /* The unchanged force_probe PCI caller parses a borrowed token in base16.
     * 9a49 is a parser vector, not evidence of the target machine's PCI ID. */
    static const struct kstrtox_unsigned_case u16_limits[] = {
        { "65535", 10, 65535, 0 }, { "ffff", 16, 65535, 0 },
        { "65536", 10, 0, -ERANGE }, { "10000", 16, 0, -ERANGE },
        { "65536x", 10, 0, -EINVAL },
        { "9a49", 16, 39497, 0 }, { "9A49", 16, 39497, 0 },
        { "0x9a49", 16, 39497, 0 }, { "+9a49", 16, 39497, 0 },
        { "9a49x", 16, 0, -EINVAL }, { "!9a49", 16, 0, -EINVAL },
        { "9a49", 0, 0, -EINVAL },
    };
    static const struct kstrtox_unsigned_case u32_limits[] = {
        { "4294967295", 10, 4294967295ULL, 0 },
        { "ffffffff", 16, 4294967295ULL, 0 },
        { "4294967296", 10, 0, -ERANGE },
        { "100000000", 16, 0, -ERANGE }, { "4294967296x", 10, 0, -EINVAL },
    };
    static const struct kstrtox_unsigned_case u64_limits[] = {
        { "18446744073709551615", 10, 18446744073709551615ULL, 0 },
        { "ffffffffffffffff", 16, 18446744073709551615ULL, 0 },
        { "+18446744073709551615\n", 10, 18446744073709551615ULL, 0 },
        { "18446744073709551616", 10, 0, -ERANGE },
        { "10000000000000000", 16, 0, -ERANGE },
        { "18446744073709551616x", 10, 0, -ERANGE },
    };
    static const struct kstrtox_signed_case s8_limits[] = {
        { "127", 10, 127, 0 }, { "-128", 10, -128, 0 },
        { "7f", 16, 127, 0 }, { "-80", 16, -128, 0 },
        { "128", 10, 0, -ERANGE }, { "-129", 10, 0, -ERANGE },
        { "80", 16, 0, -ERANGE }, { "-81", 16, 0, -ERANGE },
        { "-129x", 10, 0, -EINVAL },
    };
    static const struct kstrtox_signed_case s16_limits[] = {
        { "32767", 10, 32767, 0 }, { "-32768", 10, -32768, 0 },
        { "7fff", 16, 32767, 0 }, { "-8000", 16, -32768, 0 },
        { "32768", 10, 0, -ERANGE }, { "-32769", 10, 0, -ERANGE },
        { "8000", 16, 0, -ERANGE }, { "-8001", 16, 0, -ERANGE },
        { "-32769x", 10, 0, -EINVAL },
    };
    static const struct kstrtox_signed_case s32_limits[] = {
        { "2147483647", 10, 2147483647LL, 0 },
        { "-2147483648", 10, -2147483648LL, 0 },
        { "7fffffff", 16, 2147483647LL, 0 },
        { "-80000000", 16, -2147483648LL, 0 },
        { "2147483648", 10, 0, -ERANGE }, { "-2147483649", 10, 0, -ERANGE },
        { "80000000", 16, 0, -ERANGE }, { "-80000001", 16, 0, -ERANGE },
        { "-2147483649x", 10, 0, -EINVAL },
    };
    static const struct kstrtox_signed_case s64_limits[] = {
        { "9223372036854775807", 10, 9223372036854775807LL, 0 },
        { "-9223372036854775808", 10, (-9223372036854775807LL - 1), 0 },
        { "7fffffffffffffff", 16, 9223372036854775807LL, 0 },
        { "-8000000000000000", 16, (-9223372036854775807LL - 1), 0 },
        { "9223372036854775808", 10, 0, -ERANGE },
        { "-9223372036854775809", 10, 0, -ERANGE },
        { "8000000000000000", 16, 0, -ERANGE },
        { "-8000000000000001", 16, 0, -ERANGE },
        { "-9223372036854775809x", 10, 0, -EINVAL },
    };
    static const struct { const char *text; int error; bool value; } booleans[] = {
        { "y", 0, true }, { "Y", 0, true }, { "yes", 0, true },
        { "t", 0, true }, { "T", 0, true }, { "trueXYZ", 0, true },
        { "1", 0, true }, { "10", 0, true }, { "1\nanything", 0, true },
        { "n", 0, false }, { "N", 0, false }, { "no", 0, false },
        { "f", 0, false }, { "F", 0, false }, { "falseXYZ", 0, false },
        { "0", 0, false }, { "01", 0, false },
        { "on", 0, true }, { "ON", 0, true }, { "oNAnything", 0, true },
        { "of", 0, false }, { "OF", 0, false }, { "offXYZ", 0, false },
        { "", -EINVAL, false }, { NULL, -EINVAL, false },
        { "o", -EINVAL, false }, { "ox", -EINVAL, false },
        { "2", -EINVAL, false }, { " yes", -EINVAL, false },
        { "\n", -EINVAL, false }, { "\377", -EINVAL, false },
    };
    static const struct {
        const char *text;
        unsigned int base;
        unsigned long long value;
        int error, bool_error;
        bool boolean;
    } guarded[] = {
        { "", 0, 0, -EINVAL, -EINVAL, false },
        { "0", 0, 0, 0, 0, false },
        { "0x", 0, 0, -EINVAL, 0, false },
        { "0X", 16, 0, -EINVAL, 0, false },
        { "+", 10, 0, -EINVAL, -EINVAL, false },
        { "42\n", 10, 42, 0, -EINVAL, false },
        { "42\n\n", 10, 0, -EINVAL, -EINVAL, false },
        { "18446744073709551615", 10, 18446744073709551615ULL, 0, 0, true },
        { "18446744073709551616", 10, 0, -ERANGE, 0, true },
        { "yes", 10, 0, -EINVAL, 0, true },
        { "of", 10, 0, -EINVAL, 0, false },
        { "o", 10, 0, -EINVAL, -EINVAL, false },
        { "\377", 10, 0, -EINVAL, -EINVAL, false },
    };
    struct { unsigned char *mapping; const char *text; } borrowed[sizeof(guarded) / sizeof(guarded[0])];
    long page_size = sysconf(_SC_PAGESIZE);
    assert(page_size > 0 && (size_t)page_size > 32);
    size_t mapping_size = 3 * (size_t)page_size;
    for (size_t i = 0; i < sizeof(guarded) / sizeof(guarded[0]); i++) {
        unsigned char *mapping = mmap(NULL, mapping_size, PROT_NONE,
                MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        assert(mapping != MAP_FAILED);
        assert(!mprotect(mapping + page_size, (size_t)page_size, PROT_READ | PROT_WRITE));
        size_t length = strlen(guarded[i].text) + 1;
        char *text = (char *)mapping + 2 * page_size - length;
        memcpy(text, guarded[i].text, length);
        assert(!mprotect(mapping + page_size, (size_t)page_size, PROT_READ));
        borrowed[i].mapping = mapping;
        borrowed[i].text = text;
    }

    assert(sizeof(unsigned long) == 8 && sizeof(long) == 8);
    size_t pages = live_pages;
    unsigned int original_depth = vinix_linuxkpi_preempt_count();
    unsigned int original_cpu = current_cpu;
    u64 original_irq = vinix_linuxkpi_irq_flags();
    bool allocation_failure = fail_allocation;
    fail_allocation = true;
    u64 flags = vinix_linuxkpi_irq_save();
    vinix_linuxkpi_preempt_disable();
    vinix_linuxkpi_preempt_disable();
    unsigned int depth = vinix_linuxkpi_preempt_count();
    u64 irq = vinix_linuxkpi_irq_flags();

    KSTRTOX_CHECK_NUMERIC(kstrtou8, u8, unsigned_common);
    KSTRTOX_CHECK_NUMERIC(kstrtou16, u16, unsigned_common);
    KSTRTOX_CHECK_NUMERIC(kstrtou32, u32, unsigned_common);
    KSTRTOX_CHECK_NUMERIC(kstrtouint, unsigned int, unsigned_common);
    KSTRTOX_CHECK_NUMERIC(kstrtou64, u64, unsigned_common);
    KSTRTOX_CHECK_NUMERIC(kstrtoull, unsigned long long, unsigned_common);
    KSTRTOX_CHECK_NUMERIC(kstrtoul, unsigned long, unsigned_common);
    KSTRTOX_CHECK_NUMERIC(_kstrtoul, unsigned long, unsigned_common);
    KSTRTOX_CHECK_NUMERIC(kstrtos8, s8, signed_common);
    KSTRTOX_CHECK_NUMERIC(kstrtos16, s16, signed_common);
    KSTRTOX_CHECK_NUMERIC(kstrtos32, s32, signed_common);
    KSTRTOX_CHECK_NUMERIC(kstrtoint, int, signed_common);
    KSTRTOX_CHECK_NUMERIC(kstrtos64, s64, signed_common);
    KSTRTOX_CHECK_NUMERIC(kstrtoll, long long, signed_common);
    KSTRTOX_CHECK_NUMERIC(kstrtol, long, signed_common);
    KSTRTOX_CHECK_NUMERIC(_kstrtol, long, signed_common);

    KSTRTOX_CHECK_NUMERIC(kstrtou8, u8, u8_limits);
    KSTRTOX_CHECK_NUMERIC(kstrtou16, u16, u16_limits);
    KSTRTOX_CHECK_NUMERIC(kstrtou32, u32, u32_limits);
    KSTRTOX_CHECK_NUMERIC(kstrtouint, unsigned int, u32_limits);
    KSTRTOX_CHECK_NUMERIC(kstrtou64, u64, u64_limits);
    KSTRTOX_CHECK_NUMERIC(kstrtoull, unsigned long long, u64_limits);
    KSTRTOX_CHECK_NUMERIC(kstrtoul, unsigned long, u64_limits);
    KSTRTOX_CHECK_NUMERIC(_kstrtoul, unsigned long, u64_limits);
    KSTRTOX_CHECK_NUMERIC(kstrtos8, s8, s8_limits);
    KSTRTOX_CHECK_NUMERIC(kstrtos16, s16, s16_limits);
    KSTRTOX_CHECK_NUMERIC(kstrtos32, s32, s32_limits);
    KSTRTOX_CHECK_NUMERIC(kstrtoint, int, s32_limits);
    KSTRTOX_CHECK_NUMERIC(kstrtos64, s64, s64_limits);
    KSTRTOX_CHECK_NUMERIC(kstrtoll, long long, s64_limits);
    KSTRTOX_CHECK_NUMERIC(kstrtol, long, s64_limits);
    KSTRTOX_CHECK_NUMERIC(_kstrtol, long, s64_limits);

    for (size_t i = 0; i < sizeof(booleans) / sizeof(booleans[0]); i++)
        kstrtox_check_bool(booleans[i].text, booleans[i].error, booleans[i].value);
    for (size_t i = 0; i < sizeof(guarded) / sizeof(guarded[0]); i++) {
        struct kstrtox_unsigned_case test[] = {
            { borrowed[i].text, guarded[i].base, guarded[i].value, guarded[i].error },
        };
        KSTRTOX_CHECK_NUMERIC(kstrtoull, unsigned long long, test);
        kstrtox_check_bool(borrowed[i].text, guarded[i].bool_error, guarded[i].boolean);
    }
    assert(live_pages == pages && vinix_linuxkpi_preempt_count() == depth &&
           vinix_linuxkpi_irq_flags() == irq && current_cpu == original_cpu);
    vinix_linuxkpi_preempt_enable_no_resched();
    vinix_linuxkpi_preempt_enable_no_resched();
    vinix_linuxkpi_irq_restore(flags);
    fail_allocation = allocation_failure;
    assert(vinix_linuxkpi_preempt_count() == original_depth &&
           vinix_linuxkpi_irq_flags() == original_irq && live_pages == pages);
    for (size_t i = 0; i < sizeof(guarded) / sizeof(guarded[0]); i++)
        assert(!munmap(borrowed[i].mapping, mapping_size));
    u16 pci_token = 0;
    assert(!kstrtou16("9a49", 16, &pci_token) && pci_token == 39497);
}
#undef KSTRTOX_CHECK_NUMERIC
#endif
