/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_PROC_MAP_FIXTURE_NATIVE_ABI_H
#define VINIX_PROC_MAP_FIXTURE_NATIVE_ABI_H
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/reboot.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
typedef long vml_long;
typedef unsigned long vml_ulong;
_Static_assert(sizeof(vml_long) == 8 && sizeof(vml_ulong) == 8 && sizeof(uintptr_t) == 8,
               "native scanner, counter and callback word widths");
_Static_assert(sizeof(pid_t) == 4 && sizeof(int) == 4 && sizeof(unsigned) == 4,
               "native process and epoch widths");
_Static_assert(sizeof(((struct dirent *)0)->d_name) == 256, "actual Linux directory name capacity");
_Static_assert(sizeof(((struct timespec *)0)->tv_sec) == 8 && sizeof(((struct timespec *)0)->tv_nsec) == 8,
               "native timeout widths");
_Static_assert(sizeof(pthread_t) == 8 && sizeof(pthread_mutex_t) == 40, "native musl thread/mutex storage");
#endif
