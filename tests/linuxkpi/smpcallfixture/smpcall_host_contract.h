/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_SMP_CALL_HOST_CONTRACT_H
#define VINIX_SMP_CALL_HOST_CONTRACT_H
/* Host context and original-record compiler metadata only. Transport and all
 * assertions are V; the production backend alone owns queue algorithms. */
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sched.h>
#undef atomic_fetch_add
#undef atomic_fetch_sub
#undef atomic_fetch_and
#undef atomic_fetch_or
#undef atomic_fetch_xor
#undef atomic_exchange
#undef atomic_compare_exchange_strong
#undef atomic_compare_exchange_weak
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmacro-redefined"
#endif
#define timezone smph_linux_timezone
#define ffs smph_linux_ffs
#define fls smph_linux_fls
#include <linux/smp.h>
#undef fls
#undef ffs
#undef timezone
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
#include "linuxkpi_smp_call_v_primitives.h"
#include "linuxkpi_smp_masks_v_primitives.h"
typedef const char *smph_const_charp;

#define smph_load32(p) __atomic_load_n((p), __ATOMIC_ACQUIRE)
#define smph_store32(p, v) __atomic_store_n((p), (v), __ATOMIC_RELEASE)
#define smph_add32(p, v) __atomic_fetch_add((p), (v), __ATOMIC_ACQ_REL)
#define smph_load_flags(p) __atomic_load_n(&((p)->node.u_flags), __ATOMIC_ACQUIRE)
#define smph_set_flags(p, v) __atomic_store_n(&((p)->node.u_flags), (v), __ATOMIC_RELEASE)
#define smph_init(p, f, i) INIT_CSD((p), (f), (i))
#define smph_flags_addr(p) (&((p)->node.u_flags))
#define smph_csd_bytes() sizeof(call_single_data_t)
#define smph_csd_alignment() _Alignof(call_single_data_t)
#define smph_mask_bits(p) ((p)->bits)
#define smph_key_bytes() sizeof(pthread_key_t)
#define smph_line_value(s) ((s).str)
#define smph_mutex_init(p) pthread_mutex_init((p), NULL)
#define smph_cond_init(p) pthread_cond_init((p), NULL)
_Static_assert(sizeof(call_single_data_t) == 32 &&
               _Alignof(call_single_data_t) == 32 &&
               sizeof(struct cpumask) == 32, "genuine pinned SMP records");
#endif
