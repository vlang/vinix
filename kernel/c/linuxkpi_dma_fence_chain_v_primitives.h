/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_DMA_FENCE_CHAIN_V_PRIMITIVES_H
#define VINIX_LINUXKPI_DMA_FENCE_CHAIN_V_PRIMITIVES_H
#include "linuxkpi_dma_fence_v_primitives.h"
#include "linuxkpi_irq_work_v_primitives.h"
/* A data-only view of the original cb/work union and lock. */
struct vfc_chain {
    struct vdf_fence base;
    void *prev;
    uint64_t prev_seqno;
    void *fence;
    unsigned char callback_storage[32];
    uint32_t guard;
};
#define vfc_compare_prev(p, expected, replacement) \
    __sync_val_compare_and_swap((p), (expected), (replacement))
#define vfc_load_prev(p) __atomic_load_n((p), __ATOMIC_ACQUIRE)
#define vfc_store_prev(p, value) __atomic_store_n((p), (value), __ATOMIC_RELEASE)
void *vfc_walk(void *);
int32_t vfc_find_seqno(void **, uint64_t);
void vfc_init(void *, void *, void *, uint64_t);
bool vfc_enable(void *);
bool vfc_signaled(void *);
void vfc_release(void *);
void vfc_deadline(void *, int64_t);
void vfc_irq(void *);
void vfc_callback(void *, void *);
void *vfc_ops_identity(void);
void *vfc_get(void *);
void vfc_put(void *);
void *vfc_get_prev(void *);
bool vfc_is_signaled(void *);
uint32_t vfc_refcount(void *);
void vfc_init_work(void *);
bool vfc_ops_enable(struct dma_fence *);
bool vfc_ops_signaled(struct dma_fence *);
void vfc_ops_release(struct dma_fence *);
void vfc_ops_deadline(struct dma_fence *, vdf_ktime_t);
vdf_const_char_p vfc_driver_name(struct dma_fence *);
vdf_const_char_p vfc_timeline_name(struct dma_fence *);
void vfc_irq_callback(struct irq_work *);
void vfc_child_callback(struct dma_fence *, struct dma_fence_cb *);
#endif
