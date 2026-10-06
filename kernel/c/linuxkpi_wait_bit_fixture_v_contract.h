/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_WAIT_BIT_FIXTURE_V_CONTRACT_H
#define VINIX_LINUXKPI_WAIT_BIT_FIXTURE_V_CONTRACT_H
#include "linuxkpi_task_v_contract.h"
#include <linux/bitops.h>
#include <linux/sched/task.h>
#include <linux/wait_bit.h>
#include <linux/completion.h>
#include <linux/delay.h>
#include <linux/errno.h>
#include <linux/jiffies.h>
#include <linux/slab.h>
#include <vinix/runtime.h>
void vinix_linuxkpi_test_task_signal(void *, unsigned long long);
void *vinix_linuxkpi_fixture_bit_thread(void *);
int vinix_linuxkpi_fixture_bit_action_error(struct wait_bit_key *, int);
int vinix_linuxkpi_fixture_bit_action_clear(struct wait_bit_key *, int);
int kprintf(const char *, ...);
#ifdef VINIX_LINUXKPI_TEST_TRACE
enum { VKFW_TRACE = 1 };
#else
enum { VKFW_TRACE = 0 };
#endif
#endif
