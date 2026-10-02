/* SPDX-License-Identifier: GPL-2.0-only */
/* Keep this first: kernel.h must supply the original integer helpers itself. */
#include <linux/kernel.h>
#include <assert.h>

_Static_assert(U32_MAX == 0xffffffffU && S32_MAX == 2147483647, "kernel limits visibility");
_Static_assert(U64_MAX == 0xffffffffffffffffULL, "64-bit kernel limits visibility");
_Static_assert(BIT(5) == 32, "kernel bit constants must be available");
_Static_assert(const_ilog2(1ULL << 63) == 63, "64-bit constant logarithm");

int main(void)
{
    const unsigned long highest = 1UL << (BITS_PER_LONG - 1);
    const volatile unsigned long values[] = {
        0, 1, 2, 3, 4, 7, 8, 15, 16, highest, highest + 1, ~0UL,
    };
    const bool powers[] = {
        false, true, true, false, true, false, true, false, true,
        true, false, false,
    };
    for (unsigned int i = 0; i < sizeof(values) / sizeof(values[0]); i++)
        assert(is_power_of_2(values[i]) == powers[i]);

    /* Zero is defined for order_base_2, but not for the runtime logarithm or
     * power-of-two rounding helpers. Exercise their valid boundary inputs. */
    volatile unsigned long value = 0;
    assert(order_base_2(value) == 0);
    value = 1;
    assert(order_base_2(value) == 0 && ilog2(value) == 0);
    assert(roundup_pow_of_two(value) == 1 && rounddown_pow_of_two(value) == 1);
    value = 3;
    assert(order_base_2(value) == 2 && ilog2(value) == 1);
    assert(roundup_pow_of_two(value) == 4 && rounddown_pow_of_two(value) == 2);
    value = 17;
    assert(order_base_2(value) == 5 && ilog2(value) == 4);
    assert(roundup_pow_of_two(value) == 32 && rounddown_pow_of_two(value) == 16);
    value = highest;
    assert(order_base_2(value) == BITS_PER_LONG - 1);
    assert(ilog2(value) == BITS_PER_LONG - 1);
    assert(roundup_pow_of_two(value) == highest && rounddown_pow_of_two(value) == highest);
    value = ~0UL;
    assert(order_base_2(value) == BITS_PER_LONG);
    assert(ilog2(value) == BITS_PER_LONG - 1 && rounddown_pow_of_two(value) == highest);

    volatile u32 small = 0x80000000U;
    volatile u64 large = 1ULL << 63;
    assert(ilog2(small) == 31 && ilog2(large) == 63);

    unsigned int a = 7, b = 9;
    assert(min(a++, b++) == 7 && a == 8 && b == 10);
    assert(max(a++, b++) == 10 && a == 9 && b == 11);
    unsigned int lo = 2, hi = 8, input = 10;
    assert(clamp_val(input++, lo++, hi++) == 8);
    assert(input == 11 && lo == 3 && hi == 9);
    assert(clamp_val(0U, 2, 8) == 2);
    assert(clamp_val(5U, 2, 8) == 5);
    assert(clamp_val(~0U, 2, 8) == 8);
    assert(clamp_val(highest, 0, highest) == highest);
    assert(clamp(-10, -8, 8) == -8 && clamp(10, -8, 8) == 8);
    assert(min_not_zero(0U, 9U) == 9 && min_not_zero(7U, 0U) == 7);
    assert(min_t(u64, 1ULL << 63, 7U) == 7);
    assert(max_t(u64, 1ULL << 63, 7U) == 1ULL << 63);
    return 0;
}
