/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_SPINLOCK_TYPES_RAW_H
#define VINIX_LINUX_SPINLOCK_TYPES_RAW_H
#include <linux/types.h>
/* This build has no PREEMPT_RT substitution: both lock classes spin. */
typedef struct raw_spinlock { unsigned int locked; } raw_spinlock_t;
#define __RAW_SPIN_LOCK_INITIALIZER(name) { .locked = 0 }
#define __RAW_SPIN_LOCK_UNLOCKED(name) ((raw_spinlock_t)__RAW_SPIN_LOCK_INITIALIZER(name))
#define DEFINE_RAW_SPINLOCK(name) raw_spinlock_t name = __RAW_SPIN_LOCK_UNLOCKED(name)
#endif
