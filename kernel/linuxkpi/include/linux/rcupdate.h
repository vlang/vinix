/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_RCUPDATE_H
#define VINIX_LINUX_RCUPDATE_H
#include <linux/compiler.h>
/* Pointer publication only. No grace-period or read-side RCU API is claimed. */
#define rcu_assign_pointer(p, v) __atomic_store_n(&(p), (v), __ATOMIC_RELEASE)
#define RCU_INIT_POINTER(p, v) WRITE_ONCE(p, v)
#define rcu_dereference_raw(p) __atomic_load_n(&(p), __ATOMIC_ACQUIRE)
#endif
