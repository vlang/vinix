/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_TIMER_HOST_V_CONTRACT_H
#define VINIX_LINUXKPI_TIMER_HOST_V_CONTRACT_H
#include "host_model_v_contract.h"
#include <sched.h>
#include <linux/timer.h>
void vmh_host_time_advance(vmh_u64);
void vmh_timer_callback(struct timer_list *);
void vmh_timer_static_callback(struct timer_list *);
void vmh_timer_race_callback(struct timer_list *);
void *vmh_timer_dispatch_thread(void *);
void *vmh_timer_delete_thread(void *);
void *vmh_timer_race_thread(void *);
void vmh_timer_tests(void);
#endif
