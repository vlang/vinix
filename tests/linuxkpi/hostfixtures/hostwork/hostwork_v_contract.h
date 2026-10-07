/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_HOSTWORK_V_CONTRACT_H
#define VINIX_LINUXKPI_HOSTWORK_V_CONTRACT_H
#include "host_model_v_contract.h"
#include <sched.h>
#include <linux/workqueue.h>
#include <linux/completion.h>
#define u64 vmh_linux_u64
#include <linux/srcu.h>
#define timespec vinix_linux_timespec
#define timeval vinix_linux_timeval
#define itimerspec vinix_linux_itimerspec
#define timezone vinix_linux_timezone
#include <linux/delay.h>
#undef timespec
#undef timeval
#undef itimerspec
#undef timezone
#undef u64
/* Attach the unchanged native per-CPU storage attributes to V-owned BSS. */
extern struct srcu_data hostwork__srcu_static_data __PCPU_ATTRS("");
_Static_assert(WQ_DFL_ACTIVE == 256, "original system active slots");
atomic_t *vmh_work_workers_pointer(void);
void vmh_host_time_advance(vmh_u64);
void vmh_work_static_callback(struct work_struct *);
void vmh_work_callback(struct work_struct *);
void *vmh_work_operation_thread(void *);
void *vmh_work_producer_thread(void *);
void vmh_workqueue_tests(void);
void vmh_delayed_callback(struct work_struct *);
void vmh_static_delayed_callback(struct work_struct *);
void *vmh_delayed_operation_thread(void *);
void *vmh_delayed_producer_thread(void *);
void *vmh_delayed_dispatch_thread(void *);
void vmh_delayed_work_tests(void);
void vmh_unbound_nested_callback(struct work_struct *);
void vmh_unbound_work_tests(void);
bool vinix_linuxkpi_host_workqueue_stopped(struct workqueue_struct *);
void vinix_linuxkpi_workqueue_shutdown_for_test(void);
void vmh_bound_callback(struct work_struct *);
void vmh_bound_delayed_callback(struct work_struct *);
void vmh_bound_irq_cpu_switch(void);
void vmh_bound_work_tests(void);
void vinix_linuxkpi_srcu_static_quiesce_for_test(struct srcu_struct *);
int vinix_linuxkpi_srcu_bootstrap_limit_for_test(unsigned int);
void vinix_linuxkpi_srcu_shutdown_for_test(void);
struct workqueue_struct *vinix_linuxkpi_srcu_queue_for_test(void);
void *vmh_srcu_clock_thread(void *);
void *vmh_srcu_waiter_thread(void *);
void vmh_srcu_callback(struct rcu_head *);
void *vmh_srcu_stress_thread(void *);
void vmh_srcu_system_wait(struct work_struct *);
void vmh_srcu_tests(void);
#endif
