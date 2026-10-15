/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_RCU_V_PRIMITIVES_H
#define VINIX_LINUXKPI_RCU_V_PRIMITIVES_H
#include "linuxkpi_v_primitives.h"
#include "linuxkpi_wait_v_primitives.h"

/* Views only: the typed binding checks the original callback_head layout. */
typedef void (*vkr_rcu_callback_fn)(struct callback_head *);
struct vkr_rcu_head {
    struct vkr_rcu_head *next;
    vkr_rcu_callback_fn func;
};

int32_t vkr_rcu_bootstrap(uint32_t);
bool vkr_rcu_ready(void);
/* Trusted CPU-owned outer-return gate, with IRQs disabled. This touches only
 * permanent scalar storage: no allocation, locks, task borrows or wakeups. */
void vkr_rcu_quiescent(uint32_t);
void vkr_rcu_call(void *, vkr_rcu_callback_fn);
void vkr_kvfree_call_rcu(void *, void *);
void vkr_rcu_synchronize(bool);
void vkr_rcu_barrier(void);
uint64_t vkr_rcu_get_state(void);
uint64_t vkr_rcu_start_poll(void);
bool vkr_rcu_poll(uint64_t);
void vkr_rcu_cond(uint64_t);

void *vkr_rcu_gp_worker(void *);
void *vkr_rcu_callback_worker(void *);
void *vkr_rcu_worker_function(bool);
int32_t vkr_rcu_pthread_create(void *, void *, void *);
int32_t vkr_rcu_pthread_join(uint64_t);
void vkr_rcu_worker_enter(void);
void vkr_rcu_thread_exit(void);
void *vkr_rcu_get_current(void);
void vkr_rcu_put_task(void *);
bool vkr_rcu_task_retired(void *);
bool vinix_linuxkpi_test_thread_reap_ready(void *);

bool vkm_cpu_masks_ready(void);
uint32_t vkm_cpu_ids(void);
uint32_t vkm_online_count(void);
bool vks_smp_ready(void);
bool vinix_linuxkpi_smp_boot_context(void);
bool vinix_linuxkpi_smp_task_present(void);
void vinix_linuxkpi_rcu_force_quiescence(void);
uint32_t vinix_linuxkpi_maskable_irq_depth(void);
uint32_t vinix_linuxkpi_preempt_count(void);
void vinix_linuxkpi_preempt_disable(void);
void vinix_linuxkpi_preempt_enable(void);
unsigned long vinix_linuxkpi_irq_flags(void);
int vinix_linuxkpi_cond_resched(void);

#ifdef VINIX_V_RUNTIME
void msleep(unsigned int);
#endif
#ifdef VINIX_LINUXKPI_HOST_TEST
/* Transport/context observations only, implemented in the host V fixture. */
void vkr_rcu_host_worker_enter(void);
void vkr_rcu_host_worker_leave(void);
int32_t vkr_rcu_host_create_error(void);
void vkr_rcu_shutdown_for_test(void);
#endif

/* Compiler primitives, not an alternate queue/grace-period implementation. */
#define vkr_rcu_load32(p, order) __atomic_load_n((p), (order))
#define vkr_rcu_store32(p, value, order) __atomic_store_n((p), (value), (order))
#define vkr_rcu_load64(p, order) __atomic_load_n((p), (order))
#define vkr_rcu_store64(p, value, order) __atomic_store_n((p), (value), (order))
#define vkr_rcu_fence(order) __atomic_thread_fence(order)
#endif
