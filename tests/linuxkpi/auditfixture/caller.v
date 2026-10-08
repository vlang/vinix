// SPDX-License-Identifier: GPL-2.0-or-later
module auditfixture

const caller = '#include <linux/spinlock.h>
#include <linux/atomic.h>
#include <linux/overflow.h>
#include <generated/bounds.h>
#define __GENERATING_BOUNDS_H
#include <linux/page-flags.h>
#include <linux/mmzone.h>
#include <linux/log2.h>
_Static_assert(NR_PAGEFLAGS == __NR_PAGEFLAGS, "actual configured page flags");
_Static_assert(MAX_NR_ZONES == __MAX_NR_ZONES, "actual configured zones");
_Static_assert(SPINLOCK_SIZE == sizeof(spinlock_t), "actual lock ABI");
_Static_assert(NR_CPUS_BITS == order_base_2(CONFIG_NR_CPUS), "configured CPUs");

void native_adapter_caller(spinlock_t *lock, unsigned long *value)
{
    unsigned long flags, sum;
    spin_lock_irqsave(lock, flags);
    (void)arch_xchg_relaxed(value, 1UL);
    (void)arch_cmpxchg_relaxed(value, 1UL, 2UL);
    (void)check_add_overflow(*value, 1UL, &sum);
    spin_unlock_irqrestore(lock, flags);
}
'
