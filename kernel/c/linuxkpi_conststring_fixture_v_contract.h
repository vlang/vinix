/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_CONSTSTRING_FIXTURE_V_CONTRACT_H
#define VINIX_LINUXKPI_CONSTSTRING_FIXTURE_V_CONTRACT_H
#include "linuxkpi_common_v_contract.h"
#define u64 vkh_linux_u64
#include "linuxkpi_const_string_v_contract.h"
#include <linux/slab.h>
#undef u64
#include "symbols.h"
#include "linuxkpi_conststring_fixture_v_primitives.h"

/* Constant metadata avoids foreign-global declarations in the V producer. */
#define vinix_conststring_gfp_kernel() ((uint32_t)GFP_KERNEL)
_Static_assert(sizeof(uintptr_t) == sizeof(void *) && sizeof(uintptr_t) == 8,
               "native const-string fixture address width");
_Static_assert(__builtin_types_compatible_p(__typeof__(&kfree_const),
               void (*)(const void *)), "original const-string release ABI");
_Static_assert(__builtin_types_compatible_p(__typeof__(&kstrdup_const),
               const char *(*)(const char *, gfp_t)), "original const-string duplicate ABI");
#endif
