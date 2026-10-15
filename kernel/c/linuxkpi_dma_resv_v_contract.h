/* SPDX-License-Identifier: MIT */
#ifndef VINIX_LINUXKPI_DMA_RESV_V_CONTRACT_H
#define VINIX_LINUXKPI_DMA_RESV_V_CONTRACT_H
#include "linuxkpi_dma_fence_v_contract.h"
#define u64 vkh_linux_u64
#include <linux/dma-resv.h>
#undef u64
#include "linuxkpi_dma_resv_v_primitives.h"
/* Exact private record from the pinned dma-resv.c; data only. */
struct dma_resv_list {
    struct rcu_head rcu;
    u32 num_fences, max_fences;
    struct dma_fence *table[];
};
typedef enum dma_resv_usage vdr_usage;
typedef struct ww_class vdr_class_type;
typedef const char *vdr_const_char_p;
#define vdr_acquire_name "reservation_ww_class_acquire"
#define vdr_mutex_name "reservation_ww_class_mutex"
_Static_assert(sizeof(struct dma_resv) == 48 && _Alignof(struct dma_resv) == 8 &&
               offsetof(struct dma_resv, lock) == 0 && offsetof(struct dma_resv, fences) == 40 &&
               sizeof(struct vdr_obj) == 48 && _Alignof(struct vdr_obj) == 8 && offsetof(struct vdr_obj, fences) == 40 &&
               sizeof(struct ww_mutex) == 40 && offsetof(struct ww_mutex, base.owner) == 0,
               "original reservation and native writer ownership ABI");
_Static_assert(sizeof(struct dma_resv_list) == 24 && _Alignof(struct dma_resv_list) == 8 &&
               offsetof(struct dma_resv_list, rcu) == 0 && offsetof(struct dma_resv_list, num_fences) == 16 &&
               offsetof(struct dma_resv_list, max_fences) == 20 && offsetof(struct dma_resv_list, table) == 24 &&
               sizeof(struct vdr_list) == 24 && _Alignof(struct vdr_list) == 8 &&
               offsetof(struct vdr_list, num_fences) == 16 && offsetof(struct vdr_list, max_fences) == 20 &&
               offsetof(struct vdr_list, table) == 24, "original reservation list and RCU head ABI");
_Static_assert(sizeof(struct dma_resv_iter) == 48 && _Alignof(struct dma_resv_iter) == 8 &&
               offsetof(struct dma_resv_iter, obj) == 0 && offsetof(struct dma_resv_iter, usage) == 8 &&
               offsetof(struct dma_resv_iter, fence) == 16 && offsetof(struct dma_resv_iter, fence_usage) == 24 &&
               offsetof(struct dma_resv_iter, index) == 28 && offsetof(struct dma_resv_iter, fences) == 32 &&
               offsetof(struct dma_resv_iter, num_fences) == 40 && offsetof(struct dma_resv_iter, is_restarted) == 44 &&
               sizeof(struct vdr_iter) == 48 && _Alignof(struct vdr_iter) == 8 &&
               offsetof(struct vdr_iter, usage) == 8 && offsetof(struct vdr_iter, fence) == 16 &&
               offsetof(struct vdr_iter, fence_usage) == 24 && offsetof(struct vdr_iter, position) == 28 &&
               offsetof(struct vdr_iter, fences) == 32 && offsetof(struct vdr_iter, num_fences) == 40 &&
               offsetof(struct vdr_iter, is_restarted) == 44, "original reservation iterator ABI");
_Static_assert(sizeof(struct ww_class) == 32 && _Alignof(struct ww_class) == 8 &&
               offsetof(struct ww_class, stamp) == 0 && offsetof(struct ww_class, acquire_name) == 8 &&
               offsetof(struct ww_class, mutex_name) == 16 && offsetof(struct ww_class, is_wait_die) == 24 &&
               __builtin_types_compatible_p(__typeof__(reservation_ww_class), vdr_class_type),
               "original mutable wait-die class identity");
_Static_assert(sizeof(enum dma_resv_usage) == 4 && DMA_RESV_USAGE_KERNEL == 0 && DMA_RESV_USAGE_WRITE == 1 &&
               DMA_RESV_USAGE_READ == 2 && DMA_RESV_USAGE_BOOKKEEP == 3, "original reservation usage tag order");
#endif
