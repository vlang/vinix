/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_RESV_HOST_CONTRACT_H
#define VINIX_RESV_HOST_CONTRACT_H
/* Original records, inline adapters and atomic/page transport declarations.
 * Every reservation, reference, wait and grace-period algorithm is V. */
#include "../freefixture/contract.h"
#include "linuxkpi_dma_resv_v_contract.h"
#include "linuxkpi_task_v_contract.h"
#include "linuxkpi_irq_work_v_contract.h"
#include <linux/dma-fence-array.h>
#define dfh_refcount(f) refcount_read(&(f)->refcount.refcount)
#define dfh_lock_held(f) __atomic_load_n(&(f)->lock->locked, __ATOMIC_ACQUIRE)
#define rsh_begin(c,o,u) dma_resv_iter_begin((c),(o),(u))
#define rsh_end(c) dma_resv_iter_end(c)
#define rsh_usage(c) dma_resv_iter_usage(c)
#define rsh_restarted(c) dma_resv_iter_is_restarted(c)
#define rsh_cursor_fence(c) ((c)->fence)
#define rsh_list(o) ((void *)rcu_access_pointer((o)->fences))
#define rsh_count(o) (rcu_access_pointer((o)->fences)->num_fences)
#define rsh_capacity(o) (rcu_access_pointer((o)->fences)->max_fences)
#define rsh_tag(o,i) ((uintptr_t)rcu_access_pointer((o)->fences)->table[i])
#define rsh_tag_address(o,i) ((void **)&rcu_access_pointer((o)->fences)->table[i])
#define rsh_class() (&reservation_ww_class)
#define rsh_wait_die() (reservation_ww_class.is_wait_die)
#define rsh_ctx(o) dma_resv_locking_ctx(o)
#define rsh_usage_rw(w) dma_resv_usage_rw(w)
#define rsh_array_count(f) (to_dma_fence_array(f)->num_fences)
#define rsh_array_ops(f) ((f)->ops == &dma_fence_array_ops)
#define rsh_array_work(f) (&to_dma_fence_array(f)->work)
#define rsh_atomic_load_ptr(p) __atomic_load_n((p), __ATOMIC_ACQUIRE)
#define rsh_wait_list(o) (!list_empty(&(o)->lock.base.wait_list))
void *rsh_load_ptr_gate(void **);
#endif
