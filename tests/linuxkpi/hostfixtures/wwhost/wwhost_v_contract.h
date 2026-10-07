/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_WW_HOST_V_CONTRACT_H
#define VINIX_LINUXKPI_WW_HOST_V_CONTRACT_H
#include "host_model_v_contract.h"
#include <sched.h>
#include <linux/ww_mutex.h>
#include <linux/limits.h>
unsigned int vmh_mutex_waiters(struct mutex *);
void *vmh_ww_actor_thread(void *);
void vmh_ww_mutex_tests(void);
#endif
