/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_SYNC_HOST_V_CONTRACT_H
#define VINIX_LINUXKPI_SYNC_HOST_V_CONTRACT_H
#include "host_model_v_contract.h"
#include <sched.h>
#include <linux/mutex.h>
#undef WSTOPPED
#undef WCONTINUED
#undef WNOWAIT
#include <linux/completion.h>
#include <linux/limits.h>
void *vmh_sync_mutex_worker(void *);
void *vmh_sync_event_worker(void *);
int vmh_sync_record_wake(struct wait_queue_entry *, unsigned int, int, void *);
unsigned int vmh_mutex_waiters(struct mutex *);
unsigned int vmh_queue_waiters(struct wait_queue_head *);
void vmh_sync_tests(void);
#endif
