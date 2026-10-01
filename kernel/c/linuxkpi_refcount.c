/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifdef VINIX_LINUXKPI
#include <linux/refcount.h>
#include <linux/spinlock.h>
#include <vinix/runtime.h>

/* The algorithms and saturation checks in Linux's refcount/kref headers stay
 * upstream. Sleepable mutex final-release helpers remain unresolved until a
 * real mutex backend exists; they must never degrade into spinning locks. */
void refcount_warn_saturate(refcount_t *r, enum refcount_saturation_type kind)
{
    refcount_set(r, REFCOUNT_SATURATED);
    vinix_linuxkpi_refcount_warning(kind);
}

bool refcount_dec_if_one(refcount_t *r)
{
    int old = 1;
    return atomic_try_cmpxchg_release(&r->refs, &old, 0);
}

bool refcount_dec_not_one(refcount_t *r)
{
    int old = atomic_read(&r->refs);
    for (;;) {
        if (old < 0) return true;
        if (old == 1) return false;
        if (old == 0) {
            refcount_warn_saturate(r, REFCOUNT_SUB_UAF);
            return true;
        }
        if (atomic_try_cmpxchg_release(&r->refs, &old, old - 1)) return true;
    }
}

bool refcount_dec_and_lock(refcount_t *r, spinlock_t *lock)
{
    if (refcount_dec_not_one(r)) return false;
    spin_lock(lock);
    if (refcount_dec_and_test(r)) return true;
    spin_unlock(lock);
    return false;
}

bool refcount_dec_and_lock_irqsave(refcount_t *r, spinlock_t *lock, unsigned long *flags)
{
    if (refcount_dec_not_one(r)) return false;
    spin_lock_irqsave(lock, *flags);
    if (refcount_dec_and_test(r)) return true;
    spin_unlock_irqrestore(lock, *flags);
    return false;
}
#endif
