/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_WAIT_HOST_V_CONTRACT_H
#define VINIX_LINUXKPI_WAIT_HOST_V_CONTRACT_H
#include "host_model_v_contract.h"
#include <sched.h>
#include <linux/init.h>
#include <linux/bitops.h>
#include <linux/wait_bit.h>
#include <linux/limits.h>
#include <sys/mman.h>
unsigned int vmh_queue_waiters(struct wait_queue_head *);
void vmh_host_time_advance(vmh_u64);
int vmh_wait_bit_action(struct wait_bit_key *, int);
int vmh_wait_bit_custom_action(struct wait_bit_key *, int);
void vmh_wait_bit_clear_hook(void);
void vmh_wait_bit_expiry_hook(void);
void *vmh_wait_bit_actor_thread(void *);
void vmh_wait_bit_tests(void);
#endif
