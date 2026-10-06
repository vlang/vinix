// SPDX-License-Identifier: GPL-2.0-or-later
#ifndef VINIX_ANDROID_RUNTIME_HOST_ABI_H
#define VINIX_ANDROID_RUNTIME_HOST_ABI_H
#include "runtime-v-abi.h"
void __fseterr(FILE *);
int fixture_pthread_mutex_lock(pthread_mutex_t *);
int fixture_pthread_mutex_trylock(pthread_mutex_t *);
int fixture_pthread_mutex_unlock(pthread_mutex_t *);
void *fixture_dlsym(void *, const char *);
struct android_mallinfo bionic_mallinfo(void);
#endif
