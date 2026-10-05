/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_SRCU_V_CONTRACT_H
#define VINIX_LINUXKPI_SRCU_V_CONTRACT_H
/* Linux and the V backend use distinct names for their native 64-bit typedefs.
 * This changes names only; the upstream declarations/layouts stay intact. */
/* C11 and Linux use the same spellings for different atomic interfaces. */
#undef atomic_fetch_add
#undef atomic_fetch_sub
#undef atomic_fetch_and
#undef atomic_fetch_or
#undef atomic_fetch_xor
#undef atomic_exchange
#undef atomic_compare_exchange_strong
#undef atomic_compare_exchange_weak
#define u64 vkh_linux_u64
#define timezone vkh_linux_timezone
#define ffs vkh_linux_ffs
#define fls vkh_linux_fls
#if defined(__clang__) && defined(VINIX_LINUXKPI_HOST_TEST)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmacro-redefined"
#endif
#include <linux/srcu.h>
#include <linux/percpu.h>
#include <linux/sched.h>
#if defined(__clang__) && defined(VINIX_LINUXKPI_HOST_TEST)
#pragma clang diagnostic pop
#endif
#undef fls
#undef ffs
#undef timezone
#undef u64
#include "linuxkpi_srcu_v_primitives.h"
#define VKS_SIZE(view, native) _Static_assert(sizeof(struct view) == sizeof(struct native), #view " size"); _Static_assert(_Alignof(struct view) == _Alignof(struct native), #view " alignment")
#define VKS_FIELD(view, native, field) _Static_assert(offsetof(struct view, field) == offsetof(struct native, field), #view "." #field " offset")
VKS_SIZE(vks_rcu_head, rcu_head);
VKS_FIELD(vks_rcu_head, rcu_head, next);
VKS_FIELD(vks_rcu_head, rcu_head, func);
VKS_SIZE(vks_cblist, rcu_segcblist);
VKS_FIELD(vks_cblist, rcu_segcblist, head);
VKS_FIELD(vks_cblist, rcu_segcblist, tails);
VKS_FIELD(vks_cblist, rcu_segcblist, gp_seq);
VKS_FIELD(vks_cblist, rcu_segcblist, len);
VKS_FIELD(vks_cblist, rcu_segcblist, seglen);
VKS_FIELD(vks_cblist, rcu_segcblist, flags);
VKS_SIZE(vks_work, work_struct);
VKS_FIELD(vks_work, work_struct, data);
VKS_FIELD(vks_work, work_struct, entry);
VKS_FIELD(vks_work, work_struct, func);
VKS_SIZE(vks_timer, timer_list);
_Static_assert(offsetof(struct vks_timer, next) == offsetof(struct timer_list, entry.next), "timer next");
_Static_assert(offsetof(struct vks_timer, pprev) == offsetof(struct timer_list, entry.pprev), "timer pprev");
VKS_FIELD(vks_timer, timer_list, expires);
VKS_FIELD(vks_timer, timer_list, function);
VKS_FIELD(vks_timer, timer_list, flags);
VKS_SIZE(vks_delayed_work, delayed_work);
VKS_FIELD(vks_delayed_work, delayed_work, work);
VKS_FIELD(vks_delayed_work, delayed_work, timer);
VKS_FIELD(vks_delayed_work, delayed_work, wq);
VKS_FIELD(vks_delayed_work, delayed_work, cpu);
VKS_SIZE(vks_srcu_data, srcu_data);
VKS_FIELD(vks_srcu_data, srcu_data, srcu_lock_count);
VKS_FIELD(vks_srcu_data, srcu_data, srcu_unlock_count);
VKS_FIELD(vks_srcu_data, srcu_data, lock);
VKS_FIELD(vks_srcu_data, srcu_data, srcu_cblist);
VKS_FIELD(vks_srcu_data, srcu_data, srcu_gp_seq_needed);
VKS_FIELD(vks_srcu_data, srcu_data, srcu_gp_seq_needed_exp);
VKS_FIELD(vks_srcu_data, srcu_data, srcu_cblist_invoking);
VKS_FIELD(vks_srcu_data, srcu_data, work);
VKS_FIELD(vks_srcu_data, srcu_data, mynode);
VKS_FIELD(vks_srcu_data, srcu_data, grpmask);
VKS_FIELD(vks_srcu_data, srcu_data, cpu);
VKS_FIELD(vks_srcu_data, srcu_data, ssp);
VKS_SIZE(vks_srcu_usage, srcu_usage);
VKS_FIELD(vks_srcu_usage, srcu_usage, node);
VKS_FIELD(vks_srcu_usage, srcu_usage, level);
VKS_FIELD(vks_srcu_usage, srcu_usage, srcu_size_state);
VKS_FIELD(vks_srcu_usage, srcu_usage, srcu_cb_mutex);
VKS_FIELD(vks_srcu_usage, srcu_usage, lock);
VKS_FIELD(vks_srcu_usage, srcu_usage, srcu_gp_mutex);
VKS_FIELD(vks_srcu_usage, srcu_usage, srcu_gp_seq);
VKS_FIELD(vks_srcu_usage, srcu_usage, srcu_gp_seq_needed);
VKS_FIELD(vks_srcu_usage, srcu_usage, srcu_gp_seq_needed_exp);
VKS_FIELD(vks_srcu_usage, srcu_usage, sda_is_static);
VKS_FIELD(vks_srcu_usage, srcu_usage, srcu_barrier_seq);
VKS_FIELD(vks_srcu_usage, srcu_usage, srcu_barrier_mutex);
VKS_FIELD(vks_srcu_usage, srcu_usage, srcu_barrier_completion);
VKS_FIELD(vks_srcu_usage, srcu_usage, srcu_barrier_cpu_cnt);
VKS_FIELD(vks_srcu_usage, srcu_usage, work);
VKS_FIELD(vks_srcu_usage, srcu_usage, srcu_ssp);
VKS_SIZE(vks_srcu, srcu_struct);
VKS_FIELD(vks_srcu, srcu_struct, srcu_idx);
VKS_FIELD(vks_srcu, srcu_struct, sda);
VKS_FIELD(vks_srcu, srcu_struct, srcu_sup);
_Static_assert(RCU_NUM_LVLS == 2 && RCU_CBLIST_NSEGS == 4, "pinned SRCU dimensions");

struct vks_data_alignment_probe { char prefix; struct srcu_data data; };
void vinix_linuxkpi_srcu_gp_work(void *);
void vinix_linuxkpi_srcu_callback_work(void *);
#endif
