/* SPDX-License-Identifier: MIT */
/* Actual native MIPS declarations and assertions; no C algorithms. */
#ifndef VINIX_N64_PADDLE_NATIVE_ABI_H
#define VINIX_N64_PADDLE_NATIVE_ABI_H
#include <stdint.h>
#include <stddef.h>
struct n64_volatile_word { volatile uint32_t value; };
struct n64_volatile_byte { volatile uint8_t value; };
struct n64_volatile_half { volatile uint16_t value; };
#define N64_VOLATILE_LAYOUT(type, width) \
    _Static_assert(sizeof(struct type) == width && _Alignof(struct type) == width && \
                   offsetof(struct type, value) == 0, "native volatile memory view")
N64_VOLATILE_LAYOUT(n64_volatile_word, 4);
N64_VOLATILE_LAYOUT(n64_volatile_byte, 1);
N64_VOLATILE_LAYOUT(n64_volatile_half, 2);
void n64_sync(void);
_Static_assert(sizeof(void *) == 4 && sizeof(size_t) == 4, "native o32 pointer/size width");
_Static_assert(sizeof(int) == 4 && sizeof(unsigned) == 4 && sizeof(uint16_t) == 2,
               "native o32 control/pixel words");
_Static_assert(__BYTE_ORDER__ == __ORDER_BIG_ENDIAN__, "native MIPS big-endian data");
_Static_assert(_MIPS_SIM == _ABIO32 && _MIPS_ARCH_MIPS3 == 1, "native MIPS III/o32");
#endif
