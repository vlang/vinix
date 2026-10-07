/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Native declarations and widths only; the guest policy checks are V. */
#ifndef VINIX_SECURELEVEL_FIXTURE_NATIVE_ABI_H
#define VINIX_SECURELEVEL_FIXTURE_NATIVE_ABI_H
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/uio.h>
#include <sys/wait.h>
#include <unistd.h>
_Static_assert(sizeof(int) == 4 && sizeof(pid_t) == 4 && sizeof(mode_t) == 4 && sizeof(dev_t) == 8 && (dev_t)-1 > 0, "native process and device words");
_Static_assert(sizeof(long) == 8 && __builtin_types_compatible_p(long, ptrdiff_t) && sizeof(uintptr_t) == 8, "native callback argument words");
_Static_assert(sizeof(size_t) == 8 && sizeof(ssize_t) == 8 && __builtin_types_compatible_p(ssize_t, ptrdiff_t) && sizeof(off_t) == 8 && __builtin_types_compatible_p(off_t, int64_t), "native transfer and offset words");
_Static_assert(sizeof(pthread_t) == 8 && _Alignof(pthread_t) == 8 && __builtin_types_compatible_p(pthread_t, struct __pthread *), "native opaque joined thread handle");
_Static_assert(sizeof(void *(*)(void *)) == 8, "native pthread callback pointer");
_Static_assert(sizeof(struct iovec) == 16 && _Alignof(struct iovec) == 8 && offsetof(struct iovec, iov_base) == 0 && offsetof(struct iovec, iov_len) == 8, "native borrowed transfer vector");
void *vsecure_raise_level(void *);
/* Original fixture-local bodies remain private; the registered C wrapper is public. */
static void securefixture__check(_Bool, char *);
static int32_t securefixture__level(int32_t);
static int32_t securefixture__read_level(void);
static _Bool securefixture__wait_ok(int32_t);
static void *securefixture__raise_level(void *);
#endif
