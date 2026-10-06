/* SPDX-License-Identifier: BSD-2-Clause */
#ifndef VINIX_QEMU_CORE_BLOCKED_FIXTURE_NATIVE_ABI_H
#define VINIX_QEMU_CORE_BLOCKED_FIXTURE_NATIVE_ABI_H
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
_Static_assert(sizeof(int)==4 && sizeof(pid_t)==4,"native process/status width");
_Static_assert(sizeof(pthread_t)==8,"native thread handle width");
_Static_assert(sizeof(time_t)==8 && sizeof(long)==8,"native timespec fields");
int reap_ok(pid_t);
void *vqb_block_in_read(void *);
#endif
