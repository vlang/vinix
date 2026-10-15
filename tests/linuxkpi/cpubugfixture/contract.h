/* SPDX-License-Identifier: GPL-2.0-or-later */
/* ABI metadata and libc/compiler declarations; executable transport is V. */
#ifndef VINIX_CPU_BUG_FIXTURE_H
#define VINIX_CPU_BUG_FIXTURE_H
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <setjmp.h>
#include <asm/cpufeature.h>
typedef struct array cbh_array;
typedef struct string cbh_string;
typedef pthread_t cbh_thread;
typedef jmp_buf cbh_jump;
#define cbh_setjmp(record) setjmp(*(jmp_buf *)(record))
#define cbh_longjmp(record) longjmp(*(jmp_buf *)(record), 1)
_Static_assert(NCAPINTS == 22, "pinned capability word count");
_Static_assert(X86_BUG_L1TF == 722, "pinned L1TF bug index");
#endif
