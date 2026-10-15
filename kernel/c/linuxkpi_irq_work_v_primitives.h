/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_IRQ_WORK_V_PRIMITIVES_H
#define VINIX_LINUXKPI_IRQ_WORK_V_PRIMITIVES_H
#include "linuxkpi_v_primitives.h"
struct irq_work;
typedef void (*vkiw_callback_fn)(struct irq_work *);
/* Data-only view checked against the unchanged original record. */
struct vkiw_work {
    struct vkiw_work *next;
    uint32_t flags;
    uint16_t src, dst;
    vkiw_callback_fn func;
    void *irqwait;
};
int32_t vkiw_bootstrap(uint32_t);
bool vkiw_ready(void);
bool vkiw_queue(void *, int32_t);
void vkiw_drain(uint32_t);
void vkiw_tick(uint32_t);
void vkiw_tick_all(void);
bool vkiw_needs_cpu(void);
void vkiw_single(void *);
void vkiw_sync(void *);
void vkiw_raise(void);
uint32_t vkiw_running_count(void *);
uint64_t vkiw_sync_wait_count(void);
void vinix_linuxkpi_irqwork_send_ipi(uint32_t);
bool vkm_cpu_masks_ready(void);
uint32_t vkm_cpu_ids(void);
uint32_t vkm_online_count(void);
bool vks_smp_ready(void);
bool vkr_rcu_ready(void);
bool vinix_linuxkpi_smp_boot_context(void);
bool vinix_linuxkpi_smp_task_present(void);
uint32_t vinix_linuxkpi_cpu_id(void);
uint32_t vinix_linuxkpi_maskable_irq_depth(void);
uint32_t vinix_linuxkpi_preempt_count(void);
void vinix_linuxkpi_preempt_disable(void);
void vinix_linuxkpi_preempt_enable(void);
unsigned long vinix_linuxkpi_irq_flags(void);
void vinix_linuxkpi_spin_wait(void);
/* Compiler primitives only. All queue ownership and dispatch stay in V. */
#define vkiw_load32(p, order) __atomic_load_n((p), (order))
#define vkiw_store32(p, value, order) __atomic_store_n((p), (value), (order))
#define vkiw_or32(p, value, order) __atomic_fetch_or((p), (value), (order))
#define vkiw_compare32(p, expected, value, success, failure) \
    __atomic_compare_exchange_n((p), (expected), (value), false, (success), (failure))
#define vkiw_fence(order) __atomic_thread_fence(order)
#endif
