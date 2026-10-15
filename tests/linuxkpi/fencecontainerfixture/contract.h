/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_FENCE_CONTAINER_HOST_CONTRACT_H
#define VINIX_FENCE_CONTAINER_HOST_CONTRACT_H
/* Metadata, compiler intrinsics and unchanged original-inline adapters only. */
#include "../freefixture/contract.h"
#include "linuxkpi_dma_fence_v_contract.h"
#include "linuxkpi_task_v_contract.h"
#include "linuxkpi_irq_work_v_contract.h"
#include <linux/dma-fence-array.h>
#include <linux/dma-fence-chain.h>
#include "linuxkpi_dma_fence_chain_v_primitives.h"
#define dfh_flags(f) __atomic_load_n(&(f)->flags, __ATOMIC_ACQUIRE)
#define dfh_refcount(f) refcount_read(&(f)->refcount.refcount)
#define dfh_cb_empty(c) list_empty(&(c)->node)
#define dfh_list_empty(f) list_empty(&(f)->cb_list)
#define dfh_lock_held(f) __atomic_load_n(&(f)->lock->locked, __ATOMIC_ACQUIRE)
#define dfh_set_flags(f,v) __atomic_store_n(&(f)->flags,(v),__ATOMIC_RELEASE)
#define dfh_timestamp(f) dma_fence_timestamp(f)
#define dfh_error(f) ((f)->error)
_Static_assert(sizeof(struct dma_fence)==64 && sizeof(struct dma_fence_cb)==24 &&
               sizeof(struct dma_fence_ops)==80,"original fence ABI");
extern uint32_t compatcore__vkiw_guard;
#define fch_irq_guard() ((void *)&compatcore__vkiw_guard)
#define fch_array_base(a) (&(a)->base)
#define fch_array_pending(a) atomic_read(&(a)->num_pending)
#define fch_array_count(a) ((a)->num_fences)
#define fch_array_fences(a) ((a)->fences)
#define fch_array_work(a) (&(a)->work)
#define fch_chain_base(c) (&(c)->base)
#define fch_chain_prev(c) rcu_access_pointer((c)->prev)
#define fch_chain_prev_seqno(c) ((c)->prev_seqno)
#define fch_chain_fence(c) ((c)->fence)
#define fch_chain_work(c) (&(c)->work)
#define fch_chain_callback(c) (&(c)->cb)
#define fch_chain_prev_address(c) ((void **)&(c)->prev)
#define fch_fence_context(f) ((f)->context)
#define fch_fence_seqno(f) ((f)->seqno)
#define fch_fence_ops(f) ((const void *)(f)->ops)
#define fch_driver_is(f,s) (strcmp((f)->ops->get_driver_name(f),(s))==0)
#define fch_timeline_is(f,s) (strcmp((f)->ops->get_timeline_name(f),(s))==0)
#define fch_uses64(f) ((f)->ops->use_64bit_seqno)
#define fch_array_ops() ((const void *)&dma_fence_array_ops)
#define fch_chain_ops() ((const void *)&dma_fence_chain_ops)
#define fch_work_flags(w) atomic_read(&(w)->node.a_flags)
#define fch_real_compare_prev(p,expected,replacement) __sync_val_compare_and_swap((p),(expected),(replacement))
void *fch_compare_prev(void **,void *,void *);
#ifdef VINIX_FENCE_CONTAINER_CAS_TRANSPORT
/* The same fully ordered atomic operation, with a V scheduling/observation
 * boundary only. Queue, walk, reference and return-value logic stays in V. */
#undef vfc_compare_prev
#define vfc_compare_prev(p,expected,replacement) fch_compare_prev((p),(expected),(replacement))
#endif
_Static_assert(sizeof(struct dma_fence_array)==120 && sizeof(struct dma_fence_array_cb)==32 &&
               sizeof(struct dma_fence_chain)==128,"original container ABI");
#endif
