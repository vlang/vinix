/* SPDX-License-Identifier: GPL-2.0-only */
/* Stamp ordering, Wait-Die and Wound-Wait conditions follow the pinned
 * Linux 6.6.157 kernel/locking/ww_mutex.h and mutex.c algorithms:
 * Copyright (C) 2013 Canonical Ltd. (Wait-Die)
 * Copyright (C) 2018 VMware Inc. (algorithm selection)
 * Native stack waiters, direct handoff and lifetime serialization are
 * Vinix-specific. No optimistic spinning or RT priority inheritance. */
#ifdef VINIX_LINUXKPI
#include <linux/sched.h>
#include <linux/sched/signal.h>
#include <linux/ww_mutex.h>
#include <linux/spinlock.h>
#include <linux/bug.h>
#include <linux/errno.h>
#include <linux/limits.h>

/* A WW mutex is acquired/released through WW APIs, including NULL-context
 * users. Its ordinary native mutex layout is unchanged. Every waiter lives
 * on its task's stack and is detached under base.wait_lock before returning.
 * The owner keeps the lock and context storage alive until all users stop. */
struct native_ww_waiter {
    struct list_head entry;
    struct task_struct *task;
    struct ww_acquire_ctx *ctx;
};

static unsigned int context_acquired(struct ww_acquire_ctx *ctx)
{
    return __atomic_load_n(&ctx->acquired, __ATOMIC_ACQUIRE);
}
static bool context_younger(struct ww_acquire_ctx *a, struct ww_acquire_ctx *b)
{
    /* Exact pinned age comparison, including wrap. Live transactions must
     * remain within half the stamp sequence space. */
    return (long)(a->stamp - b->stamp) > 0;
}
static struct ww_acquire_ctx *owner_context(struct ww_mutex *lock)
{
    return __atomic_load_n(&lock->ctx, __ATOMIC_ACQUIRE);
}
static void prepare_context(struct ww_acquire_ctx *ctx)
{
    if (!ctx) return;
    BUG_ON(ctx->task != current || ctx->is_wait_die > 1);
    /* With no owned lock, no other task can still hold an owner pointer to
     * this context and wound it. Retain the original stamp after backing off. */
    if (!context_acquired(ctx))
        __atomic_store_n(&ctx->wounded, 0, __ATOMIC_RELEASE);
}
static void acquire_context(struct ww_mutex *lock, struct ww_acquire_ctx *ctx)
{
    BUG_ON(owner_context(lock));
    if (ctx) {
        unsigned int previous = __atomic_fetch_add(&ctx->acquired, 1, __ATOMIC_ACQ_REL);
        BUG_ON(previous == UINT_MAX);
    }
    __atomic_store_n(&lock->ctx, ctx, __ATOMIC_RELEASE);
}
static void release_context(struct ww_mutex *lock)
{
    struct ww_acquire_ctx *ctx = owner_context(lock);
    if (ctx) {
        BUG_ON(ctx->task != current);
        unsigned int previous = __atomic_fetch_sub(&ctx->acquired, 1, __ATOMIC_ACQ_REL);
        BUG_ON(!previous);
    }
    __atomic_store_n(&lock->ctx, NULL, __ATOMIC_RELEASE);
}
static struct native_ww_waiter *waiter_at(struct list_head *entry)
{
    /* Apply list_entry only to actual entries, never a sentinel. */
    return list_entry(entry, struct native_ww_waiter, entry);
}
static bool die_waiter(struct native_ww_waiter *waiter, struct ww_acquire_ctx *older)
{
    if (!older->is_wait_die) return false;
    if (context_acquired(waiter->ctx) && context_younger(waiter->ctx, older))
        wake_up_process(waiter->task);
    return true;
}
static bool wound_owner(struct ww_mutex *lock, struct ww_acquire_ctx *requester,
                        struct ww_acquire_ctx *holder)
{
    if (!holder || !context_acquired(requester) || !context_younger(holder, requester))
        return false;
    struct task_struct *owner = (struct task_struct *)atomic_long_read(&lock->base.owner);
    BUG_ON(!owner || holder->task != owner);
    /* Different locks can expose this same context, so their separate wait
     * locks do not serialize the wounded field. Publication must be atomic. */
    __atomic_store_n(&holder->wounded, 1, __ATOMIC_RELEASE);
    if (owner != current) wake_up_process(owner);
    return true;
}
static void check_waiters(struct ww_mutex *lock, struct ww_acquire_ctx *holder)
{
    if (!holder) return;
    struct list_head *entry;
    list_for_each(entry, &lock->base.wait_list) {
        struct native_ww_waiter *waiter = waiter_at(entry);
        if (!waiter->ctx) continue;
        if (die_waiter(waiter, holder) || wound_owner(lock, waiter->ctx, holder)) break;
    }
}
static int add_waiter(struct ww_mutex *lock, struct native_ww_waiter *waiter)
{
    struct ww_acquire_ctx *ctx = waiter->ctx;
    if (!ctx) {
        list_add_tail(&waiter->entry, &lock->base.wait_list);
        return 0;
    }
    /* Contexts are ordered by age. Skip context-free waiters while choosing
     * the position, preserving their interspersed FIFO fairness. */
    struct list_head *position = &lock->base.wait_list;
    struct list_head *entry;
    list_for_each_prev(entry, &lock->base.wait_list) {
        struct native_ww_waiter *existing = waiter_at(entry);
        if (!existing->ctx) continue;
        if (context_younger(ctx, existing->ctx)) {
            if (ctx->is_wait_die && context_acquired(ctx)) return -EDEADLK;
            break;
        }
        position = entry;
        die_waiter(existing, ctx);
    }
    list_add_tail(&waiter->entry, position);
    if (!ctx->is_wait_die) wound_owner(lock, ctx, owner_context(lock));
    return 0;
}
static bool must_back_off(struct ww_mutex *lock, struct native_ww_waiter *waiter)
{
    struct ww_acquire_ctx *ctx = waiter->ctx;
    if (!ctx || !context_acquired(ctx)) return false;
    if (!ctx->is_wait_die)
        return __atomic_load_n(&ctx->wounded, __ATOMIC_ACQUIRE) != 0;
    struct ww_acquire_ctx *holder = owner_context(lock);
    if (holder && context_younger(ctx, holder)) return true;
    /* Earlier context waiters are older because insertion preserves stamp
     * order. They can cause death even while a NULL-context task owns it. */
    struct list_head *entry;
    for (entry = waiter->entry.prev; entry != &lock->base.wait_list; entry = entry->prev)
        if (waiter_at(entry)->ctx) return true;
    return false;
}
static int acquire_ww_mutex(struct ww_mutex *lock, struct ww_acquire_ctx *ctx,
                            unsigned int state)
{
    might_sleep();
    struct task_struct *task = current;
    struct native_ww_waiter waiter = { .task = task, .ctx = ctx };
    INIT_LIST_HEAD(&waiter.entry);
    unsigned long flags;
    raw_spin_lock_irqsave(&lock->base.wait_lock, flags);
    if (ctx && owner_context(lock) == ctx) {
        BUG_ON(ctx->task != task || atomic_long_read(&lock->base.owner) != (long)task);
        raw_spin_unlock_irqrestore(&lock->base.wait_lock, flags);
        return -EALREADY;
    }
    prepare_context(ctx);
    long owner = atomic_long_read(&lock->base.owner);
    BUG_ON(owner == (long)task); /* NULL/different-context recursion is invalid. */
    if (!owner) {
        BUG_ON(!list_empty(&lock->base.wait_list));
        /* A free lock wins signals/wounding, as Linux's fast acquisition. */
        acquire_context(lock, ctx);
        atomic_long_set_release(&lock->base.owner, (long)task);
        check_waiters(lock, ctx);
        raw_spin_unlock_irqrestore(&lock->base.wait_lock, flags);
        return 0;
    }
    int result = add_waiter(lock, &waiter);
    if (result) {
        BUG_ON(!list_empty(&waiter.entry));
        raw_spin_unlock_irqrestore(&lock->base.wait_lock, flags);
        return result;
    }
    for (;;) {
        /* Direct handoff wins concurrent cancellation. The unlocker installs
         * context/count before owner publication and detaches this waiter. */
        if (atomic_long_read(&lock->base.owner) == (long)task) {
            BUG_ON(!list_empty(&waiter.entry) || owner_context(lock) != ctx);
            __set_current_state(TASK_RUNNING);
            raw_spin_unlock_irqrestore(&lock->base.wait_lock, flags);
            return 0;
        }
        if (signal_pending_state(state, task)) result = -EINTR;
        else if (must_back_off(lock, &waiter)) result = -EDEADLK;
        else result = 0;
        if (result) {
            list_del_init(&waiter.entry);
            __set_current_state(TASK_RUNNING);
            raw_spin_unlock_irqrestore(&lock->base.wait_lock, flags);
            return result;
        }
        set_current_state(state);
        raw_spin_unlock_irqrestore(&lock->base.wait_lock, flags);
        schedule();
        raw_spin_lock_irqsave(&lock->base.wait_lock, flags);
    }
}
int ww_mutex_lock(struct ww_mutex *lock, struct ww_acquire_ctx *ctx)
{
    return acquire_ww_mutex(lock, ctx, TASK_UNINTERRUPTIBLE);
}
int ww_mutex_lock_interruptible(struct ww_mutex *lock, struct ww_acquire_ctx *ctx)
{
    return acquire_ww_mutex(lock, ctx, TASK_INTERRUPTIBLE);
}
int ww_mutex_trylock(struct ww_mutex *lock, struct ww_acquire_ctx *ctx)
{
    unsigned long flags;
    raw_spin_lock_irqsave(&lock->base.wait_lock, flags);
    prepare_context(ctx);
    int acquired = !atomic_long_read(&lock->base.owner);
    if (acquired) {
        BUG_ON(!list_empty(&lock->base.wait_list));
        acquire_context(lock, ctx);
        atomic_long_set_release(&lock->base.owner, (long)current);
        check_waiters(lock, ctx);
    }
    /* Trylock never sleeps or reports a deadlock, including same-context
     * ownership: pinned mutex.c returns 0 on every contended trylock. */
    raw_spin_unlock_irqrestore(&lock->base.wait_lock, flags);
    return acquired;
}
void ww_mutex_unlock(struct ww_mutex *lock)
{
    unsigned long flags;
    raw_spin_lock_irqsave(&lock->base.wait_lock, flags);
    BUG_ON(atomic_long_read(&lock->base.owner) != (long)current);
    release_context(lock);
    if (list_empty(&lock->base.wait_list)) atomic_long_set_release(&lock->base.owner, 0);
    else {
        struct native_ww_waiter *waiter = waiter_at(lock->base.wait_list.next);
        struct task_struct *next = waiter->task;
        struct ww_acquire_ctx *ctx = waiter->ctx;
        list_del_init(&waiter->entry);
        acquire_context(lock, ctx);
        atomic_long_set_release(&lock->base.owner, (long)next);
        check_waiters(lock, ctx);
        /* Context/count/owner are fully published. Never touch the detached
         * stack record again; its task may return immediately on another CPU. */
        wake_up_process(next);
    }
    raw_spin_unlock_irqrestore(&lock->base.wait_lock, flags);
}
#endif
