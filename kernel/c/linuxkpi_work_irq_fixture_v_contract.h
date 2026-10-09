/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_WORK_IRQ_FIXTURE_V_CONTRACT_H
#define VINIX_LINUXKPI_WORK_IRQ_FIXTURE_V_CONTRACT_H
#include "linuxkpi_task_v_contract.h"
#include "linuxkpi_work_irq_fixture_v_primitives.h"
#include <linux/smp.h>
#include <linux/sched/task.h>
#include <linux/workqueue.h>
#include <linux/delay.h>
#include <vinix/runtime.h>
void vinix_linuxkpi_workirq_anchor(struct work_struct *);
void vinix_linuxkpi_workirq_rejected(struct work_struct *);
void vinix_linuxkpi_workirq_chain(struct work_struct *);
void vinix_linuxkpi_workirq_probe(void *);
void *vinix_linuxkpi_workirq_controller(void *);
void *vinix_linuxkpi_workirq_drainer(void *);
int kprintf(const char *, ...);
_Static_assert(sizeof(pthread_t) == sizeof(uintptr_t),
               "native work IRQ actor thread handle");
#endif
