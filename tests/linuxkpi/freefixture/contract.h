/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_DEFERRED_FREE_HOST_CONTRACT_H
#define VINIX_DEFERRED_FREE_HOST_CONTRACT_H
/* Declarations, original layouts and compiler intrinsics only. The allocator,
 * grace periods, intrusive queue and all host observations are V. */
#include "rcucall_host_contract.h"
#include <linux/slab.h>
#include <linux/rcupdate.h>
void *vkr_kmalloc(size_t, unsigned int);
size_t vkr_page_allocation_size(void *);
void vkr_kvfree(void *);
void vkr_kvfree_call_rcu(void *, void *);
struct frh_embedded { uint64_t prefix; struct rcu_head head; uint64_t payload; };
_Static_assert(__builtin_types_compatible_p(__typeof__(&kvfree), void (*)(const void *)), "original kvfree signature");
_Static_assert(__builtin_types_compatible_p(__typeof__(&kvfree_call_rcu), void (*)(struct rcu_head *, void *)), "original deferred free signature");
#define frh_bad_callback(b) ((rcu_callback_t)(uintptr_t)(b))
extern uint64_t compatcore__vkr_rcu_enqueued;
#endif
