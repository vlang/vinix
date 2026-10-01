/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_SPINLOCK_H
#define VINIX_LINUX_SPINLOCK_H
#include <vinix/runtime.h>
#include <linux/spinlock_types.h>
static inline void spin_lock_init(spinlock_t *lock) { __atomic_store_n(&lock->locked, 0, __ATOMIC_RELAXED); }
static inline bool vinix_raw_spin_trylock(spinlock_t *lock) {
    unsigned int expected = 0;
    return __atomic_compare_exchange_n(&lock->locked, &expected, 1, false, __ATOMIC_ACQUIRE, __ATOMIC_RELAXED);
}
static inline void spin_lock(spinlock_t *lock) {
    vinix_linuxkpi_preempt_disable();
    while (!vinix_raw_spin_trylock(lock)) vinix_linuxkpi_spin_wait();
}
static inline bool spin_trylock(spinlock_t *lock) {
    vinix_linuxkpi_preempt_disable();
    if (vinix_raw_spin_trylock(lock)) return true;
    vinix_linuxkpi_preempt_enable();
    return false;
}
static inline void spin_unlock(spinlock_t *lock) {
    __atomic_store_n(&lock->locked, 0, __ATOMIC_RELEASE);
    vinix_linuxkpi_preempt_enable();
}
#define spin_lock_irqsave(lock, flags) do { \
    (flags) = vinix_linuxkpi_irq_save(); spin_lock(lock); \
} while (0)
#define spin_unlock_irqrestore(lock, flags) do { \
    spin_unlock(lock); vinix_linuxkpi_irq_restore(flags); \
} while (0)
static inline void spin_lock_irq(spinlock_t *lock) { (void)vinix_linuxkpi_irq_save(); spin_lock(lock); }
static inline void spin_unlock_irq(spinlock_t *lock) { spin_unlock(lock); vinix_linuxkpi_irq_restore(1UL << 9); }
#endif
