/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUX_MUTEX_H
#define VINIX_LINUX_MUTEX_H
#include <linux/atomic.h>
#include <linux/list.h>
#include <linux/spinlock_types.h>
#include <linux/lockdep_types.h>

/* Ordinary non-RT mutex layout. No optimistic spinning or ww_mutex support. */
struct mutex {
    atomic_long_t owner;
    raw_spinlock_t wait_lock;
    struct list_head wait_list;
};
#define __MUTEX_INITIALIZER(name) { \
    .owner = ATOMIC_LONG_INIT(0), \
    .wait_lock = __RAW_SPIN_LOCK_UNLOCKED(name.wait_lock), \
    .wait_list = LIST_HEAD_INIT(name.wait_list) }
#define DEFINE_MUTEX(name) struct mutex name = __MUTEX_INITIALIZER(name)
void __mutex_init(struct mutex *lock, const char *name, struct lock_class_key *key);
#define mutex_init(lock) do { \
    static struct lock_class_key __key; __mutex_init((lock), #lock, &__key); \
} while (0)
void mutex_destroy(struct mutex *lock);
bool mutex_is_locked(struct mutex *lock);
void mutex_lock(struct mutex *lock);
int mutex_lock_interruptible(struct mutex *lock);
int mutex_lock_killable(struct mutex *lock);
int mutex_trylock(struct mutex *lock);
void mutex_unlock(struct mutex *lock);
int atomic_dec_and_mutex_lock(atomic_t *count, struct mutex *lock);
/* Match Linux's CONFIG_DEBUG_LOCK_ALLOC=n aliases; these are annotations. */
#define mutex_lock_nested(lock, subclass) mutex_lock(lock)
#define mutex_lock_interruptible_nested(lock, subclass) mutex_lock_interruptible(lock)
#define mutex_lock_killable_nested(lock, subclass) mutex_lock_killable(lock)
#define mutex_lock_nest_lock(lock, nest_lock) mutex_lock(lock)
#endif
