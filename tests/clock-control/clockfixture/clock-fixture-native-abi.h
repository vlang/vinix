/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_CLOCK_FIXTURE_NATIVE_ABI_H
#define VINIX_CLOCK_FIXTURE_NATIVE_ABI_H
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <sys/timex.h>
#include <sys/timerfd.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
typedef unsigned long long vcc_native_ull;
_Static_assert(sizeof(struct timex) == 208, "Linux timex ABI");
_Static_assert(offsetof(struct timex, time) == 72, "Linux timeval offset");
_Static_assert(sizeof(time_t) == 8 && sizeof(long) == 8, "clock native LP64 fields");
_Static_assert(sizeof(timer_t) == 8 && sizeof(pid_t) == 4 && sizeof(uid_t) == 4, "native clock process ABI");
_Static_assert(sizeof(vcc_native_ull) == 8, "native timerfd counter ABI");
#endif
