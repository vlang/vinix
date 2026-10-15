/* SPDX-License-Identifier: MIT */
#ifndef VINIX_LINUXKPI_DMA_RESV_V_PRIMITIVES_H
#define VINIX_LINUXKPI_DMA_RESV_V_PRIMITIVES_H
#include "linuxkpi_dma_fence_v_primitives.h"
#include "linuxkpi_rcu_v_primitives.h"
struct vdr_list {
    struct vkr_rcu_head rcu;
    uint32_t num_fences, max_fences;
    void *table[];
};
struct vdr_obj { int64_t owner; unsigned char lock_tail[32]; struct vdr_list *fences; };
struct vdr_iter {
    void *obj;
    uint32_t usage;
    void *fence;
    uint32_t fence_usage, position;
    struct vdr_list *fences;
    uint32_t num_fences;
    bool is_restarted;
};
#define vdr_load_ptr(p) __atomic_load_n((p), __ATOMIC_ACQUIRE)
#define vdr_store_ptr(p, value, order) __atomic_store_n((p), (value), (order))
#define vdr_load32(p) __atomic_load_n((p), __ATOMIC_RELAXED)
#define vdr_store32(p, value) __atomic_store_n((p), (value), __ATOMIC_RELAXED)
#define vdr_publish_fence() __atomic_thread_fence(__ATOMIC_RELEASE)
void vdr_init(void *);
void vdr_fini(void *);
int32_t vdr_reserve(void *, uint32_t);
void vdr_add(void *, void *, uint32_t);
void vdr_replace(void *, uint64_t, void *, uint32_t);
void *vdr_iter_first_unlocked(void *);
void *vdr_iter_next_unlocked(void *);
void *vdr_iter_first(void *);
void *vdr_iter_next(void *);
int32_t vdr_copy(void *, void *);
int32_t vdr_get_fences(void *, uint32_t, uint32_t *, void **);
int32_t vdr_get_singleton(void *, uint32_t, void **);
int64_t vdr_wait(void *, uint32_t, bool, uint64_t);
void vdr_deadline(void *, uint32_t, int64_t);
bool vdr_test_signaled(void *, uint32_t);
void *vdr_class(void);
void vdr_lock_init(void *);
void vdr_lock_fini(void *);
void *vdr_get(void *);
void vdr_put(void *);
void *vdr_get_rcu(void *);
bool vdr_later_or_same(void *, void *);
bool vdr_container(void *);
void vdr_read_lock(void);
void vdr_read_unlock(void);
size_t kmalloc_size_roundup(size_t);
void *krealloc_array(void *, size_t, size_t, unsigned int);
#endif
