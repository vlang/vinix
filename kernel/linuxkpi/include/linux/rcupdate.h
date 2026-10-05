/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_RCUPDATE_H
#define VINIX_LINUX_RCUPDATE_H
#include <linux/compiler.h>
#include <linux/cleanup.h>
#include <linux/lockdep_types.h>
#include <linux/preempt.h>
/* Pointer publication only. No grace-period or read-side RCU API is claimed. */
#define rcu_assign_pointer(p, v) __atomic_store_n(&(p), (v), __ATOMIC_RELEASE)
#define RCU_INIT_POINTER(p, v) WRITE_ONCE(p, v)
#define rcu_dereference_raw(p) __atomic_load_n(&(p), __ATOMIC_ACQUIRE)
/* Annotations only, matching CONFIG_DEBUG_LOCK_ALLOC=n. */
#define rcu_lock_acquire(map) do { } while (0)
#define rcu_try_lock_acquire(map) do { } while (0)
#define rcu_lock_release(map) do { } while (0)
/* SRCU supplies reader protection; this primitive supplies pointer ordering. */
#define __rcu_dereference_check(p, local, condition, space) \
({ __auto_type local = __atomic_load_n(&(p), __ATOMIC_ACQUIRE); local; })
#endif
