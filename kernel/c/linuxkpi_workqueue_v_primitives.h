/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_WORKQUEUE_V_PRIMITIVES_H
#define VINIX_LINUXKPI_WORKQUEUE_V_PRIMITIVES_H
#include "linuxkpi_srcu_v_primitives.h"
extern struct vkw_list vkwq_running, vkwq_canceling, vkwq_all;
void *vkwq_worker_callback(void);
void *vkwq_manager_callback(void);
void *vkwq_barrier_callback(void);
void *vkwq_delayed_callback(void);
int vkwq_pthread_create(void *, void *, void *);
int vkwq_pthread_join(uint64_t);
void *vkwq_get_current(void);
void vkwq_put_task(void *);
unsigned int vkwq_task_state(void *);
bool vkwq_current_running(void);
void vkwq_worker_enter(void);
void vkwq_worker_leave(void);
void vkwq_delayed_gate(void *);
void vkwq_publish_gate(void *, unsigned int);
void vkwq_warn_queue_cpu(bool);
void vkwq_warn_delayed_cpu(bool);
void vkwq_warn_mod_cpu(bool);
void vkwq_warn_limit(void);
int vinix_linuxkpi_worker_set_nice(int);
int vinix_linuxkpi_worker_bind(unsigned int);
int vinix_linuxkpi_cond_resched(void);
unsigned int vinix_linuxkpi_cpu_id(void);
unsigned long vinix_linuxkpi_irq_flags(void);
void vinix_linuxkpi_spin_wait(void);
#ifdef VINIX_V_RUNTIME
extern void *system_wq, *system_highpri_wq, *system_unbound_wq;
void *vinix_linuxkpi_workqueue_allocate(unsigned int, int);
char *vinix_linuxkpi_workqueue_name(void *);
void *vinix_linuxkpi_workqueue_start(void *);
void *vinix_linuxkpi_work_worker(void *);
void *vinix_linuxkpi_pool_manager(void *);
void vinix_linuxkpi_work_barrier(struct work_struct *);
bool queue_work_on(int, void *, void *);
bool queue_delayed_work_on(int, void *, void *, uint64_t);
bool mod_delayed_work_on(int, void *, void *, uint64_t);
bool cancel_delayed_work(void *);
void delayed_work_timer_fn(struct timer_list *);
void vinix_linuxkpi_workqueue_task_sleep(void *);
void vinix_linuxkpi_workqueue_task_resume(void *);
int vinix_linuxkpi_workqueue_bootstrap(void);
bool vinix_linuxkpi_host_workqueue_stopped(void *);
void vinix_linuxkpi_workqueue_shutdown_for_test(void);
bool cancel_work(void *);
bool flush_delayed_work(void *);
void __flush_workqueue(void *);
void drain_workqueue(void *);
void *current_work(void);
unsigned int work_busy(void *);
int try_to_del_timer_sync(void *);
int timer_delete_sync(void *);
int mod_timer(void *, uint64_t);
#endif
#endif
