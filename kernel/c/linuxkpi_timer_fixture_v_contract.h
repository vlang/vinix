/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_TIMER_FIXTURE_V_CONTRACT_H
#define VINIX_LINUXKPI_TIMER_FIXTURE_V_CONTRACT_H
#include "linuxkpi_task_v_contract.h"
#include <linux/bug.h>
#include <linux/sched/task.h>
int kprintf(const char *, ...);
void vinix_linuxkpi_fixture_timer_callback(struct timer_list *);
void *vinix_linuxkpi_fixture_timer_worker(void *);
#endif
