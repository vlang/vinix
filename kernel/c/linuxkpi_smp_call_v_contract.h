/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_SMP_CALL_V_CONTRACT_H
#define VINIX_LINUXKPI_SMP_CALL_V_CONTRACT_H
#include "linuxkpi_common_v_contract.h"
#include "linuxkpi_smp_call_v_primitives.h"
#include <linux/smp.h>
#include <linux/gfp_types.h>
typedef const struct cpumask *vks_smp_const_cpumask;

_Static_assert(NR_CPUS == VKS_SMP_CPU_LIMIT && BITS_PER_LONG == 64,
               "native fixed boot CPU profile");
_Static_assert(sizeof(struct __call_single_node) == 16 &&
               offsetof(struct __call_single_node, llist) == 0 &&
               offsetof(struct __call_single_node, u_flags) == 8 &&
               offsetof(struct __call_single_node, src) == 12 &&
               offsetof(struct __call_single_node, dst) == 14,
               "original CSD node field ABI");
_Static_assert(sizeof(struct __call_single_data) == VKS_SMP_CSD_BYTES &&
               _Alignof(struct __call_single_data) == 8 &&
               offsetof(struct __call_single_data, node) == 0 &&
               offsetof(struct __call_single_data, func) == 16 &&
               offsetof(struct __call_single_data, info) == 24 &&
               sizeof(call_single_data_t) == VKS_SMP_CSD_BYTES &&
               _Alignof(call_single_data_t) == VKS_SMP_CSD_ALIGN,
               "original natural record and aligned typedef ABI");
_Static_assert(sizeof(struct cpumask) == 4 * sizeof(uint64_t),
               "original full four-word CPU mask");
_Static_assert(CSD_FLAG_LOCK == VKS_SMP_LOCK &&
               CSD_TYPE_SYNC == VKS_SMP_SYNC && CSD_TYPE_ASYNC == 0 &&
               CSD_FLAG_TYPE_MASK == VKS_SMP_TYPE_MASK,
               "original CSD lock and dispatch classes");
_Static_assert(GFP_KERNEL == VKS_SMP_GFP_KERNEL,
               "fallible boot allocation uses genuine GFP_KERNEL");
_Static_assert(sizeof(int) == sizeof(int32_t) && sizeof(void *) == 8 &&
               __builtin_types_compatible_p(vks_smp_call_fn, smp_call_func_t) &&
               __builtin_types_compatible_p(vks_smp_cond_fn, smp_cond_func_t),
               "original public integer and callback signatures");

/* Original compound literal, written to original strongly aligned storage. */
#define vks_smp_stack_init(csd) \
    (*(csd) = (struct __call_single_data){ \
        .node = { .u_flags = CSD_FLAG_LOCK | CSD_TYPE_SYNC } })
#define vks_smp_borrow_mask(mask) ((vks_smp_const_void)(mask))
#define vks_smp_original_online_mask() \
    ((vks_smp_const_void)cpu_online_mask)
#endif
