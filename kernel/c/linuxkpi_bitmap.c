/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifdef VINIX_LINUXKPI
#include <linux/bitmap.h>
#include <linux/bug.h>
#include <linux/errno.h>
#include <linux/slab.h>

/* Linux 6.6 bitmap semantics: unused tail bits are unspecified except where
 * they affect a scalar result, or the API explicitly clears them. The native
 * implementation has no device/MM dependency and allocates only in alloc().
 * Parsing, devres, user-buffer, remapping and region APIs remain unresolved. */
static size_t bitmap_words(unsigned int nbits)
{
    /* BITS_TO_LONGS(UINT_MAX) can overflow its unsigned rounding addition. */
    return nbits / BITS_PER_LONG + (nbits % BITS_PER_LONG != 0);
}

unsigned long *bitmap_alloc(unsigned int nbits, gfp_t flags)
{
    return kmalloc_array(bitmap_words(nbits), sizeof(unsigned long), flags);
}

unsigned long *bitmap_zalloc(unsigned int nbits, gfp_t flags)
{
    return bitmap_alloc(nbits, flags | __GFP_ZERO);
}

unsigned long *bitmap_alloc_node(unsigned int nbits, gfp_t flags, int node)
{
    /* There is one native allocation domain. -1 is Linux NUMA_NO_NODE. */
    if (node != -1 && node != 0) return NULL;
    return bitmap_alloc(nbits, flags);
}

unsigned long *bitmap_zalloc_node(unsigned int nbits, gfp_t flags, int node)
{
    return bitmap_alloc_node(nbits, flags | __GFP_ZERO, node);
}

void bitmap_free(const unsigned long *bitmap)
{
    kfree(bitmap);
}

bool __bitmap_equal(const unsigned long *a, const unsigned long *b,
                    unsigned int nbits)
{
    size_t full = nbits / BITS_PER_LONG;
    for (size_t i = 0; i < full; i++)
        if (a[i] != b[i]) return false;
    return !(nbits % BITS_PER_LONG) ||
           !((a[full] ^ b[full]) & BITMAP_LAST_WORD_MASK(nbits));
}

bool __bitmap_or_equal(const unsigned long *a, const unsigned long *b,
                       const unsigned long *c, unsigned int nbits)
{
    size_t full = nbits / BITS_PER_LONG;
    for (size_t i = 0; i < full; i++)
        if ((a[i] | b[i]) != c[i]) return false;
    return !(nbits % BITS_PER_LONG) ||
           !(((a[full] | b[full]) ^ c[full]) & BITMAP_LAST_WORD_MASK(nbits));
}

void __bitmap_complement(unsigned long *dst, const unsigned long *src,
                         unsigned int nbits)
{
    for (size_t i = 0, words = bitmap_words(nbits); i < words; i++)
        dst[i] = ~src[i];
}

bool __bitmap_and(unsigned long *dst, const unsigned long *a,
                  const unsigned long *b, unsigned int nbits)
{
    size_t full = nbits / BITS_PER_LONG;
    unsigned long any = 0;
    for (size_t i = 0; i < full; i++) any |= (dst[i] = a[i] & b[i]);
    if (nbits % BITS_PER_LONG)
        any |= (dst[full] = a[full] & b[full] & BITMAP_LAST_WORD_MASK(nbits));
    return any != 0;
}

bool __bitmap_andnot(unsigned long *dst, const unsigned long *a,
                     const unsigned long *b, unsigned int nbits)
{
    size_t full = nbits / BITS_PER_LONG;
    unsigned long any = 0;
    for (size_t i = 0; i < full; i++) any |= (dst[i] = a[i] & ~b[i]);
    if (nbits % BITS_PER_LONG)
        any |= (dst[full] = a[full] & ~b[full] & BITMAP_LAST_WORD_MASK(nbits));
    return any != 0;
}

void __bitmap_or(unsigned long *dst, const unsigned long *a,
                 const unsigned long *b, unsigned int nbits)
{
    for (size_t i = 0, words = bitmap_words(nbits); i < words; i++)
        dst[i] = a[i] | b[i];
}

void __bitmap_xor(unsigned long *dst, const unsigned long *a,
                  const unsigned long *b, unsigned int nbits)
{
    for (size_t i = 0, words = bitmap_words(nbits); i < words; i++)
        dst[i] = a[i] ^ b[i];
}

