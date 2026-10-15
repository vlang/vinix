/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_CONST_STRING_V_CONTRACT_H
#define VINIX_LINUXKPI_CONST_STRING_V_CONTRACT_H
#include <linux/string.h>
#include "linuxkpi_v_primitives.h"
#include "linuxkpi_const_string_v_primitives.h"

typedef const char *vkc_const_char_p;

_Static_assert(sizeof(void *) == 8 && sizeof(unsigned long) == 8,
               "native const-string address width");
_Static_assert(__builtin_types_compatible_p(gfp_t, unsigned int) &&
               __builtin_types_compatible_p(uint32_t, unsigned int),
               "original GFP and raw backend flag types");
_Static_assert(__builtin_types_compatible_p(__typeof__(&kfree_const),
               void (*)(const void *)), "original kfree_const signature");
_Static_assert(__builtin_types_compatible_p(__typeof__(&kstrdup_const),
               const char *(*)(const char *, gfp_t)), "original kstrdup_const signature");
_Static_assert(__builtin_types_compatible_p(__typeof__(&vkc_kfree_const),
               void (*)(void *)), "raw kfree_const backend signature");
_Static_assert(__builtin_types_compatible_p(__typeof__(&vkc_kstrdup_const),
               void *(*)(void *, unsigned int)), "raw kstrdup_const backend signature");
_Static_assert(__builtin_types_compatible_p(__typeof__(&vinix_linuxkpi_is_kernel_rodata),
               bool (*)(const void *)), "native rodata interval query signature");
#endif
