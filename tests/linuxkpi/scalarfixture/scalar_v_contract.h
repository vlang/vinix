/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Native scalar/type metadata only; all executable fixture logic lives in V. */
#ifndef VINIX_SCALAR_V_CONTRACT_H
#define VINIX_SCALAR_V_CONTRACT_H
#define u64 vsh_linux_u64
#define timezone vsh_linux_timezone
#define ffs vsh_linux_ffs
#define fls vsh_linux_fls
#ifdef VSH_UAPI_FIRST
#include <uapi/linux/types.h>
#endif
#include <linux/types.h>
#include <uapi/linux/types.h>
#include <linux/types.h>
#include <linux/kernel.h>
#include <linux/err.h>
#include <uapi/linux/resource.h>
#include <asm/resource.h>
#include <assert.h>
#include <stdio.h>
typedef const void *vsh_constp;
/* Native cast metadata for V's opaque foreign const-pointer spelling. */
#define vsh_as_const(pointer) ((const void *)(pointer))
typedef umode_t vsh_umode;
typedef volatile u16 vsh_volatile_u16;
typedef volatile u32 vsh_volatile_u32;
typedef volatile u64 vsh_volatile_u64;
typedef struct vsh_error_calls {
    void *(*cast)(const void *);
    void *(*create)(long);
    long (*decode)(const void *);
    bool (*classify)(const void *);
} vsh_error_calls;
_Static_assert(sizeof(umode_t) == 2 && (umode_t)-1 > 0, "unsigned sixteen-bit umode_t");
_Static_assert(__builtin_types_compatible_p(umode_t, unsigned short), "original unsigned-short type");
_Static_assert(__builtin_types_compatible_p(__typeof__(ERR_CAST), void *(const void *)), "native ERR_CAST ABI");
_Static_assert(__builtin_types_compatible_p(__typeof__(((vsh_error_calls *)0)->cast), void *(*)(const void *)), "typed const-pointer call");
_Static_assert(__builtin_types_compatible_p(__typeof__(upper_32_bits((u16)0)), u32), "u16 upper result");
_Static_assert(__builtin_types_compatible_p(__typeof__(upper_32_bits((u32)0)), u32), "u32 upper result");
_Static_assert(__builtin_types_compatible_p(__typeof__(upper_32_bits((u64)0)), u32), "u64 upper result");
_Static_assert(__builtin_types_compatible_p(__typeof__(lower_32_bits((u16)0)), u32), "u16 lower result");
_Static_assert(__builtin_types_compatible_p(__typeof__(lower_32_bits((u32)0)), u32), "u32 lower result");
_Static_assert(__builtin_types_compatible_p(__typeof__(lower_32_bits((u64)0)), u32), "u64 lower result");
_Static_assert(upper_32_bits((u32)0xffffffff) == 0, "split shifts on a 32-bit operand");
_Static_assert(upper_32_bits(0x12345678abcdef01ULL) == 0x12345678U, "original upper constant expression");
_Static_assert(lower_32_bits(0x12345678abcdef01ULL) == 0xabcdef01U, "original lower constant expression");
_Static_assert(sizeof(RLIM_INFINITY) == 8 && __builtin_types_compatible_p(__typeof__(RLIM_INFINITY), unsigned long), "original unsigned-long infinity");
_Static_assert(sizeof(struct rlimit) == 16 && sizeof(struct rlimit64) == 16, "original resource records");
_Static_assert(__builtin_offsetof(struct rlimit, rlim_max) == 8 && __builtin_offsetof(struct rlimit64, rlim_max) == 8, "original resource field offsets");
#undef u64
#undef timezone
#undef ffs
#undef fls
#endif
