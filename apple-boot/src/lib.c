// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "lib.h"

#ifndef APPLE_BOOT_HOST

/* Word copies only when both sides share the same alignment, so a copy never
 * issues an unaligned access while the MMU is off. */
void *memcpy(void *dest, const void *src, size_t count)
{
    uint8_t *out = dest;
    const uint8_t *in = src;

    if ((((uintptr_t)out ^ (uintptr_t)in) & 7) == 0) {
        while (count && ((uintptr_t)out & 7)) {
            *out++ = *in++;
            count--;
        }
        while (count >= 8) {
            *(uint64_t *)(void *)out = *(const uint64_t *)(const void *)in;
            out += 8;
            in += 8;
            count -= 8;
        }
    }
    while (count--)
        *out++ = *in++;
    return dest;
}

void *memmove(void *dest, const void *src, size_t count)
{
    uint8_t *out = dest;
    const uint8_t *in = src;

    if (out <= in || out >= in + count)
        return memcpy(dest, src, count);
    while (count--)
        out[count] = in[count];
    return dest;
}

void *memset(void *dest, int value, size_t count)
{
    uint8_t *out = dest;
    uint64_t pattern = (uint8_t)value;

    pattern |= pattern << 8;
    pattern |= pattern << 16;
    pattern |= pattern << 32;
    while (count && ((uintptr_t)out & 7)) {
        *out++ = (uint8_t)value;
        count--;
    }
    while (count >= 8) {
        *(uint64_t *)(void *)out = pattern;
        out += 8;
        count -= 8;
    }
    while (count--)
        *out++ = (uint8_t)value;
    return dest;
}

int memcmp(const void *left, const void *right, size_t count)
{
    const uint8_t *a = left;
    const uint8_t *b = right;

    for (size_t index = 0; index < count; index++) {
        if (a[index] != b[index])
            return a[index] < b[index] ? -1 : 1;
    }
    return 0;
}

size_t strlen(const char *text)
{
    size_t length = 0;

    while (text[length])
        length++;
    return length;
}

int strcmp(const char *left, const char *right)
{
    while (*left && *left == *right) {
        left++;
        right++;
    }
    return (uint8_t)*left - (uint8_t)*right;
}

#endif

size_t lib_strnlen(const char *text, size_t limit)
{
    size_t length = 0;

    while (length < limit && text[length])
        length++;
    return length;
}
