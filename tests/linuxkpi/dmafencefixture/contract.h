/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_DMA_FENCE_HOST_CONTRACT_H
#define VINIX_DMA_FENCE_HOST_CONTRACT_H
/* Metadata, compiler intrinsics and unchanged original-inline adapters only. */
#include "../freefixture/contract.h"
#include "linuxkpi_dma_fence_v_contract.h"
#include "linuxkpi_task_v_contract.h"
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
#endif
