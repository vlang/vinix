/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_HOSTIO_V_CONTRACT_H
#define VINIX_LINUXKPI_HOSTIO_V_CONTRACT_H
#include "host_model_v_contract.h"
#include <sched.h>
#include <linux/wait_bit.h>
#include <linux/sched/stat.h>
#include <linux/mutex.h>
void vmh_host_time_advance(vmh_u64);
unsigned int vmh_mutex_waiters(struct mutex *);
void *vmh_io_actor_thread(void *);
void vmh_io_wake_before_block(struct native_task_model *);
void *vmh_mutex_io_thread(void *);
void vmh_mutex_io_before_block(struct native_task_model *);
void vmh_io_tests(void);
void vmh_mutex_io_tests(void);
#endif
