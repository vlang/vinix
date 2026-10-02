/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_BITMAP_RUNTIME_TEST_H
#define VINIX_BITMAP_RUNTIME_TEST_H

int vinix_linuxkpi_bitmap_runtime_selftest(void);

/* The oracle stores one bool per bit; it never uses the backend's word masks
 * or carries. Guard words catch writes beyond the requested bitmap storage. */
#define BITMAP_TEST_BITS 8193U
#define BITMAP_TEST_WORDS (BITMAP_TEST_BITS / BITS_PER_LONG + 2)
#define BITMAP_TEST_GUARD 0x5a15a15a15a15a15UL

static bool bitmap_test_bit(const unsigned long *map, unsigned int bit)
{
    return !!(map[bit / BITS_PER_LONG] & (1UL << (bit % BITS_PER_LONG)));
}

static void bitmap_test_check(const unsigned long *map, const bool *expected,
                              unsigned int nbits)
{
    for (unsigned int bit = 0; bit < nbits; bit++)
        assert(bitmap_test_bit(map, bit) == expected[bit]);
    size_t words = nbits / BITS_PER_LONG + (nbits % BITS_PER_LONG != 0);
    assert(map[words] == BITMAP_TEST_GUARD);
}

static void bitmap_runtime_properties(unsigned int nbits, unsigned long *seed)
{
    unsigned long a[BITMAP_TEST_WORDS], b[BITMAP_TEST_WORDS];
    unsigned long mask[BITMAP_TEST_WORDS], dst[BITMAP_TEST_WORDS];
    unsigned long alias[BITMAP_TEST_WORDS];
    bool ar[BITMAP_TEST_BITS], br[BITMAP_TEST_BITS], mr[BITMAP_TEST_BITS];
    bool expected[BITMAP_TEST_BITS];
    size_t words = nbits / BITS_PER_LONG + (nbits % BITS_PER_LONG != 0);
    for (size_t word = 0; word < words; word++) {
        *seed ^= *seed << 13;
        *seed ^= *seed >> 7;
        *seed ^= *seed << 17;
        a[word] = *seed;
        b[word] = *seed * 0x9e3779b97f4a7c15UL;
        mask[word] = *seed ^ 0xaaaaaaaaaaaaaaaaUL;
    }
    a[words] = b[words] = mask[words] = dst[words] = BITMAP_TEST_GUARD;
    bool equal = true, subset = true, intersects = false, empty = true, full = true;
    unsigned int weight = 0, weight_and = 0;
    for (unsigned int bit = 0; bit < nbits; bit++) {
        ar[bit] = bitmap_test_bit(a, bit);
        br[bit] = bitmap_test_bit(b, bit);
        mr[bit] = bitmap_test_bit(mask, bit);
        equal &= ar[bit] == br[bit];
        subset &= !ar[bit] || br[bit];
        intersects |= ar[bit] && br[bit];
        empty &= !ar[bit];
        full &= ar[bit];
        weight += ar[bit];
        weight_and += ar[bit] && br[bit];
    }
    assert(__bitmap_equal(a, b, nbits) == equal);
    assert(__bitmap_subset(a, b, nbits) == subset);
    assert(__bitmap_intersects(a, b, nbits) == intersects);
    assert(__bitmap_weight(a, nbits) == weight);
    assert(__bitmap_weight_and(a, b, nbits) == weight_and);
    assert(bitmap_empty(a, nbits) == empty && bitmap_full(a, nbits) == full);
    assert(bitmap_weight(a, nbits) == weight);

    for (unsigned int operation = 0; operation < 4; operation++) {
        bool any = false;
        for (unsigned int bit = 0; bit < nbits; bit++) {
            if (operation == 0) expected[bit] = ar[bit] && br[bit];
            if (operation == 1) expected[bit] = ar[bit] && !br[bit];
            if (operation == 2) expected[bit] = ar[bit] || br[bit];
            if (operation == 3) expected[bit] = ar[bit] != br[bit];
            any |= expected[bit];
        }
        for (unsigned int target = 0; target < 3; target++) {
            const unsigned long *lhs = a, *rhs = b;
            unsigned long *out = dst;
            if (target) {
                memcpy(alias, target == 1 ? a : b, (words + 1) * sizeof(*alias));
                out = alias;
                if (target == 1) lhs = alias;
                else rhs = alias;
            }
            if (operation == 0) assert(__bitmap_and(out, lhs, rhs, nbits) == any);
            if (operation == 1) assert(__bitmap_andnot(out, lhs, rhs, nbits) == any);
            if (operation == 2) __bitmap_or(out, lhs, rhs, nbits);
            if (operation == 3) __bitmap_xor(out, lhs, rhs, nbits);
            bitmap_test_check(out, expected, nbits);
            if (operation == 2) assert(__bitmap_or_equal(a, b, out, nbits));
            if (operation < 2 && nbits % BITS_PER_LONG)
                for (unsigned int bit = nbits; bit < words * BITS_PER_LONG; bit++)
                    assert(!bitmap_test_bit(out, bit));
        }
    }
    for (unsigned int bit = 0; bit < nbits; bit++) expected[bit] = !ar[bit];
    __bitmap_complement(dst, a, nbits);
    bitmap_test_check(dst, expected, nbits);
    memcpy(alias, a, (words + 1) * sizeof(*alias));
    __bitmap_complement(alias, alias, nbits);
    bitmap_test_check(alias, expected, nbits);

    for (unsigned int bit = 0; bit < nbits; bit++)
        expected[bit] = mr[bit] ? br[bit] : ar[bit];
    for (unsigned int target = 0; target < 4; target++) {
        const unsigned long *old = a, *new = b, *select = mask;
        unsigned long *out = dst;
        if (target) {
            memcpy(alias, target == 1 ? a : target == 2 ? b : mask,
                   (words + 1) * sizeof(*alias));
            out = alias;
            if (target == 1) old = alias;
            if (target == 2) new = alias;
            if (target == 3) select = alias;
        }
        __bitmap_replace(out, old, new, select, nbits);
        bitmap_test_check(out, expected, nbits);
    }

    const unsigned int shifts[] = { 0, 1, 31, 32, 63, 64, 65,
                                    nbits ? nbits - 1 : 0, nbits, nbits + 1, UINT_MAX };
    for (size_t s = 0; s < ARRAY_SIZE(shifts); s++) {
        unsigned int shift = shifts[s];
        for (unsigned int direction = 0; direction < 2; direction++) {
            for (unsigned int bit = 0; bit < nbits; bit++) {
                expected[bit] = false;
                if (direction == 0 && shift < nbits - bit)
                    expected[bit] = ar[bit + shift];
                if (direction == 1 && bit >= shift)
                    expected[bit] = ar[bit - shift];
            }
            memcpy(alias, a, (words + 1) * sizeof(*alias));
            if (direction == 0) {
                __bitmap_shift_right(dst, a, shift, nbits);
                __bitmap_shift_right(alias, alias, shift, nbits);
            } else {
                __bitmap_shift_left(dst, a, shift, nbits);
                __bitmap_shift_left(alias, alias, shift, nbits);
            }
            bitmap_test_check(dst, expected, nbits);
            bitmap_test_check(alias, expected, nbits);
        }
    }

    const unsigned int starts[] = { 0, 1, 31, 63, 64, nbits };
    const unsigned int lengths[] = { 0, 1, 2, 63, 64, 65, nbits };
    for (size_t s = 0; s < ARRAY_SIZE(starts); s++) {
        unsigned int start = starts[s];
        if (start > nbits) continue;
        for (size_t l = 0; l < ARRAY_SIZE(lengths); l++) {
            unsigned int len = lengths[l];
            if (len > nbits - start) len = nbits - start;
            for (unsigned int clear = 0; clear < 2; clear++) {
                memcpy(dst, a, (words + 1) * sizeof(*dst));
                memcpy(expected, ar, nbits * sizeof(*expected));
                for (unsigned int bit = start; bit < start + len; bit++)
                    expected[bit] = !clear;
                if (clear) __bitmap_clear(dst, start, len);
                else __bitmap_set(dst, start, len);
                bitmap_test_check(dst, expected, nbits);
                /* A range operation also preserves unused bits in its word. */
                for (unsigned int bit = nbits; bit < words * BITS_PER_LONG; bit++)
                    assert(bitmap_test_bit(dst, bit) == bitmap_test_bit(a, bit));
            }
        }
    }

    size_t halfwords = nbits / 32 + (nbits % 32 != 0);
    u32 *packed = malloc((halfwords ? halfwords : 1) * sizeof(*packed));
    assert(packed);
    bitmap_to_arr32(packed, a, nbits);
    for (unsigned int bit = 0; bit < nbits; bit++)
        assert(!!(packed[bit / 32] & (1U << (bit % 32))) == ar[bit]);
    for (unsigned int bit = nbits; bit < halfwords * 32; bit++)
        assert(!(packed[bit / 32] & (1U << (bit % 32))));
    bitmap_from_arr32(dst, packed, nbits);
    bitmap_test_check(dst, ar, nbits);
    for (unsigned int bit = nbits; bit < words * BITS_PER_LONG; bit++)
        assert(!bitmap_test_bit(dst, bit));
    free(packed);

    /* Dirt outside nbits never changes predicates or population counts. */
    memcpy(alias, a, (words + 1) * sizeof(*alias));
    if (nbits % BITS_PER_LONG) alias[words - 1] ^= ~0UL << (nbits % BITS_PER_LONG);
    assert(__bitmap_equal(a, alias, nbits));
    assert(__bitmap_weight(alias, nbits) == weight);
    for (size_t word = 0; word < words; word++) alias[word] = 0;
    if (nbits % BITS_PER_LONG) alias[words - 1] = ~0UL << (nbits % BITS_PER_LONG);
    assert(bitmap_empty(alias, nbits));
    for (size_t word = 0; word < words; word++) alias[word] = ~0UL;
    if (nbits % BITS_PER_LONG) alias[words - 1] >>= BITS_PER_LONG - nbits % BITS_PER_LONG;
    assert(bitmap_full(alias, nbits));
}

