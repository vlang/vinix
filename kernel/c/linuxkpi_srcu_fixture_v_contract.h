/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_SRCU_FIXTURE_V_CONTRACT_H
#define VINIX_LINUXKPI_SRCU_FIXTURE_V_CONTRACT_H
#include "linuxkpi_srcu_v_contract.h"
#include "linuxkpi_task_v_contract.h"
#include <linux/delay.h>
#include <linux/errno.h>
#include <linux/sched/task.h>
#include <linux/slab.h>
#include <vinix/runtime.h>
void *vinix_linuxkpi_fixture_srcu_worker(void *);
void *vinix_linuxkpi_fixture_srcu_barrier_waiter(void *);
void vinix_linuxkpi_fixture_srcu_free_callback(struct rcu_head *);
void vinix_linuxkpi_fixture_srcu_barrier_callback(struct rcu_head *);
void vinix_linuxkpi_fixture_srcu_work_callback(struct work_struct *);
int kprintf(const char *, ...);
#endif
