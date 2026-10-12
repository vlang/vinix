/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Native ABI metadata and libc/compiler interfaces; executable models are V. */
#ifndef VINIX_CPU_POLICY_TRANSPORT_H
#define VINIX_CPU_POLICY_TRANSPORT_H
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <setjmp.h>
typedef struct array vpp_array;
typedef struct string vpp_string;
typedef pthread_t vpp_thread;
typedef jmp_buf vpp_jump;
#define vpp_setjmp(record) setjmp(*(jmp_buf *)(record))
#define vpp_longjmp(record) longjmp(*(jmp_buf *)(record), 1)
#endif
