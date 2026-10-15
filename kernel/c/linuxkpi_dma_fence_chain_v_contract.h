/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_DMA_FENCE_CHAIN_V_CONTRACT_H
#define VINIX_LINUXKPI_DMA_FENCE_CHAIN_V_CONTRACT_H
#include "linuxkpi_dma_fence_v_contract.h"
#include "linuxkpi_irq_work_v_contract.h"
#define u64 vkh_linux_u64
#include <linux/dma-fence-chain.h>
#undef u64
#include "linuxkpi_dma_fence_chain_v_primitives.h"
typedef const struct dma_fence_ops vfc_const_ops;
_Static_assert(sizeof(struct dma_fence_chain) == 128 &&
               _Alignof(struct dma_fence_chain) == 8 &&
               offsetof(struct dma_fence_chain, base) == 0 &&
               offsetof(struct dma_fence_chain, prev) == 64 &&
               offsetof(struct dma_fence_chain, prev_seqno) == 72 &&
               offsetof(struct dma_fence_chain, fence) == 80 &&
               offsetof(struct dma_fence_chain, cb) == 88 &&
               offsetof(struct dma_fence_chain, work) == 88 &&
               offsetof(struct dma_fence_chain, lock) == 120 &&
               sizeof(struct vfc_chain) == sizeof(struct dma_fence_chain) &&
               _Alignof(struct vfc_chain) == _Alignof(struct dma_fence_chain) &&
               offsetof(struct vfc_chain, callback_storage) == 88 &&
               offsetof(struct vfc_chain, guard) == 120,
               "original chain intrusive storage and union ABI");
_Static_assert(__builtin_types_compatible_p(__typeof__(dma_fence_chain_ops), vfc_const_ops) &&
               __builtin_types_compatible_p(__typeof__(&vfc_ops_enable), __typeof__(((struct dma_fence_ops *)0)->enable_signaling)) &&
               __builtin_types_compatible_p(__typeof__(&vfc_ops_signaled), __typeof__(((struct dma_fence_ops *)0)->signaled)) &&
               __builtin_types_compatible_p(__typeof__(&vfc_ops_release), __typeof__(((struct dma_fence_ops *)0)->release)) &&
               __builtin_types_compatible_p(__typeof__(&vfc_ops_deadline), __typeof__(((struct dma_fence_ops *)0)->set_deadline)) &&
               __builtin_types_compatible_p(__typeof__(&vfc_child_callback), dma_fence_func_t) &&
               __builtin_types_compatible_p(__typeof__(&vfc_irq_callback), __typeof__(((struct irq_work *)0)->func)),
               "original immutable chain ops and typed callbacks");
#endif
