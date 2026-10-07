/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Parse libc's types and inline annotations before Linux compiler macros. */
/* Keep libc's device type and declarations separate from kernel dev_t32. */
#define dev_t vinix_linuxkpi_host_dev_t
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdlib.h>
#undef dev_t
/* musl leaves Linux's internal file-offset spelling to kernel headers. */
#if defined(__linux__) && !defined(__GLIBC__)
typedef long long loff_t;
#endif
/* Preloading libc wait declarations must not override the Linux wait ABI. */
#undef WNOHANG
#undef WUNTRACED
#undef WSTOPPED
#undef WCONTINUED
#undef WNOWAIT
#include <assert.h>
/* The imported Linux build-bug contract supplies the variadic native form. */
#undef static_assert
#define timer_delete vinix_linuxkpi_host_libc_timer_delete
#include <time.h>
#undef timer_delete
/* The native Linux va_list macros use the same builtins. Parse libc's guarded
 * declarations first so GCC does not diagnose whitespace-only redefinitions. */
#include <stdarg.h>
#undef va_start
#undef va_end
#undef va_arg
#undef va_copy
#include <linux/stdarg.h>
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
