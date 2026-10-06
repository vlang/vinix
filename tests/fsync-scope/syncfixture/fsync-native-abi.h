/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_FSYNC_SCOPE_NATIVE_ABI_H
#define VINIX_FSYNC_SCOPE_NATIVE_ABI_H
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>
_Static_assert(sizeof(int) == 4 && sizeof(long) == 8 && sizeof(off_t) == 8,
               "native descriptor and syscall widths");
#endif
