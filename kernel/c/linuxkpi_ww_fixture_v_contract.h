/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_WW_FIXTURE_V_CONTRACT_H
#define VINIX_LINUXKPI_WW_FIXTURE_V_CONTRACT_H
#include "linuxkpi_task_v_contract.h"
#include <linux/ww_mutex.h>
#include <linux/delay.h>
#include <linux/sched/task.h>
#include <linux/errno.h>
void vinix_linuxkpi_test_task_signal(void *, uint64_t);
void *vinix_linuxkpi_fixture_ww_worker(void *);
int kprintf(const char *, ...);
#endif
