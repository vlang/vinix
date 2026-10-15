/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_DMA_FENCE_V_CONTRACT_H
#define VINIX_LINUXKPI_DMA_FENCE_V_CONTRACT_H
#include "linuxkpi_common_v_contract.h"
struct seq_file;
#define u64 vkh_linux_u64
#include <linux/dma-fence.h>
#undef u64
#include <linux/slab.h>
#include "linuxkpi_dma_fence_v_primitives.h"
typedef const struct dma_fence_ops *vdf_const_ops_p;
typedef __u64 vdf_u64;
_Static_assert(sizeof(struct dma_fence) == 64 && _Alignof(struct dma_fence) == 8 &&
               offsetof(struct dma_fence, lock) == 0 && offsetof(struct dma_fence, ops) == 8 &&
               offsetof(struct dma_fence, cb_list) == 16 && offsetof(struct dma_fence, timestamp) == 16 &&
               offsetof(struct dma_fence, rcu) == 16 && offsetof(struct dma_fence, context) == 32 &&
               offsetof(struct dma_fence, seqno) == 40 && offsetof(struct dma_fence, flags) == 48 &&
               offsetof(struct dma_fence, refcount) == 56 && offsetof(struct dma_fence, error) == 60 &&
               sizeof(struct vdf_fence) == sizeof(struct dma_fence) &&
               _Alignof(struct vdf_fence) == _Alignof(struct dma_fence) &&
               offsetof(struct vdf_fence, cb_list) == offsetof(struct dma_fence, cb_list) &&
               offsetof(struct vdf_fence, flags) == offsetof(struct dma_fence, flags) &&
               offsetof(struct vdf_fence, refcount) == offsetof(struct dma_fence, refcount) &&
               offsetof(struct vdf_fence, error) == offsetof(struct dma_fence, error),
               "original DMA fence and anonymous union ABI");
_Static_assert(sizeof(struct dma_fence_cb) == 24 && _Alignof(struct dma_fence_cb) == 8 &&
               offsetof(struct dma_fence_cb, node) == 0 && offsetof(struct dma_fence_cb, func) == 16 &&
               sizeof(struct vdf_cb) == sizeof(struct dma_fence_cb) &&
               sizeof(struct vdf_wait_cb) == 32 && offsetof(struct vdf_wait_cb, task) == 24,
               "original DMA fence callback ABI");
_Static_assert(sizeof(struct dma_fence_ops) == 80 && _Alignof(struct dma_fence_ops) == 8 &&
               offsetof(struct dma_fence_ops, use_64bit_seqno) == 0 &&
               offsetof(struct dma_fence_ops, get_driver_name) == 8 &&
               offsetof(struct dma_fence_ops, get_timeline_name) == 16 &&
               offsetof(struct dma_fence_ops, enable_signaling) == 24 &&
               offsetof(struct dma_fence_ops, signaled) == 32 &&
               offsetof(struct dma_fence_ops, wait) == 40 &&
               offsetof(struct dma_fence_ops, release) == 48 &&
               offsetof(struct dma_fence_ops, fence_value_str) == 56 &&
               offsetof(struct dma_fence_ops, timeline_value_str) == 64 &&
               offsetof(struct dma_fence_ops, set_deadline) == 72 &&
               sizeof(struct vdf_ops) == sizeof(struct dma_fence_ops) &&
               _Alignof(struct vdf_ops) == _Alignof(struct dma_fence_ops) &&
               offsetof(struct vdf_ops, use_64bit_seqno) == 0 &&
               offsetof(struct vdf_ops, get_driver_name) == 8 &&
               offsetof(struct vdf_ops, get_timeline_name) == 16 &&
               offsetof(struct vdf_ops, enable_signaling) == 24 &&
               offsetof(struct vdf_ops, signaled) == 32 &&
               offsetof(struct vdf_ops, wait) == 40 &&
               offsetof(struct vdf_ops, release) == 48 &&
               offsetof(struct vdf_ops, fence_value_str) == 56 &&
               offsetof(struct vdf_ops, timeline_value_str) == 64 &&
               offsetof(struct vdf_ops, set_deadline) == 72,
               "original DMA fence ops ABI");
_Static_assert(__builtin_types_compatible_p(vdf_callback_fn, dma_fence_func_t) &&
               __builtin_types_compatible_p(__typeof__(((struct vdf_ops *)0)->get_driver_name), __typeof__(((struct dma_fence_ops *)0)->get_driver_name)) &&
               __builtin_types_compatible_p(__typeof__(((struct vdf_ops *)0)->get_timeline_name), __typeof__(((struct dma_fence_ops *)0)->get_timeline_name)) &&
               __builtin_types_compatible_p(__typeof__(((struct vdf_ops *)0)->enable_signaling), __typeof__(((struct dma_fence_ops *)0)->enable_signaling)) &&
               __builtin_types_compatible_p(__typeof__(((struct vdf_ops *)0)->signaled), __typeof__(((struct dma_fence_ops *)0)->signaled)) &&
               __builtin_types_compatible_p(__typeof__(((struct vdf_ops *)0)->wait), __typeof__(((struct dma_fence_ops *)0)->wait)) &&
               __builtin_types_compatible_p(__typeof__(((struct vdf_ops *)0)->release), __typeof__(((struct dma_fence_ops *)0)->release)) &&
               __builtin_types_compatible_p(__typeof__(((struct vdf_ops *)0)->fence_value_str), __typeof__(((struct dma_fence_ops *)0)->fence_value_str)) &&
               __builtin_types_compatible_p(__typeof__(((struct vdf_ops *)0)->timeline_value_str), __typeof__(((struct dma_fence_ops *)0)->timeline_value_str)) &&
               __builtin_types_compatible_p(__typeof__(((struct vdf_ops *)0)->set_deadline), __typeof__(((struct dma_fence_ops *)0)->set_deadline)),
               "original DMA fence function signatures");
_Static_assert(DMA_FENCE_FLAG_SIGNALED_BIT == 0 && DMA_FENCE_FLAG_TIMESTAMP_BIT == 1 &&
               DMA_FENCE_FLAG_ENABLE_SIGNAL_BIT == 2 && DMA_FENCE_FLAG_USER_BITS == 3 &&
               GFP_KERNEL == 3264 && sizeof(ktime_t) == 8 && sizeof(long) == 8,
               "original DMA fence flags and native word widths");
#endif
