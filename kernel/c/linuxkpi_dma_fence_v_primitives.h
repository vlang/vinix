/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_DMA_FENCE_V_PRIMITIVES_H
#define VINIX_LINUXKPI_DMA_FENCE_V_PRIMITIVES_H
#include "linuxkpi_v_primitives.h"
struct dma_fence;
struct dma_fence_cb;
typedef const char *vdf_const_char_p;
typedef long long vdf_ktime_t;
typedef void (*vdf_callback_fn)(struct dma_fence *, struct dma_fence_cb *);
vdf_const_char_p vdf_stub_get_name(struct dma_fence *);
struct vdf_list { struct vdf_list *next, *prev; };
struct vdf_ops {
    bool use_64bit_seqno;
    vdf_const_char_p (*get_driver_name)(struct dma_fence *);
    vdf_const_char_p (*get_timeline_name)(struct dma_fence *);
    bool (*enable_signaling)(struct dma_fence *);
    bool (*signaled)(struct dma_fence *);
    long (*wait)(struct dma_fence *, bool, long);
    void (*release)(struct dma_fence *);
    void (*fence_value_str)(struct dma_fence *, char *, int);
    void (*timeline_value_str)(struct dma_fence *, char *, int);
    void (*set_deadline)(struct dma_fence *, vdf_ktime_t);
};
/* The list storage is the original anonymous list/timestamp/RCU union.
 * Timestamp and RCU transitions use its address, never separate state. */
struct vdf_fence {
    void *lock;
    const struct vdf_ops *ops;
    struct vdf_list cb_list;
    uint64_t context, seqno;
    unsigned long flags;
    uint32_t refcount;
    int32_t error;
};
struct vdf_cb { struct vdf_list node; vdf_callback_fn func; };
struct vdf_wait_cb { struct vdf_cb base; void *task; };
#define vdf_load_flags(p) __atomic_load_n((p), __ATOMIC_ACQUIRE)
#define vdf_or_flags(p, v) __atomic_fetch_or((p), (v), __ATOMIC_SEQ_CST)
#define vdf_fetch_context(p, v) __atomic_fetch_add((p), (v), __ATOMIC_SEQ_CST)
void *vdf_get_stub(void);
void *vdf_allocate_private_stub(int64_t);
uint64_t vdf_context_alloc(uint32_t);
int32_t vdf_signal(void *);
int32_t vdf_signal_locked(void *);
int32_t vdf_signal_timestamp(void *, int64_t);
int32_t vdf_signal_timestamp_locked(void *, int64_t);
int64_t vdf_wait_timeout(void *, bool, int64_t);
void vdf_release(void *);
void vdf_free(void *);
void vdf_enable_sw_signaling(void *);
int32_t vdf_add_callback(void *, void *, vdf_callback_fn);
int32_t vdf_get_status(void *);
bool vdf_remove_callback(void *, void *);
int64_t vdf_default_wait(void *, bool, int64_t);
int64_t vdf_wait_any_timeout(void *, uint32_t, bool, int64_t, uint32_t *);
void vdf_set_deadline(void *, int64_t);
void vdf_init(void *, void *, void *, uint64_t, uint64_t);
void *vdf_stub_storage(void);
void *vdf_stub_lock(void);
void *vdf_stub_ops(void);
void *vdf_fence_get(void *);
void *vdf_current_get(void);
void vdf_task_put(void *);
void vdf_wake(void *);
void vinix_linuxkpi_set_task_state(uint32_t);
bool vinix_linuxkpi_smp_task_present(void);
uint32_t vinix_linuxkpi_maskable_irq_depth(void);
uint32_t vinix_linuxkpi_preempt_count(void);
unsigned long vinix_linuxkpi_irq_flags(void);
void vkr_kvfree_call_rcu(void *, void *);
#endif
