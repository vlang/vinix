/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_HEADER_PRIMITIVE_V_CONTRACT_H
#define VINIX_LINUXKPI_HEADER_PRIMITIVE_V_CONTRACT_H
#include "linuxkpi_common_v_contract.h"
#include <linux/slab.h>
#include <vinix/runtime.h>
typedef s64 vhp_s64;
typedef const atomic_t *vhp_const_atomicp;
typedef const atomic64_t *vhp_const_atomic64p;
typedef const spinlock_t *vhp_const_spinp;
typedef const struct task_struct *vhp_const_taskp;
typedef const void *vhp_const_voidp;
_Static_assert(sizeof(vhp_s64)==8 && sizeof(atomic_t)==4 && sizeof(atomic64_t)==8, "native atomic storage widths");
_Static_assert(sizeof(spinlock_t)==4 && sizeof(unsigned long)==8 && sizeof(size_t)==8, "native primitive word widths");
_Static_assert(__builtin_offsetof(atomic_t,counter)==0 && __builtin_offsetof(atomic64_t,counter)==0 && __builtin_offsetof(spinlock_t,locked)==0, "native primitive fields");
#endif
