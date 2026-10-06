/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_PROCFS_MOUNT_FIXTURE_NATIVE_ABI_H
#define VINIX_PROCFS_MOUNT_FIXTURE_NATIVE_ABI_H
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
typedef long vpm_long;
_Static_assert(sizeof(vpm_long) == 8 && sizeof(size_t) == 8 && sizeof(ssize_t) == 8,
               "native mount snapshot and diagnostic widths");
_Static_assert(sizeof(int) == 4 && sizeof(pid_t) == 4, "native process/descriptor widths");
#endif
