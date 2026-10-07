/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Native libc declarations for the independent N64 desktop-client fixture. */
#ifndef VINIX_N64_GUEST_NATIVE_ABI_H
#define VINIX_N64_GUEST_NATIVE_ABI_H
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
_Static_assert(sizeof(int) == 4 && sizeof(pid_t) == 4, "native descriptor/process width");
_Static_assert(sizeof(uint32_t) == 4 && sizeof(int32_t) == 4, "VAPP and surface word width");
_Static_assert(sizeof(size_t) == 8 && sizeof(ssize_t) == 8 && sizeof(off_t) == 8,
               "native transfer, save and mapping widths");
_Static_assert(sizeof(struct pollfd) == 8 && offsetof(struct pollfd, fd) == 0 &&
               offsetof(struct pollfd, events) == 4 && offsetof(struct pollfd, revents) == 6,
               "native readiness descriptor layout");
#endif
