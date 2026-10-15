/* SPDX-License-Identifier: MIT */
#ifndef VINIX_SW_FENCE_HOST_CONTRACT_H
#define VINIX_SW_FENCE_HOST_CONTRACT_H
#if defined(VINIX_SW_FENCE_PRINTK_TRANSPORT) || defined(VINIX_SW_FENCE_ORIGINAL_NOTICE)
#include <stdint.h>
struct seq_file;
#include <linux/slab.h>
#include <linux/dma-fence.h>
#include <linux/irq_work.h>
#include <linux/dma-resv.h>
#include "i915_sw_fence.h"
#include "i915_selftest.h"
int swh_printk(const char *,const char *,const char *,uint64_t,void *);
#ifdef VINIX_SW_FENCE_PRINTK_TRANSPORT
#define _printk swh_printk
#endif
#else
#include "../resvfixture/contract.h"
#define u64 vkh_linux_u64
#include "i915_sw_fence.h"
#include <linux/timer.h>
#undef u64
typedef enum i915_sw_fence_notify swh_notify;
_Static_assert(__builtin_types_compatible_p(swh_notify,enum i915_sw_fence_notify),"original notify enum ABI");
_Static_assert(__builtin_types_compatible_p(i915_sw_fence_notify_t,int (*)(struct i915_sw_fence *,swh_notify)),"original callback ABI");
_Static_assert(sizeof(struct i915_sw_fence)==40 && offsetof(struct i915_sw_fence,fn)==24 && offsetof(struct i915_sw_fence,pending)==32 && offsetof(struct i915_sw_fence,error)==36,"original SW fence ABI");
_Static_assert(sizeof(struct i915_sw_dma_fence_cb)==32 && sizeof(wait_queue_entry_t)==40,"original dependency ABI");
#define swh_pending(f) atomic_read(&(f)->pending)
#define swh_error(f) ((f)->error)
#define swh_wait_empty(f) list_empty(&(f)->wait.head)
#define swh_jiffies() READ_ONCE(jiffies)
#define swh_expected_notice() (KERN_NOTICE "Asynchronous wait on fence %s:%s:%llx timed out (hint:%ps)\n")
#define swh_set_error(f,v) i915_sw_fence_set_error_once((f),(v))
/* Exact private timed-owner record from unchanged i915_sw_fence.c, data only. */
struct swh_timed_owner { struct i915_sw_dma_fence_cb base; struct dma_fence *dma; struct timer_list timer; struct irq_work work; struct rcu_head rcu; };
#define swh_timed_callback(f) ((struct swh_timed_owner *)list_first_entry(&(f)->cb_list,struct dma_fence_cb,node))
#define swh_timed_work(c) (&((struct swh_timed_owner *)(c))->work)
_Static_assert(sizeof(struct swh_timed_owner)==128 && offsetof(struct swh_timed_owner,timer)==40 && offsetof(struct swh_timed_owner,work)==80 && offsetof(struct swh_timed_owner,rcu)==112,"original timed callback owner ABI");
int swh_printk(const char *,const char *,const char *,uint64_t,void *);
#endif /* generated V fixture metadata */
#endif
