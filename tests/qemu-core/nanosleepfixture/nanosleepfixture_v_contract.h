/* SPDX-License-Identifier: BSD-2-Clause */
#ifndef VINIX_QEMU_CORE_NANOSLEEP_FIXTURE_NATIVE_ABI_H
#define VINIX_QEMU_CORE_NANOSLEEP_FIXTURE_NATIVE_ABI_H
#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
struct vqn_volatile_signal { volatile sig_atomic_t value; };
_Static_assert(sizeof(sig_atomic_t)==4 && sizeof(struct vqn_volatile_signal)==4,"native signal counter width");
_Static_assert(_Alignof(struct vqn_volatile_signal)==_Alignof(sig_atomic_t),"native signal counter alignment");
_Static_assert(sizeof(pid_t)==4 && sizeof(int)==4,"native process/status ABI");
_Static_assert(sizeof(time_t)==8 && sizeof(long)==8,"native timespec fields");
int reap_ok(pid_t);
void vqn_nanosleep_interrupt(int);
#endif
