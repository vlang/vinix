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
static inline bool spin_is_locked(const spinlock_t *lock) {
    return __atomic_load_n(&lock->locked, __ATOMIC_RELAXED) != 0;
}
#define spin_lock_irqsave(lock, flags) do { \
    (flags) = vinix_linuxkpi_irq_save(); spin_lock(lock); \
} while (0)
#define spin_unlock_irqrestore(lock, flags) do { \
    spin_unlock(lock); vinix_linuxkpi_irq_restore(flags); \
} while (0)
/* Unlike lock_irqsave, a failed trylock must restore the incoming IRQ state. */
#define spin_trylock_irqsave(lock, flags) ({ \
    (flags) = vinix_linuxkpi_irq_save(); \
    bool __vinix_acquired = spin_trylock(lock); \
    if (!__vinix_acquired) vinix_linuxkpi_irq_restore(flags); \
    __vinix_acquired; \
})
static inline void spin_lock_irq(spinlock_t *lock) { (void)vinix_linuxkpi_irq_save(); spin_lock(lock); }
static inline void spin_unlock_irq(spinlock_t *lock) { spin_unlock(lock); vinix_linuxkpi_irq_restore(1UL << 9); }
#define raw_spin_lock_init spin_lock_init
#define raw_spin_lock spin_lock
#define raw_spin_unlock spin_unlock
#define raw_spin_trylock spin_trylock
#define raw_spin_is_locked spin_is_locked
#define raw_spin_lock_irqsave spin_lock_irqsave
#define raw_spin_unlock_irqrestore spin_unlock_irqrestore
#define raw_spin_trylock_irqsave spin_trylock_irqsave
#define raw_spin_lock_irq spin_lock_irq
#define raw_spin_unlock_irq spin_unlock_irq
#endif
