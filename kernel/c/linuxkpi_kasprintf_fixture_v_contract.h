/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_KASPRINTF_FIXTURE_V_CONTRACT_H
#define VINIX_LINUXKPI_KASPRINTF_FIXTURE_V_CONTRACT_H
#include "linuxkpi_common_v_contract.h"
#define u64 vkh_linux_u64
#include "linuxkpi_kasprintf_v_contract.h"
#include "linuxkpi_const_string_v_contract.h"
#include <linux/slab.h>
#undef u64
#include "linuxkpi_kasprintf_fixture_v_primitives.h"
#define vinix_kasprintf_gfp_kernel() ((uint32_t)GFP_KERNEL)
#define vinix_kasprintf_va_storage(ap) ((void *)&(ap))
#define vinix_kasprintf_descriptor_storage(record) ((void *)&(record))
_Static_assert(sizeof(va_list)<=32 && _Alignof(va_list)<=8,"native stack cursor capacity");
_Static_assert(__builtin_types_compatible_p(__typeof__(&kasprintf),char *(*)(gfp_t,const char *,...)),"original named-two public variadic ABI");
_Static_assert(__builtin_types_compatible_p(__typeof__(&kvasprintf_const),const char *(*)(gfp_t,const char *,va_list)),"original const variadic allocation ABI");
_Static_assert(__builtin_types_compatible_p(__typeof__(((struct va_format *)0)->fmt),const char *),"original nested format pointer ABI");
_Static_assert(__builtin_types_compatible_p(__typeof__(((struct va_format *)0)->va),va_list *),"original nested borrowed cursor pointer ABI");
#endif
