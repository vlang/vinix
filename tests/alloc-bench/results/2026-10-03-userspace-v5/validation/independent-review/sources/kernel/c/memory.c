#include <stdint.h>
#include <stddef.h>
#include <string.h>

// may_alias keeps word accesses valid for arbitrary object representations.
// Word operations use only naturally aligned addresses and stay entirely in
// the requested range; byte prefixes/tails never access a neighbouring page.
typedef uint64_t memory_word __attribute__((__may_alias__));

void *memcpy(void *restrict dest, const void *restrict src, size_t n) {
    uint8_t *restrict pdest = (uint8_t *restrict)dest;
    const uint8_t *restrict psrc = (const uint8_t *restrict)src;

    // Different alignments cannot both be advanced to a word boundary.
    if ((((uintptr_t)pdest ^ (uintptr_t)psrc) & 7) == 0) {
        while (n && ((uintptr_t)pdest & 7)) {
            *pdest++ = *psrc++;
            n--;
        }
        if (n >= 8) {
            memory_word *restrict d = (memory_word *restrict)pdest;
            const memory_word *restrict s = (const memory_word *restrict)psrc;
            while (n >= 64) {
                d[0] = s[0]; d[1] = s[1]; d[2] = s[2]; d[3] = s[3];
                d[4] = s[4]; d[5] = s[5]; d[6] = s[6]; d[7] = s[7];
                d += 8;
                s += 8;
                n -= 64;
            }
            while (n >= 8) {
                *d++ = *s++;
                n -= 8;
            }
            pdest = (uint8_t *)d;
            psrc = (const uint8_t *)s;
        }
    }
    while (n--) {
        *pdest++ = *psrc++;
    }
    return dest;
}

void *memset(void *s, int c, size_t n) {
    uint8_t *p = (uint8_t *)s;
    const uint8_t byte = (uint8_t)c;
    while (n && ((uintptr_t)p & 7)) {
        *p++ = byte;
        n--;
    }
    if (n >= 8) {
        const memory_word fill = (memory_word)byte * 0x0101010101010101ULL;
        memory_word *w = (memory_word *)p;
        while (n >= 64) {
            w[0] = fill; w[1] = fill; w[2] = fill; w[3] = fill;
            w[4] = fill; w[5] = fill; w[6] = fill; w[7] = fill;
            w += 8;
            n -= 64;
        }
        while (n >= 8) {
            *w++ = fill;
            n -= 8;
        }
        p = (uint8_t *)w;
    }
    while (n--) {
        *p++ = byte;
    }
    return s;
}

void *memmove(void *dest, const void *src, size_t n) {
    uint8_t *pdest = (uint8_t *)dest;
    const uint8_t *psrc = (const uint8_t *)src;

    if (src > dest) {
        for (size_t i = 0; i < n; i++) {
            pdest[i] = psrc[i];
        }
    } else if (src < dest) {
        for (size_t i = n; i > 0; i--) {
            pdest[i-1] = psrc[i-1];
        }
    }

    return dest;
}

int memcmp(const void *s1, const void *s2, size_t n) {
    const uint8_t *p1 = (const uint8_t *)s1;
    const uint8_t *p2 = (const uint8_t *)s2;

    for (size_t i = 0; i < n; i++) {
        if (p1[i] != p2[i]) {
            return p1[i] < p2[i] ? -1 : 1;
        }
    }

    return 0;
}

int atoi(const char *text) {
    int sign = 1;
    int value = 0;

    while (*text == ' ' || *text == '\t' || *text == '\n' ||
           *text == '\r' || *text == '\f' || *text == '\v') {
        text++;
    }
    if (*text == '-' || *text == '+') {
        if (*text++ == '-') {
            sign = -1;
        }
    }
    while (*text >= '0' && *text <= '9') {
        value = value * 10 + (*text++ - '0');
    }
    return value * sign;
}