void __bitmap_replace(unsigned long *dst, const unsigned long *old,
                      const unsigned long *new, const unsigned long *mask,
                      unsigned int nbits)
{
    for (size_t i = 0, words = bitmap_words(nbits); i < words; i++)
        dst[i] = (old[i] & ~mask[i]) | (new[i] & mask[i]);
}

bool __bitmap_intersects(const unsigned long *a, const unsigned long *b,
                         unsigned int nbits)
{
    size_t full = nbits / BITS_PER_LONG;
    for (size_t i = 0; i < full; i++) if (a[i] & b[i]) return true;
    return (nbits % BITS_PER_LONG) &&
           (a[full] & b[full] & BITMAP_LAST_WORD_MASK(nbits));
}

bool __bitmap_subset(const unsigned long *a, const unsigned long *b,
                     unsigned int nbits)
{
    size_t full = nbits / BITS_PER_LONG;
    for (size_t i = 0; i < full; i++) if (a[i] & ~b[i]) return false;
    return !(nbits % BITS_PER_LONG) ||
           !(a[full] & ~b[full] & BITMAP_LAST_WORD_MASK(nbits));
}

unsigned int __bitmap_weight(const unsigned long *src, unsigned int nbits)
{
    size_t full = nbits / BITS_PER_LONG;
    unsigned int weight = 0;
    for (size_t i = 0; i < full; i++) weight += hweight_long(src[i]);
    if (nbits % BITS_PER_LONG)
        weight += hweight_long(src[full] & BITMAP_LAST_WORD_MASK(nbits));
    return weight;
}

unsigned int __bitmap_weight_and(const unsigned long *a, const unsigned long *b,
                                 unsigned int nbits)
{
    size_t full = nbits / BITS_PER_LONG;
    unsigned int weight = 0;
    for (size_t i = 0; i < full; i++) weight += hweight_long(a[i] & b[i]);
    if (nbits % BITS_PER_LONG)
        weight += hweight_long(a[full] & b[full] & BITMAP_LAST_WORD_MASK(nbits));
    return weight;
}

void __bitmap_set(unsigned long *map, unsigned int start, int len)
{
    BUG_ON(len < 0 || (unsigned int)len > UINT_MAX - start);
    if (!len) return;
    unsigned long *word = map + start / BITS_PER_LONG;
    unsigned int offset = start % BITS_PER_LONG;
    while (len) {
        unsigned int chunk = BITS_PER_LONG - offset;
        if (chunk > (unsigned int)len) chunk = len;
        *word++ |= BITMAP_LAST_WORD_MASK(chunk) << offset;
        len -= chunk;
        offset = 0;
    }
}

void __bitmap_clear(unsigned long *map, unsigned int start, int len)
{
    BUG_ON(len < 0 || (unsigned int)len > UINT_MAX - start);
    if (!len) return;
    unsigned long *word = map + start / BITS_PER_LONG;
    unsigned int offset = start % BITS_PER_LONG;
    while (len) {
        unsigned int chunk = BITS_PER_LONG - offset;
        if (chunk > (unsigned int)len) chunk = len;
        *word++ &= ~(BITMAP_LAST_WORD_MASK(chunk) << offset);
        len -= chunk;
        offset = 0;
    }
}

void __bitmap_shift_right(unsigned long *dst, const unsigned long *src,
                          unsigned int shift, unsigned int nbits)
{
    size_t words = bitmap_words(nbits);
    if (!words) return;
    if (shift >= nbits) {
        memset(dst, 0, words * sizeof(*dst));
        return;
    }
    size_t off = shift / BITS_PER_LONG;
    unsigned int rem = shift % BITS_PER_LONG;
    unsigned long tail = BITMAP_LAST_WORD_MASK(nbits);
    /* Ascending stores preserve src when dst == src. */
    for (size_t i = 0; i < words - off; i++) {
        size_t from = i + off;
        unsigned long lower = src[from];
        if (from == words - 1) lower &= tail;
        unsigned long upper = 0;
        if (rem && from + 1 < words) {
            upper = src[from + 1];
            if (from + 1 == words - 1) upper &= tail;
            upper <<= BITS_PER_LONG - rem;
        }
        dst[i] = (lower >> rem) | upper;
    }
    memset(dst + words - off, 0, off * sizeof(*dst));
}

