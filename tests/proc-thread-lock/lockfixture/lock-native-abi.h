/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_PROC_THREAD_LOCK_NATIVE_ABI_H
#define VINIX_PROC_THREAD_LOCK_NATIVE_ABI_H
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/reboot.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
typedef unsigned long vtl_ulong;
_Static_assert(sizeof(vtl_ulong) == 8 && sizeof(pthread_t) == 8,
               "native counters and thread handles");
_Static_assert(sizeof(pid_t) == 4 && sizeof(clockid_t) == 4 && sizeof(int) == 4,
               "native process, clock and status widths");
_Static_assert(sizeof(((struct timespec *)0)->tv_sec) == 8 &&
               sizeof(((struct timespec *)0)->tv_nsec) == 8, "native timespec widths");
#endif
