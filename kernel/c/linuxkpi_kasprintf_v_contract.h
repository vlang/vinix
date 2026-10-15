/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_KASPRINTF_V_CONTRACT_H
#define VINIX_LINUXKPI_KASPRINTF_V_CONTRACT_H
#define u64 vkh_linux_u64
#include <linux/sprintf.h>
#include <linux/string.h>
#undef u64
#include "linuxkpi_v_primitives.h"
#include "varargs_abi.h"
#include "linuxkpi_kasprintf_v_primitives.h"
#if VINIX_VA_ABI == 3
typedef __typeof__(((va_list *)0)[0][0]) vkf_sysv_record;
_Static_assert(sizeof(va_list) == 24 && _Alignof(va_list) == 8 &&
    offsetof(vkf_sysv_record, gp_offset) == 0 && offsetof(vkf_sysv_record, fp_offset) == 4 &&
    offsetof(vkf_sysv_record, overflow_arg_area) == 8 && offsetof(vkf_sysv_record, reg_save_area) == 16,
    "genuine SysV64 cursor representation");
#elif VINIX_VA_ABI == 2
_Static_assert(sizeof(va_list) == 32 && _Alignof(va_list) == 8 &&
    offsetof(va_list, __stack) == 0 && offsetof(va_list, __gr_top) == 8 &&
    offsetof(va_list, __vr_top) == 16 && offsetof(va_list, __gr_offs) == 24 &&
    offsetof(va_list, __vr_offs) == 28, "genuine AAPCS64 cursor representation");
#else
_Static_assert(sizeof(va_list) == sizeof(void *) && _Alignof(va_list) == 8,
    "genuine Darwin ARM64 cursor representation");
#endif
_Static_assert(sizeof(va_list) <= 32 && _Alignof(va_list) <= 8,
    "fixed stack cursor capacity/alignment");
_Static_assert(__builtin_types_compatible_p(gfp_t, unsigned int), "original GFP type");
_Static_assert(__builtin_types_compatible_p(__typeof__(&kvasprintf),
    char *(*)(gfp_t, const char *, va_list)), "original kvasprintf signature");
_Static_assert(__builtin_types_compatible_p(__typeof__(&kvasprintf_const),
    const char *(*)(gfp_t, const char *, va_list)), "original kvasprintf_const signature");
_Static_assert(__builtin_types_compatible_p(__typeof__(&kasprintf),
    char *(*)(gfp_t, const char *, ...)), "original kasprintf signature");
#endif
