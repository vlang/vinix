/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_WORKER_FIXTURE_V_CONTRACT_H
#define VINIX_LINUXKPI_WORKER_FIXTURE_V_CONTRACT_H
#include "linuxkpi_task_v_contract.h"
#include <linux/delay.h>
#include <linux/errno.h>
#include <linux/workqueue.h>
#include <vinix/runtime.h>
#include <string.h>
#ifdef VINIX_LINUXKPI_TEST_TRACE
#define VKF_WORKER_TRACE 1
#else
#define VKF_WORKER_TRACE 0
#endif
_Static_assert(sizeof(pthread_t) == sizeof(uintptr_t), "worker native pthread sentinel width");
void *vinix_linuxkpi_fixture_worker_once(void *);
void *vinix_linuxkpi_fixture_worker_context(void *);
int kprintf(const char *, ...);
#endif
