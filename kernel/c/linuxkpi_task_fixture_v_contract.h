/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_TASK_FIXTURE_V_CONTRACT_H
#define VINIX_LINUXKPI_TASK_FIXTURE_V_CONTRACT_H
#include "linuxkpi_task_v_contract.h"
#include <linux/bug.h>
#include <linux/sched/signal.h>
#include <linux/sched/task.h>
void vinix_linuxkpi_test_task_signal(void *, uint64_t);
void *vinix_linuxkpi_fixture_task_worker(void *);
#endif
