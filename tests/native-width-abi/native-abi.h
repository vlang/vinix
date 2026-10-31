/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_NATIVE_WIDTH_ABI_H
#define VINIX_NATIVE_WIDTH_ABI_H

#include <stddef.h>
#include <stdint.h>

_Static_assert(sizeof(size_t) == 8, "Vinix requires a 64-bit size_t");
_Static_assert(sizeof(ptrdiff_t) == 8, "Vinix requires a 64-bit ptrdiff_t");

struct vinix_native_words {
    size_t unsigned_value;
    ptrdiff_t signed_value;
    void *address;
};

#define vinix_native_words_size() sizeof(struct vinix_native_words)
#define vinix_native_signed_offset() offsetof(struct vinix_native_words, signed_value)
#define vinix_native_address_offset() offsetof(struct vinix_native_words, address)

size_t vinix_probe_size_roundtrip(size_t value);
void *vinix_probe_memcpy(void *dest, void *src, size_t length);
void *vinix_probe_memset(void *dest, int value, size_t length);
void *vinix_probe_memmove(void *dest, void *src, size_t length);
int vinix_probe_memcmp(void *first, void *second, size_t length);
void vinix_probe_erase(void *buffer, size_t length);

#endif
