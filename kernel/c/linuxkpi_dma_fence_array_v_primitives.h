/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_DMA_FENCE_ARRAY_V_PRIMITIVES_H
#define VINIX_LINUXKPI_DMA_FENCE_ARRAY_V_PRIMITIVES_H
#include "linuxkpi_dma_fence_v_primitives.h"
#include "linuxkpi_irq_work_v_primitives.h"
struct dma_fence_array;
/* Data-only views of the original array and its appended callbacks. */
struct vfa_array {
    struct vdf_fence base;
    uint32_t lock, num_fences;
    int32_t num_pending;
    void **fences;
    struct vkiw_work work;
};
struct vfa_cb { struct vdf_cb cb; struct vfa_array *array; };
typedef const char *vfa_const_char_p;
typedef long long vfa_ktime_t;
vfa_const_char_p vfa_driver_name(struct dma_fence *);
vfa_const_char_p vfa_timeline_name(struct dma_fence *);
bool vfa_enable_signaling(struct dma_fence *);
bool vfa_signaled(struct dma_fence *);
void vfa_release(struct dma_fence *);
void vfa_set_deadline(struct dma_fence *, vfa_ktime_t);
void *vfa_create(int32_t, void *, uint64_t, uint32_t, bool);
bool vfa_match_context(void *, uint64_t);
void *vfa_first(void *);
void *vfa_next(void *, uint32_t);
void *vfa_ops(void);
void vfa_fence_put(void *);
bool vfa_is_container(void *);
void vfa_init_work(void *, vkiw_callback_fn);
/* Intrinsic atomics only; all ownership and state transitions live in V. */
#define vfa_pending_load(p) __atomic_load_n((p), __ATOMIC_ACQUIRE)
#define vfa_pending_dec(p) (__atomic_sub_fetch((p), 1, __ATOMIC_SEQ_CST) == 0)
#define vfa_error_compare(p, expected, value) \
    __atomic_compare_exchange_n((p), (expected), (value), false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)
#endif