static void test_bitmap_runtime(void)
{
    const unsigned int widths[] = { 0, 1, 31, 32, 33, 63, 64, 65, 127,
                                    128, 129, 257, 4097, BITMAP_TEST_BITS };
    size_t before = live_pages;
    unsigned long seed = 0x1234abcddcba4321UL;
    for (unsigned int round = 0; round < 4; round++)
        for (size_t i = 0; i < ARRAY_SIZE(widths); i++)
            bitmap_runtime_properties(widths[i], &seed);
    assert(live_pages == before);

    /* Zero-width operations permit NULL pointers and must never dereference. */
    assert(__bitmap_equal(NULL, NULL, 0) && __bitmap_subset(NULL, NULL, 0));
    assert(!__bitmap_intersects(NULL, NULL, 0) && !__bitmap_weight(NULL, 0));
    assert(!__bitmap_and(NULL, NULL, NULL, 0));
    assert(!__bitmap_andnot(NULL, NULL, NULL, 0));
    __bitmap_shift_right(NULL, NULL, UINT_MAX, 0);
    __bitmap_shift_left(NULL, NULL, UINT_MAX, 0);
    __bitmap_set(NULL, UINT_MAX, 0);
    __bitmap_clear(NULL, UINT_MAX, 0);
    bitmap_from_arr32(NULL, NULL, 0);
    bitmap_to_arr32(NULL, NULL, 0);

    assert(bitmap_zalloc(0, GFP_KERNEL) == ZERO_SIZE_PTR);
    bitmap_free(NULL);
    bitmap_free(ZERO_SIZE_PTR);
    assert(!bitmap_alloc_node(1, GFP_KERNEL, 1));
    assert(!bitmap_zalloc_node(1, GFP_KERNEL, -2));
    assert(!bitmap_alloc(1, GFP_KERNEL | __GFP_DMA32));
    for (unsigned int round = 0; round < 200; round++) {
        unsigned int nbits = widths[round % ARRAY_SIZE(widths)];
        unsigned long *map = bitmap_zalloc_node(nbits, GFP_KERNEL, round & 1 ? 0 : -1);
        assert(map);
        if (nbits) {
            size_t bytes = (nbits / BITS_PER_LONG + !!(nbits % BITS_PER_LONG)) * sizeof(*map);
            assert(ksize(map) == bytes);
            for (size_t i = 0; i < bytes; i++) assert(!((unsigned char *)map)[i]);
            __bitmap_set(map, 0, nbits);
            assert(__bitmap_weight(map, nbits) == nbits);
        }
        bitmap_free(map);
        assert(live_pages == before);
    }
    fail_allocation = true;
    assert(!bitmap_alloc(1, GFP_KERNEL));
    assert(!bitmap_zalloc(4097, GFP_KERNEL));
    /* Detect overflow in unsigned rounding without allocating half a GiB. */
    assert(!bitmap_alloc(UINT_MAX, GFP_KERNEL));
    assert(!bitmap_zalloc_node(UINT_MAX, GFP_KERNEL, 0));
    fail_allocation = false;
    assert(live_pages == before);
    for (unsigned int round = 0; round < 200; round++) {
        assert(!vinix_linuxkpi_bitmap_runtime_selftest());
        assert(live_pages == before);
    }
}

#endif
