/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_POSIX_TIMER_FIXTURE_NATIVE_ABI_H
#define VINIX_POSIX_TIMER_FIXTURE_NATIVE_ABI_H
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
typedef union sigval vpt_sigval;
typedef unsigned long long vpt_native_ull;
struct vpt_kernel_event { uint64_t value; int signo, notify, tid; };
struct vpt_thread_state { int tid, result, code, value, timed; uint64_t elapsed; };
void vpt_timer_callback(vpt_sigval);
void *vpt_timer_receiver(void *);
_Static_assert(sizeof(vpt_sigval) == 8 && sizeof(vpt_native_ull) == 8, "native timer value ABI");
_Static_assert(sizeof(pthread_t) == 8 && sizeof(timer_t) == 8, "native timer/thread handles");
_Static_assert(sizeof(pid_t) == 4 && sizeof(int) == 4 && sizeof(time_t) == 8 && sizeof(long) == 8, "native timer LP64 fields");
_Static_assert(sizeof(struct vpt_kernel_event) == 24 && sizeof(struct vpt_thread_state) == 32, "raw timer fixture storage");
_Static_assert(__builtin_types_compatible_p(__typeof__(&vpt_timer_callback), __typeof__(((struct sigevent *)0)->sigev_notify_function)), "canonical union sigval callback type");
_Static_assert(__builtin_types_compatible_p(__typeof__(&vpt_timer_receiver), void *(*)(void *)), "native pthread receiver callback type");
#endif
