/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_HOSTTASK_V_CONTRACT_H
#define VINIX_LINUXKPI_HOSTTASK_V_CONTRACT_H
#include "host_model_v_contract.h"
void *vmh_task_worker(void *);
void *vmh_task_wait_worker(void *);
void vmh_task_tests(void);
void vmh_task_wait_tests(void);
#endif
