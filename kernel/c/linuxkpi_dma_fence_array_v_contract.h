/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_DMA_FENCE_ARRAY_V_CONTRACT_H
#define VINIX_LINUXKPI_DMA_FENCE_ARRAY_V_CONTRACT_H
#include "linuxkpi_dma_fence_v_contract.h"
#include "linuxkpi_irq_work_v_contract.h"
#define u64 vkh_linux_u64
#include <linux/dma-fence-array.h>
#undef u64
#include "linuxkpi_dma_fence_array_v_primitives.h"
typedef const struct dma_fence_ops vfa_const_ops;
typedef __u64 vfa_u64;
_Static_assert(sizeof(struct dma_fence_array) == 120 && _Alignof(struct dma_fence_array) == 8 &&
               offsetof(struct dma_fence_array, base) == 0 && offsetof(struct dma_fence_array, lock) == 64 &&
               offsetof(struct dma_fence_array, num_fences) == 68 && offsetof(struct dma_fence_array, num_pending) == 72 &&
               offsetof(struct dma_fence_array, fences) == 80 && offsetof(struct dma_fence_array, work) == 88 &&
               sizeof(struct vfa_array) == sizeof(struct dma_fence_array) &&
               _Alignof(struct vfa_array) == _Alignof(struct dma_fence_array) &&
               offsetof(struct vfa_array, base) == 0 && offsetof(struct vfa_array, lock) == 64 &&
               offsetof(struct vfa_array, num_fences) == 68 && offsetof(struct vfa_array, num_pending) == 72 &&
               offsetof(struct vfa_array, fences) == 80 && offsetof(struct vfa_array, work) == 88,
               "original DMA fence array ABI");
_Static_assert(sizeof(struct dma_fence_array_cb) == 32 && _Alignof(struct dma_fence_array_cb) == 8 &&
               offsetof(struct dma_fence_array_cb, cb) == 0 && offsetof(struct dma_fence_array_cb, array) == 24 &&
               sizeof(struct vfa_cb) == sizeof(struct dma_fence_array_cb) &&
               _Alignof(struct vfa_cb) == _Alignof(struct dma_fence_array_cb) &&
               offsetof(struct vfa_cb, cb) == 0 && offsetof(struct vfa_cb, array) == 24 &&
               sizeof(atomic_t) == sizeof(int32_t) && sizeof(spinlock_t) == sizeof(uint32_t),
               "original DMA fence array callback, counter and lock ABI");
_Static_assert(__builtin_types_compatible_p(__typeof__(&vfa_driver_name), __typeof__(((struct dma_fence_ops *)0)->get_driver_name)) &&
               __builtin_types_compatible_p(__typeof__(&vfa_timeline_name), __typeof__(((struct dma_fence_ops *)0)->get_timeline_name)) &&
               __builtin_types_compatible_p(__typeof__(&vfa_enable_signaling), __typeof__(((struct dma_fence_ops *)0)->enable_signaling)) &&
               __builtin_types_compatible_p(__typeof__(&vfa_signaled), __typeof__(((struct dma_fence_ops *)0)->signaled)) &&
               __builtin_types_compatible_p(__typeof__(&vfa_release), __typeof__(((struct dma_fence_ops *)0)->release)) &&
               __builtin_types_compatible_p(__typeof__(&vfa_set_deadline), __typeof__(((struct dma_fence_ops *)0)->set_deadline)),
               "original DMA fence array ops signatures");
#endif
