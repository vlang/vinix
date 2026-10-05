/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_INIT_SYSCALL_ABI_H
#define VINIX_INIT_SYSCALL_ABI_H
#include <stdint.h>
#include <stddef.h>
#ifdef VINIX_INIT_HOST_TEST
#include <stdio.h>
#else
struct vinit_file;
extern struct vinit_file *stderr;
int fprintf(struct vinit_file *, const char *, ...);
#endif
int64_t vinit_syscall(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
void *vinit_power_callback(void);
void *vinit_child_callback(void);
void *vinit_restorer(void);
int vinit_wifi_enabled(void);
int vinit_echo_enabled(void);
extern volatile int32_t vinit_power, vinit_reload;
#endif
