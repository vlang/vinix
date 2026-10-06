/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_IO_FIXTURE_V_CONTRACT_H
#define VINIX_LINUXKPI_IO_FIXTURE_V_CONTRACT_H
#include "linuxkpi_task_v_contract.h"
#include <linux/init.h>
#include <linux/bitops.h>
#include <linux/sched/task.h>
#include <linux/sched/stat.h>
#include <linux/wait_bit.h>
#include <linux/delay.h>
#include <linux/errno.h>
#include <linux/mutex.h>
void vinix_linuxkpi_test_task_signal(void *, uint64_t);
void *vinix_linuxkpi_fixture_io_worker(void *);
int kprintf(const char *, ...);
#endif
