// SPDX-License-Identifier: GPL-2.0-or-later
#ifndef VINIX_ANDROID_RUNTIME_V_ABI_H
#define VINIX_ANDROID_RUNTIME_V_ABI_H
#ifndef _GNU_SOURCE
#define _GNU_SOURCE 1
#endif
#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <unistd.h>
#include "musl-statistics.h"
#if defined(__aarch64__) && defined(__linux__)
#include <stdio_ext.h>
#endif
extern int __vinix_malloc_stats(struct vinix_malloc_stats *, size_t) __attribute__((weak));
void __cxa_finalize(void *);
struct android_mallinfo {
    size_t arena, ordblks, smblks, hblks, hblkhd;
    size_t usmblks, fsmblks, uordblks, fordblks, keepcost;
};
typedef struct android_mallinfo android_mallinfo;
typedef struct vinix_malloc_stats vinix_malloc_stats;
typedef const void *vandroid_const_void_p;
typedef const char *vandroid_const_char_p;
typedef const struct sockaddr *vandroid_const_sockaddr_p;
_Static_assert(sizeof(struct android_mallinfo) == 80, "Bionic ARM64 mallinfo ABI");
_Static_assert(sizeof(size_t) == 8 && sizeof(uintptr_t) == 8 && sizeof(off_t) == 8,
               "Native Linux LP64 runtime ABI");
#if defined(__linux__) && !defined(__APPLE__)
_Static_assert(sizeof(pthread_mutex_t) == 40 && _Alignof(pthread_mutex_t) == 8,
               "Pinned musl native mutex storage");
_Static_assert(sizeof(pthread_once_t) == 4 && PTHREAD_ONCE_INIT == 0,
               "Pinned musl native once storage");
#endif
#ifdef mmap64
#undef mmap64
#endif
#endif
