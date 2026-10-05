/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Parse libc's types and inline annotations before Linux compiler macros. */
/* Keep libc's device type and declarations separate from kernel dev_t32. */
#define dev_t vinix_linuxkpi_host_dev_t
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdlib.h>
#undef dev_t
/* Preloading libc wait declarations must not override the Linux wait ABI. */
#undef WSTOPPED
#undef WCONTINUED
#undef WNOWAIT
#include <assert.h>
#include <time.h>
/* Linux ktime is also included through sched.h. Parse libc first, then let
 * the unchanged kernel headers supply their own clock IDs and tick units. */
#undef CLOCKS_PER_SEC
#undef CLOCK_REALTIME
#undef CLOCK_MONOTONIC
#undef CLOCK_PROCESS_CPUTIME_ID
#undef CLOCK_THREAD_CPUTIME_ID
#undef CLOCK_MONOTONIC_RAW
#undef CLOCK_REALTIME_COARSE
#undef CLOCK_MONOTONIC_COARSE
#undef CLOCK_BOOTTIME
#undef CLOCK_REALTIME_ALARM
#undef CLOCK_BOOTTIME_ALARM
#undef CLOCK_SGI_CYCLE
#undef CLOCK_TAI
#undef TIMER_ABSTIME
