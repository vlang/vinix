/* SPDX-License-Identifier: BSD-2-Clause */
#ifndef VINIX_QEMU_CORE_RESTART_FIXTURE_NATIVE_ABI_H
#define VINIX_QEMU_CORE_RESTART_FIXTURE_NATIVE_ABI_H
#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
_Static_assert(sizeof(pid_t)==4 && sizeof(int)==4, "native signal process/status ABI");
_Static_assert(sizeof(time_t)==8 && sizeof(long)==8, "native timespec fields");
int reap_ok(pid_t);
void vqr_restart_handler(int);
#endif
