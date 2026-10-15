/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_RCU_V_CONTRACT_H
#define VINIX_LINUXKPI_RCU_V_CONTRACT_H
#include "linuxkpi_task_v_contract.h"
#include <linux/sched/task.h>
#include "linuxkpi_rcu_v_primitives.h"

_Static_assert(sizeof(struct callback_head) == 16 &&
               _Alignof(struct callback_head) == 8 &&
               offsetof(struct callback_head, next) == 0 &&
               offsetof(struct callback_head, func) == 8 &&
               sizeof(struct vkr_rcu_head) == sizeof(struct callback_head) &&
               _Alignof(struct vkr_rcu_head) == _Alignof(struct callback_head) &&
               offsetof(struct vkr_rcu_head, next) == offsetof(struct callback_head, next) &&
               offsetof(struct vkr_rcu_head, func) == offsetof(struct callback_head, func),
               "original intrusive RCU callback ABI");
_Static_assert(__builtin_types_compatible_p(vkr_rcu_callback_fn, rcu_callback_t),
               "original RCU callback signature");
_Static_assert(sizeof(unsigned long) == sizeof(uint64_t) &&
               __builtin_types_compatible_p(size_t, unsigned long) &&
               CONFIG_NR_CPUS == 256 && TASK_DEAD == 128,
               "native fixed boot RCU profile");

/* Genuine public signatures. CONFIG_TREE_RCU selects the original SMP reader
 * ABI; these native exports do not import Linux's tree backend or supply
 * PREEMPT_RCU, hotplug, BH, NMI or generic VM/cache allocation ownership. */
void call_rcu(struct rcu_head *, rcu_callback_t);
/* Native kvfree currently accepts page-backed kmalloc owners only. */
void kvfree(const void *);
void kvfree_call_rcu(struct rcu_head *, void *);
void synchronize_rcu(void);
void synchronize_rcu_expedited(void);
void rcu_barrier(void);
unsigned long get_state_synchronize_rcu(void);
unsigned long start_poll_synchronize_rcu(void);
bool poll_state_synchronize_rcu(unsigned long);
void cond_synchronize_rcu(unsigned long);
#endif