void __bitmap_shift_left(unsigned long *dst, const unsigned long *src,
                         unsigned int shift, unsigned int nbits)
{
    size_t words = bitmap_words(nbits);
    if (!words) return;
    if (shift >= nbits) {
        memset(dst, 0, words * sizeof(*dst));
        return;
    }
    size_t off = shift / BITS_PER_LONG;
    unsigned int rem = shift % BITS_PER_LONG;
    /* Descending stores preserve src when dst == src. Tail is unspecified,
     * matching Linux's multiword left shift. */
    for (size_t i = words - off; i > 0; i--) {
        size_t from = i - 1;
        unsigned long lower = rem && from ? src[from - 1] >> (BITS_PER_LONG - rem) : 0;
        dst[from + off] = (src[from] << rem) | lower;
    }
    memset(dst, 0, off * sizeof(*dst));
}

#if BITS_PER_LONG == 64
void bitmap_from_arr32(unsigned long *dst, const u32 *src, unsigned int nbits)
{
    size_t halfwords = nbits / 32 + (nbits % 32 != 0);
    for (size_t i = 0; i < halfwords; i += 2) {
        unsigned long value = src[i];
        if (i + 1 < halfwords) value |= (unsigned long)src[i + 1] << 32;
        dst[i / 2] = value;
    }
    if (nbits % BITS_PER_LONG)
        dst[bitmap_words(nbits) - 1] &= BITMAP_LAST_WORD_MASK(nbits);
}

void bitmap_to_arr32(u32 *dst, const unsigned long *src, unsigned int nbits)
{
    size_t halfwords = nbits / 32 + (nbits % 32 != 0);
    for (size_t i = 0; i < halfwords; i += 2) {
        unsigned long value = src[i / 2];
        dst[i] = (u32)value;
        if (i + 1 < halfwords) dst[i + 1] = (u32)(value >> 32);
    }
    if (nbits % 32) dst[halfwords - 1] &= ~0U >> (32 - nbits % 32);
}
#endif

/* Called repeatedly by the native integration test, with the caller measuring
 * pages around the batches. Every error path releases its owned allocation. */
int vinix_linuxkpi_bitmap_runtime_selftest(void)
{
    unsigned long a[3] = { ~0UL, ~0UL, ~0UL };
    unsigned long b[3] = { 0, 0, ~1UL };
    unsigned long dst[3];
    u32 packed[5];
    int result = -EIO;
    if (__bitmap_intersects(a, b, 129) || __bitmap_weight(b, 129) ||
        !__bitmap_subset(b, a, 129) || __bitmap_and(dst, a, b, 129)) return result;
    if (!__bitmap_andnot(dst, a, b, 129) || dst[2] != 1 ||
        __bitmap_weight(dst, 129) != 129) return result;
    bitmap_to_arr32(packed, a, 129);
    if (packed[4] != 1) return result;
    bitmap_from_arr32(dst, packed, 129);
    if (dst[2] != 1 || !__bitmap_equal(a, dst, 129)) return result;
    __bitmap_shift_right(dst, a, 128, 129);
    if (dst[0] != 1 || dst[1] || dst[2]) return result;
    __bitmap_shift_left(dst, dst, 128, 129);
    if (dst[0] || dst[1] || dst[2] != 1) return result;

    unsigned long *map = bitmap_zalloc(4097, GFP_KERNEL);
    if (!map) return -ENOMEM;
    if (__bitmap_weight(map, 4097)) goto out;
    __bitmap_set(map, 63, 3970);
    if (__bitmap_weight(map, 4097) != 3970) goto out;
    __bitmap_clear(map, 64, 3968);
    if (__bitmap_weight(map, 4097) != 2 || !test_bit(63, map) ||
        !test_bit(4032, map)) goto out;
    __bitmap_shift_right(map, map, 63, 4097);
    if (__bitmap_weight(map, 4097) != 2 || !test_bit(0, map) ||
        !test_bit(3969, map)) goto out;
    __bitmap_shift_left(map, map, 63, 4097);
    if (__bitmap_weight(map, 4097) != 2 || !test_bit(63, map) ||
        !test_bit(4032, map)) goto out;
    result = 0;
out:
    bitmap_free(map);
    return result;
}
#endif
