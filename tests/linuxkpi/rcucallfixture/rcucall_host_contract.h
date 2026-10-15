/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_RCU_CALL_HOST_CONTRACT_H
#define VINIX_RCU_CALL_HOST_CONTRACT_H
/* Original records and compiler primitives only. Host transport and tests are
 * V; the production module alone implements queues and grace periods. */
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sched.h>
#include <stdint.h>
#include "linuxkpi_rcu_v_contract.h"
#include "linuxkpi_smp_masks_v_contract.h"
typedef const char *rcuh_const_charp;
typedef const void *rcuh_const_voidp;
#define rcuh_load32(p) __atomic_load_n((p), __ATOMIC_ACQUIRE)
#define rcuh_store32(p,v) __atomic_store_n((p),(v), __ATOMIC_RELEASE)
#define rcuh_add32(p,v) __atomic_fetch_add((p),(v), __ATOMIC_ACQ_REL)
#define rcuh_exchange32(p,v) __atomic_exchange_n((p),(v), __ATOMIC_ACQ_REL)
#define rcuh_compare32(p,old,v) __atomic_compare_exchange_n((p),(old),(v),false,__ATOMIC_ACQ_REL,__ATOMIC_ACQUIRE)
#define rcuh_load64(p) __atomic_load_n((p), __ATOMIC_ACQUIRE)
#define rcuh_store64(p,v) __atomic_store_n((p),(v), __ATOMIC_RELEASE)
#define rcuh_add64(p,v) __atomic_fetch_add((p),(v), __ATOMIC_ACQ_REL)
#define rcuh_head_bytes() sizeof(struct rcu_head)
#define rcuh_head_alignment() _Alignof(struct rcu_head)
#define rcuh_line(s) ((s).str)
#define rcuh_read_lock() rcu_read_lock()
#define rcuh_read_unlock() rcu_read_unlock()
void rcuh_completion_init(void *);
void rcuh_completion_complete(void *);
void rcuh_completion_wait(void *);
/* Exact selected production V body, not a model of its public-cookie rule. */
bool compatcore__rcu_sequence_exact_done(uint64_t, uint64_t);
/* Ordinary-callback regression transport deliberately supplies no generic
 * allocator ownership. Entering a new deferred-free branch fails explicitly;
 * deferred_free.v executes the real page/cache allocator instead. */
size_t vkr_page_allocation_size(void *);
void vkr_kvfree(void *);
_Static_assert(sizeof(struct rcu_head)==16 && _Alignof(struct rcu_head)==8 &&
               offsetof(struct rcu_head,next)==0 && offsetof(struct rcu_head,func)==8,
               "original callback head ABI");
#endif
