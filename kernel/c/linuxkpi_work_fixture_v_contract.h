/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_WORK_FIXTURE_V_CONTRACT_H
#define VINIX_LINUXKPI_WORK_FIXTURE_V_CONTRACT_H
#include "linuxkpi_srcu_v_contract.h"
#include "linuxkpi_task_v_contract.h"
#include <linux/slab.h>
#include <linux/delay.h>
#include <linux/errno.h>
#include <vinix/runtime.h>
void vinix_linuxkpi_fixture_work_callback(struct work_struct *);
void vinix_linuxkpi_fixture_delayed_callback(struct work_struct *);
void vinix_linuxkpi_fixture_parallel_callback(struct work_struct *);
void vinix_linuxkpi_fixture_bound_callback(struct work_struct *);
int kprintf(const char *, ...);
#endif
