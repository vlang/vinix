/* SPDX-License-Identifier: GPL-2.0-or-later */
/* ABI metadata and libc/compiler declarations; executable transport is V. */
#ifndef VINIX_MIGRATION_FIXTURE_H
#define VINIX_MIGRATION_FIXTURE_H
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <setjmp.h>
#include <linux/preempt.h>
typedef struct array mh_array;
typedef struct string mh_string;
typedef pthread_t mh_thread;
typedef jmp_buf mh_jump;
#define mh_setjmp(record) setjmp(*(jmp_buf *)(record))
#define mh_longjmp(record) longjmp(*(jmp_buf *)(record), 1)
/* Native array-index transport retains bounds checks without importing the
 * V runtime's panic-formatting allocator into the independent fixture. */
#define v_fixed_index mh_fixed_index
#define v_fixed_index_u64 mh_fixed_index_u64
_Static_assert(__builtin_types_compatible_p(__typeof__(&migrate_disable), void (*)(void)), "original disable prototype");
_Static_assert(__builtin_types_compatible_p(__typeof__(&migrate_enable), void (*)(void)), "original enable prototype");
#endif
