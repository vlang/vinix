/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_WORKQUEUE_V_CONTRACT_H
#define VINIX_LINUXKPI_WORKQUEUE_V_CONTRACT_H
#include "linuxkpi_task_v_contract.h"
#include <linux/sched/task.h>
#include "linuxkpi_workqueue_v_primitives.h"
_Static_assert(WORK_STRUCT_FLAG_BITS == 8 && WORK_STRUCT_PENDING == 1 && WORK_STRUCT_INACTIVE == 2 && WORK_STRUCT_PWQ == 4, "V work data flags");
_Static_assert(WORK_STRUCT_NO_POOL == 0xfffffffe0UL && WORK_OFFQ_CANCELING == 16, "V off-queue work flags");
_Static_assert(WORK_CPU_UNBOUND == 256 && WQ_UNBOUND_MAX_ACTIVE == 512 && WQ_MAX_ACTIVE == 512 && WQ_DFL_ACTIVE == 256, "V pool limits");
_Static_assert(WQ_UNBOUND == 2 && WQ_HIGHPRI == 16 && __WQ_ORDERED == 131072 && __WQ_ORDERED_EXPLICIT == 524288, "V queue policies");
_Static_assert(sizeof(pthread_t) == sizeof(uint64_t), "V worker thread ABI");
void *vinix_linuxkpi_work_worker(void *);
void *vinix_linuxkpi_pool_manager(void *);
void vinix_linuxkpi_work_barrier(void *);
void *vinix_linuxkpi_workqueue_allocate(unsigned int, int);
char *vinix_linuxkpi_workqueue_name(void *);
void *vinix_linuxkpi_workqueue_start(void *);
int vkr_format_entry(char *, size_t, char *, void *, unsigned int *);
int vp_snprintf(char *, size_t, const char *, void *);
#ifdef VINIX_LINUXKPI_HOST_TEST
void vinix_linuxkpi_host_worker_enter(void);
void vinix_linuxkpi_host_worker_leave(void);
void vinix_linuxkpi_host_delayed_timer_gate(struct timer_list *);
void vinix_linuxkpi_host_pool_publish_gate(struct workqueue_struct *, unsigned int);
#endif
#endif
