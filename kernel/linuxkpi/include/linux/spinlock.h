/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_SPINLOCK_H
#define VINIX_LINUX_SPINLOCK_H
#include <linux/kernel.h>
#include <vinix/runtime.h>
#include <linux/spinlock_types.h>
#include <asm/barrier.h>
/* The original x86 spinlock header exposes this real native spin hint. */
#include <asm/processor.h>
void spin_lock_init(spinlock_t *);
bool vinix_raw_spin_trylock(spinlock_t *);
void spin_lock(spinlock_t *);
bool spin_trylock(spinlock_t *);
void spin_unlock(spinlock_t *);
bool spin_is_locked(const spinlock_t *);
void spin_lock_irq(spinlock_t *);
void spin_unlock_irq(spinlock_t *);
#include <vinix/spinlock_adapters.h>
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
/* Required declarations for unchanged seqlock inlines. Native BH exclusion
 * is not implemented yet; callers of these APIs remain unresolved at link. */
void spin_lock_bh(spinlock_t *lock);
void spin_unlock_bh(spinlock_t *lock);
#endif
