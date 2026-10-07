/* SPDX-License-Identifier: GPL-2.0-only */
/* Native declarations and layout constraints; the independent fixture is V. */
#ifndef VINIX_INIT_HOST_NATIVE_ABI_H
#define VINIX_INIT_HOST_NATIVE_ABI_H
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <setjmp.h>
typedef jmp_buf vinix_init_escape;
struct delay { int64_t seconds, nanoseconds; };
struct action { void (*handler)(int); uint64_t flags; void (*restorer)(void); uint64_t mask; };
void vinix_init_shell(void), vinix_init_full(void);
void vinix_init_power_signal(int), vinix_init_child_signal(int);
void initcore__prepare_desktop_boot(void), initcore__prepare_hosted_x11_storage(void);
void initcore__install_power_signals(void), initcore__apply_power_request(void);
void initcore__pause_for(struct delay), initcore__wait_for_child(int64_t,int32_t *);
void initcore__stop_desktop_group(int64_t);
int64_t initcore__spawn_program(char **,char **,bool,int32_t *,char **,bool);
extern volatile int32_t vinit_power, vinit_reload;
_Static_assert(sizeof(int) == 4 && sizeof(bool) == 1 && sizeof(void *) == 8, "host scalar ABI");
_Static_assert(sizeof(struct delay) == 16 && _Alignof(struct delay) == 8 && offsetof(struct delay, nanoseconds) == 8, "by-value raw time record");
_Static_assert(sizeof(struct action) == 32 && _Alignof(struct action) == 8 && offsetof(struct action, flags) == 8 && offsetof(struct action, restorer) == 16 && offsetof(struct action, mask) == 24, "raw signal action record");
#endif
