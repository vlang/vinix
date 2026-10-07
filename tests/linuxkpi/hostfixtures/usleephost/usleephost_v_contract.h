/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_USLEEP_HOST_V_CONTRACT_H
#define VINIX_LINUXKPI_USLEEP_HOST_V_CONTRACT_H
#include "host_model_v_contract.h"
#include <sched.h>
#include <linux/delay.h>
void vmh_usleep_first_sample(void);
void vmh_usleep_expire_before_park(void);
void *vmh_usleep_host_worker(void *);
void vmh_usleep_range_tests(void);
#endif
