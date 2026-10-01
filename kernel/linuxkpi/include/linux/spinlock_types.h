/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_SPINLOCK_TYPES_H
#define VINIX_LINUX_SPINLOCK_TYPES_H
#include <linux/spinlock_types_raw.h>
typedef raw_spinlock_t spinlock_t;
#define __SPIN_LOCK_UNLOCKED(name) { 0 }
#define DEFINE_SPINLOCK(name) spinlock_t name = __SPIN_LOCK_UNLOCKED(name)
#endif
