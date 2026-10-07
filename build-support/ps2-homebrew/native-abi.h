/* SPDX-License-Identifier: MIT */
/* Native memory qualifiers/layout constraints; no C algorithms. */
#ifndef VINIX_PS2_HOMEBREW_NATIVE_ABI_H
#define VINIX_PS2_HOMEBREW_NATIVE_ABI_H
#include <stdint.h>
#include <stddef.h>
struct ps2_volatile_word { volatile uint32_t value; };
struct ps2_volatile_byte { volatile uint8_t value; };
#define PS2_VOLATILE_LAYOUT(type, width) \
    _Static_assert(sizeof(struct type) == width && _Alignof(struct type) == width && \
                   offsetof(struct type, value) == 0, "native volatile memory view")
PS2_VOLATILE_LAYOUT(ps2_volatile_word, 4);
PS2_VOLATILE_LAYOUT(ps2_volatile_byte, 1);
_Static_assert(sizeof(void *) == 4 && sizeof(size_t) == 4 && sizeof(long) == 4,
               "native MIPS pointer/size/long widths");
_Static_assert(sizeof(int) == 4 && sizeof(unsigned) == 4 && sizeof(uint64_t) == 8,
               "native MIPS control/packet widths");
_Static_assert(__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__, "native PS2 little-endian data");
#endif
