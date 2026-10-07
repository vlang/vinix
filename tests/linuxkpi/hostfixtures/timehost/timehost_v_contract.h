/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_TIME_HOST_V_CONTRACT_H
#define VINIX_LINUXKPI_TIME_HOST_V_CONTRACT_H
#include "host_model_v_contract.h"
#include <sched.h>
#define timespec vinix_linux_timespec
#define timeval vinix_linux_timeval
#define itimerspec vinix_linux_itimerspec
#define timezone vinix_linux_timezone
#include <linux/ktime.h>
#include <linux/delay.h>
#undef timespec
#undef timeval
#undef itimerspec
#undef timezone
#undef WSTOPPED
#undef WCONTINUED
#undef WNOWAIT
#include <linux/completion.h>
#include <linux/limits.h>
typedef __int128 vmh_time_i128;
struct vmh_time_volatile_address { volatile uintptr_t value; };
typedef volatile unsigned int vmh_time_volatile_uint;
_Static_assert(sizeof(vmh_time_i128) == 16, "original wide time reconstruction");
_Static_assert(sizeof(struct vmh_time_volatile_address) == sizeof(uintptr_t),
               "original volatile address word");
void vmh_host_time_advance(vmh_u64);
void vmh_time_expire_before_park(void);
void *vmh_timed_wait_worker(void *);
void vmh_time_tests(void);
#endif
