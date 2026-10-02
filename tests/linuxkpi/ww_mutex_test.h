/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_WW_MUTEX_TEST_H
#define VINIX_WW_MUTEX_TEST_H

/* Included after sync_test.h: use the real Linux task wait backend and the
 * existing native scheduler model, with the unchanged public ww_mutex API. */
#include <linux/ww_mutex.h>

static void ww_test_wait(unsigned int *value, unsigned int target)
{
    for (unsigned int spin = 0; spin < 1000000; spin++) {
        if (__atomic_load_n(value, __ATOMIC_ACQUIRE) >= target) return;
        sched_yield();
    }
    assert(!"WW operation did not make progress");
}

static void ww_test_wait_queue(struct ww_mutex *lock, unsigned int target)
{
    for (unsigned int spin = 0; spin < 1000000; spin++) {
        if (mutex_waiters(&lock->base) == target) return;
        sched_yield();
    }
    assert(!"WW waiter did not attach or detach");
}

struct ww_test_actor {
    struct native_task_model model;
    struct ww_acquire_ctx ctx;
    struct ww_class *class;
    struct ww_mutex *first, *target;
    pthread_t thread;
    unsigned int ready, go, returned, dropped, retry, locked, release, done;
    unsigned int *order, *count, index;
    int result;
    bool no_context, interruptible, recover, slow;
};

static void *ww_test_actor_thread(void *argument)
{
    struct ww_test_actor *actor = argument;
    native_task = &actor->model;
    current_cpu = actor->index % 4;
    struct ww_acquire_ctx *ctx = actor->no_context ? NULL : &actor->ctx;
    if (ctx) ww_acquire_init(ctx, actor->class);
    unsigned long stamp = ctx ? ctx->stamp : 0;
    if (actor->first) assert(!ww_mutex_lock(actor->first, ctx));
    __atomic_store_n(&actor->ready, 1, __ATOMIC_RELEASE);
    ww_test_wait(&actor->go, 1);
    if (actor->target) {
        if (actor->slow) {
            if (actor->interruptible)
                actor->result = ww_mutex_lock_slow_interruptible(actor->target, ctx);
            else {
                ww_mutex_lock_slow(actor->target, ctx);
                actor->result = 0;
            }
        } else actor->result = actor->interruptible ?
            ww_mutex_lock_interruptible(actor->target, ctx) : ww_mutex_lock(actor->target, ctx);
    }
    assert(task_is_running(current) && interrupts && !preempt_depth);
    __atomic_store_n(&actor->returned, 1, __ATOMIC_RELEASE);
    if (actor->result) {
        assert(actor->result == -EDEADLK || actor->result == -EINTR);
        if (actor->first) ww_mutex_unlock(actor->first);
        assert(!ctx || !ctx->acquired);
        __atomic_store_n(&actor->dropped, 1, __ATOMIC_RELEASE);
        if (actor->recover) {
            assert(ctx && actor->result == -EDEADLK);
            ww_test_wait(&actor->retry, 1);
            ww_mutex_lock_slow(actor->target, ctx);
            assert(ctx->stamp == stamp && ctx->acquired == 1);
            if (actor->first) assert(!ww_mutex_lock(actor->first, ctx));
        }
    }
    if (!actor->result || actor->recover) {
        if (ctx) {
            assert(ctx->stamp == stamp);
            assert(ctx->acquired == !!actor->first + !!actor->target);
            if (actor->target) assert(actor->target->ctx == ctx);
            ww_acquire_done(ctx);
        }
        if (actor->count) {
            unsigned int slot = __atomic_fetch_add(actor->count, 1, __ATOMIC_ACQ_REL);
            actor->order[slot] = actor->index;
        }
        __atomic_store_n(&actor->locked, 1, __ATOMIC_RELEASE);
        ww_test_wait(&actor->release, 1);
        if (actor->target) ww_mutex_unlock(actor->target);
        if (actor->first) ww_mutex_unlock(actor->first);
    }
    if (ctx) { assert(!ctx->acquired); ww_acquire_fini(ctx); }
    assert(task_is_running(current) && interrupts && !preempt_depth);
    __atomic_store_n(&actor->done, 1, __ATOMIC_RELEASE);
    native_task = NULL;
    return NULL;
}

static void ww_test_actor_start(struct ww_test_actor *actor, struct ww_class *class,
                                struct ww_mutex *first, struct ww_mutex *target,
                                unsigned int index, bool no_context, bool interruptible)
{
    *actor = (struct ww_test_actor){ .class = class, .first = first, .target = target,
        .index = index, .no_context = no_context, .interruptible = interruptible };
    sync_model_init(&actor->model, 210 + index);
    actor->model.iteration = 1;
    assert(!pthread_create(&actor->thread, NULL, ww_test_actor_thread, actor));
    ww_test_wait(&actor->ready, 1);
}

static void ww_test_actor_go(struct ww_test_actor *actor)
{
    __atomic_store_n(&actor->go, 1, __ATOMIC_RELEASE);
}

static void ww_test_actor_release(struct ww_test_actor *actor)
{
    __atomic_store_n(&actor->release, 1, __ATOMIC_RELEASE);
}

static void ww_test_actor_join(struct ww_test_actor *actor)
{
    ww_test_wait(&actor->done, 1);
    assert(!pthread_join(actor->thread, NULL));
    sync_model_destroy(&actor->model);
}

static void ww_test_basic(struct ww_class *class)
{
    struct ww_mutex a, b;
    struct ww_acquire_ctx ctx;
    ww_mutex_init(&a, class); ww_mutex_init(&b, class);
    ww_acquire_init(&ctx, class);
    assert(ctx.task == current && !ctx.acquired && !ctx.wounded);
    assert(ctx.is_wait_die == class->is_wait_die && !ww_mutex_is_locked(&a));
    /* First acquisition resets any abandoned wound; a free lock also wins
     * over a pending signal, just like the ordinary mutex fast path. */
    ctx.wounded = 1;
    native_task->pending = 1ULL << 14;
    assert(!ww_mutex_lock_interruptible(&a, &ctx));
    native_task->pending = 0;
    assert(!ctx.wounded && ctx.acquired == 1 && a.ctx == &ctx);
    assert(ww_mutex_lock(&a, &ctx) == -EALREADY);
    assert(ww_mutex_lock_interruptible(&a, &ctx) == -EALREADY);
    assert(!ww_mutex_trylock(&a, &ctx) && ctx.acquired == 1);
    unsigned long flags = vinix_linuxkpi_irq_save();
    assert(ww_mutex_trylock(&b, &ctx));
    vinix_linuxkpi_irq_restore(flags);
    assert(ctx.acquired == 2 && b.ctx == &ctx);
    ww_acquire_done(&ctx);
    ww_mutex_unlock(&a); assert(ctx.acquired == 1 && !a.ctx);
    ww_mutex_unlock(&b); assert(!ctx.acquired);
    ww_acquire_fini(&ctx);
    assert(ww_mutex_trylock(&a, NULL));
    assert(!a.ctx && ww_mutex_is_locked(&a));
    ww_mutex_unlock(&a);
    assert(!ww_mutex_lock_interruptible(&b, NULL));
    ww_mutex_unlock(&b);
    ww_mutex_destroy(&a); ww_mutex_destroy(&b);
}

static void ww_test_wait_die_inversion(bool wrap)
{
    DEFINE_WD_CLASS(class);
    if (wrap) atomic_long_set(&class.stamp, -2);
    struct ww_mutex a, b;
    ww_mutex_init(&a, &class); ww_mutex_init(&b, &class);
    struct ww_acquire_ctx old;
    ww_acquire_init(&old, &class);
    assert(!ww_mutex_lock(&a, &old));
    struct ww_test_actor young;
    ww_test_actor_start(&young, &class, &b, &a, 0, false, false);
    young.recover = true;
    unsigned long stamp = young.ctx.stamp;
    if (wrap) assert(old.stamp == ULONG_MAX && stamp == 0);
    ww_test_actor_go(&young);
    ww_test_wait(&young.dropped, 1);
    assert(young.result == -EDEADLK && !young.ctx.acquired && !mutex_waiters(&a.base));
    assert(!ww_mutex_lock(&b, &old));
    ww_mutex_unlock(&b);
    /* Backoff drops every object, then slow-locks the saved contention
     * object and retries using the original transaction stamp. */
    __atomic_store_n(&young.retry, 1, __ATOMIC_RELEASE);
    ww_test_wait_queue(&a, 1);
    ww_test_wait(&young.model.parked, 1);
    assert(young.ctx.stamp == stamp && !young.ctx.acquired);
    ww_mutex_unlock(&a);
    ww_test_wait(&young.locked, 1);
    assert(young.ctx.stamp == stamp && young.ctx.acquired == 2);
    ww_test_actor_release(&young); ww_test_actor_join(&young);
    ww_acquire_fini(&old);
    ww_mutex_destroy(&a); ww_mutex_destroy(&b);
}

static void ww_test_wait_die_three_cycle(void)
{
    DEFINE_WD_CLASS(class);
    struct ww_mutex locks[3]; struct ww_test_actor actors[3];
    for (unsigned int i = 0; i < 3; i++) ww_mutex_init(&locks[i], &class);
    for (unsigned int i = 0; i < 3; i++)
        ww_test_actor_start(&actors[i], &class, &locks[i], &locks[(i + 1) % 3], i, false, false);
    actors[2].recover = true;
    ww_test_actor_go(&actors[0]); ww_test_wait_queue(&locks[1], 1);
    ww_test_wait(&actors[0].model.parked, 1);
    ww_test_actor_go(&actors[1]); ww_test_wait_queue(&locks[2], 1);
    ww_test_wait(&actors[1].model.parked, 1);
    ww_test_actor_go(&actors[2]); ww_test_wait(&actors[2].dropped, 1);
    assert(actors[2].result == -EDEADLK);
    ww_test_wait(&actors[1].locked, 1);
    ww_test_actor_release(&actors[1]); ww_test_actor_join(&actors[1]);
    ww_test_wait(&actors[0].locked, 1);
    ww_test_actor_release(&actors[0]); ww_test_actor_join(&actors[0]);
    __atomic_store_n(&actors[2].retry, 1, __ATOMIC_RELEASE);
    ww_test_wait(&actors[2].locked, 1);
    ww_test_actor_release(&actors[2]); ww_test_actor_join(&actors[2]);
    for (unsigned int i = 0; i < 3; i++) ww_mutex_destroy(&locks[i]);
}

static void ww_test_wait_die_queued_older(void)
{
    DEFINE_WD_CLASS(class);
    struct ww_mutex target, private[3];
    ww_mutex_init(&target, &class);
    for (unsigned int i = 0; i < ARRAY_SIZE(private); i++) ww_mutex_init(&private[i], &class);
    assert(!ww_mutex_lock(&target, NULL));
    struct ww_test_actor older, younger;
    ww_test_actor_start(&older, &class, &private[0], &target, 0, false, false);
    ww_test_actor_start(&younger, &class, &private[1], &target, 1, false, false);
    /* A context-free owner gives the younger waiter no owner-based reason
     * to die. A later, older queued transaction must wake and abort it. */
    ww_test_actor_go(&younger); ww_test_wait(&younger.model.parked, 1);
    ww_test_actor_go(&older); ww_test_wait(&younger.dropped, 1);
    assert(younger.result == -EDEADLK && !younger.ctx.acquired);
    ww_test_actor_join(&younger); ww_test_wait_queue(&target, 1);
    struct ww_test_actor arriving;
    ww_test_actor_start(&arriving, &class, &private[2], &target, 2, false, false);
    ww_test_actor_go(&arriving); ww_test_wait(&arriving.dropped, 1);
    assert(arriving.result == -EDEADLK && !arriving.model.parked);
    ww_test_actor_join(&arriving); ww_test_wait_queue(&target, 1);
    ww_mutex_unlock(&target);
    ww_test_wait(&older.locked, 1);
    ww_test_actor_release(&older); ww_test_actor_join(&older);
    ww_mutex_destroy(&target);
    for (unsigned int i = 0; i < ARRAY_SIZE(private); i++) ww_mutex_destroy(&private[i]);
}

static void ww_test_wound_blocked_elsewhere(void)
{
    DEFINE_WW_CLASS(class);
    struct ww_mutex a, b; struct ww_acquire_ctx old;
    ww_mutex_init(&a, &class); ww_mutex_init(&b, &class);
    ww_acquire_init(&old, &class);
    assert(!ww_mutex_lock(&a, &old));
    struct ww_test_actor young;
    ww_test_actor_start(&young, &class, &b, &a, 0, false, false);
    young.recover = true;
    ww_test_actor_go(&young); ww_test_wait(&young.model.parked, 1);
    assert(!__atomic_load_n(&young.ctx.wounded, __ATOMIC_ACQUIRE));
    /* Older requests B, while its younger owner sleeps on A. Wounding
     * must wake that task on the other lock and make it drop B. */
    assert(!ww_mutex_lock(&b, &old));
    ww_test_wait(&young.dropped, 1);
    assert(young.result == -EDEADLK && young.ctx.wounded && old.acquired == 2);
    __atomic_store_n(&young.retry, 1, __ATOMIC_RELEASE);
    ww_test_wait_queue(&a, 1);
    assert(!young.ctx.wounded && !young.ctx.acquired);
    ww_mutex_unlock(&b); ww_mutex_unlock(&a);
    ww_test_wait(&young.locked, 1);
    assert(!young.ctx.wounded);
    ww_test_actor_release(&young); ww_test_actor_join(&young);
    ww_acquire_fini(&old);
    ww_mutex_destroy(&a); ww_mutex_destroy(&b);
}

static void ww_test_first_lock(struct ww_class *class)
{
    struct ww_mutex lock; struct ww_acquire_ctx old;
    ww_mutex_init(&lock, class); ww_acquire_init(&old, class);
    assert(!ww_mutex_lock(&lock, &old));
    struct ww_test_actor first;
    ww_test_actor_start(&first, class, NULL, &lock, 0, false, false);
    ww_test_actor_go(&first); ww_test_wait(&first.model.parked, 1);
    assert(!__atomic_load_n(&first.returned, __ATOMIC_ACQUIRE) && !first.ctx.acquired);
    /* An ordinary signal does not abort an uninterruptible WW wait. */
    __atomic_store_n(&first.model.pending, 1ULL << 14, __ATOMIC_RELEASE);
    assert(vinix_linuxkpi_task_enqueue(&first.model));
    for (unsigned int spin = 0; spin < 1000000; spin++) {
        if (!vinix_linuxkpi_task_queued(&first.model)) break;
        sched_yield();
    }
    assert(!vinix_linuxkpi_task_queued(&first.model));
    assert(!__atomic_load_n(&first.returned, __ATOMIC_ACQUIRE));
    ww_mutex_unlock(&lock);
    ww_test_wait(&first.locked, 1);
    ww_test_actor_release(&first); ww_test_actor_join(&first);
    ww_acquire_fini(&old); ww_mutex_destroy(&lock);
}

static void ww_test_first_request_does_not_wound(void)
{
    DEFINE_WW_CLASS(class);
    struct ww_mutex lock; ww_mutex_init(&lock, &class);
    struct ww_test_actor older, younger;
    ww_test_actor_start(&older, &class, NULL, &lock, 0, false, false);
    ww_test_actor_start(&younger, &class, &lock, NULL, 1, false, false);
    ww_test_actor_go(&younger); ww_test_wait(&younger.locked, 1);
    struct ww_acquire_ctx try;
    ww_acquire_init(&try, &class); try.wounded = 1;
    assert(!ww_mutex_trylock(&lock, &try) && !try.wounded && !try.acquired);
    ww_acquire_fini(&try);
    ww_test_actor_go(&older); ww_test_wait(&older.model.parked, 1);
    assert(!__atomic_load_n(&younger.ctx.wounded, __ATOMIC_ACQUIRE));
    ww_test_actor_release(&younger); ww_test_actor_join(&younger);
    ww_test_wait(&older.locked, 1);
    ww_test_actor_release(&older); ww_test_actor_join(&older);
    ww_mutex_destroy(&lock);
}

static void ww_test_wounded_free_lock(void)
{
    DEFINE_WW_CLASS(class);
    struct ww_mutex a, b, free_lock;
    ww_mutex_init(&a, &class); ww_mutex_init(&b, &class); ww_mutex_init(&free_lock, &class);
    struct ww_test_actor older;
    ww_test_actor_start(&older, &class, &b, &a, 0, false, false);
    struct ww_acquire_ctx young; ww_acquire_init(&young, &class);
    assert(!ww_mutex_lock(&a, &young));
    ww_test_actor_go(&older); ww_test_wait(&older.model.parked, 1);
    assert(__atomic_load_n(&young.wounded, __ATOMIC_ACQUIRE));
    assert(!ww_mutex_lock(&free_lock, &young));
    assert(young.wounded && young.acquired == 2);
    assert(!ww_mutex_trylock(&b, &young));
    assert(ww_mutex_lock(&b, &young) == -EDEADLK);
    assert(young.acquired == 2 && young.wounded);
    ww_mutex_unlock(&a); ww_mutex_unlock(&free_lock);
    ww_test_wait(&older.locked, 1);
    ww_test_actor_release(&older); ww_test_actor_join(&older);
    assert(!ww_mutex_lock(&free_lock, &young));
    assert(!young.wounded && young.acquired == 1);
    ww_mutex_unlock(&free_lock); ww_acquire_fini(&young);
    ww_mutex_destroy(&a); ww_mutex_destroy(&b); ww_mutex_destroy(&free_lock);
}

static void ww_test_waiter_fairness(struct ww_class *class)
{
    struct ww_mutex lock; ww_mutex_init(&lock, class);
    assert(!ww_mutex_lock(&lock, NULL));
    struct ww_test_actor actors[6]; unsigned int order[6], count = 0;
    /* Context age and arrival order differ. NULL-context callers stay FIFO
     * with one at the head and two following the younger context. */
    static const unsigned int starts[] = {1, 2, 3, 0, 4, 5};
    static const unsigned int arrivals[] = {0, 3, 4, 1, 5, 2};
    for (unsigned int i = 0; i < ARRAY_SIZE(starts); i++) {
        unsigned int index = starts[i];
        ww_test_actor_start(&actors[index], class, NULL, &lock, index,
            index == 0 || index >= 4, false);
        actors[index].order = order; actors[index].count = &count;
    }
    for (unsigned int i = 0; i < ARRAY_SIZE(arrivals); i++) {
        ww_test_actor_go(&actors[arrivals[i]]);
        ww_test_wait_queue(&lock, i + 1);
        ww_test_wait(&actors[arrivals[i]].model.parked, 1);
    }
    ww_mutex_unlock(&lock);
    for (unsigned int i = 0; i < ARRAY_SIZE(actors); i++) {
        ww_test_wait(&actors[i].locked, 1);
        assert(__atomic_load_n(&count, __ATOMIC_ACQUIRE) == i + 1 && order[i] == i);
        assert(!ww_mutex_trylock(&lock, NULL));
        ww_test_actor_release(&actors[i]); ww_test_actor_join(&actors[i]);
    }
    assert(!mutex_waiters(&lock.base)); ww_mutex_destroy(&lock);
}

static void ww_test_interrupt_and_handoff(struct ww_class *class)
{
    struct ww_mutex lock, private;
    ww_mutex_init(&lock, class); ww_mutex_init(&private, class);
    struct ww_test_actor actor;
    for (unsigned int round = 0; round < 200; round++) {
        assert(!ww_mutex_lock(&lock, NULL));
        ww_test_actor_start(&actor, class, &private, &lock, 0, false, true);
        /* Exercise the original slow-interruptible wrapper with no other
         * held mutex separately below; this path checks direct handoff. */
        ww_test_actor_go(&actor); ww_test_wait(&actor.model.parked, 1);
        __atomic_store_n(&actor.model.pending, 1ULL << 14, __ATOMIC_RELEASE);
        if (!class->is_wait_die) __atomic_store_n(&actor.ctx.wounded, 1, __ATOMIC_RELEASE);
        if (!(round & 1)) {
            assert(vinix_linuxkpi_task_enqueue(&actor.model));
            ww_test_wait(&actor.dropped, 1);
            assert(actor.result == -EINTR && !actor.ctx.acquired);
            ww_test_actor_join(&actor);
            assert(!mutex_waiters(&lock.base) && ww_mutex_is_locked(&lock));
            ww_mutex_unlock(&lock);
        } else {
            /* Park is past schedule's signal check. Publish a signal without
             * waking; ownership installed by unlock must win on resumption. */
            ww_mutex_unlock(&lock);
            ww_test_wait(&actor.locked, 1);
            assert(!actor.result && actor.ctx.acquired == 2);
            ww_test_actor_release(&actor); ww_test_actor_join(&actor);
        }
        assert(!mutex_waiters(&lock.base) && !mutex_waiters(&private.base));
    }
    assert(!ww_mutex_lock(&lock, NULL));
    ww_test_actor_start(&actor, class, NULL, &lock, 0, false, true);
    actor.slow = true;
    ww_test_actor_go(&actor); ww_test_wait(&actor.model.parked, 1);
    __atomic_store_n(&actor.model.pending, 1ULL << 14, __ATOMIC_RELEASE);
    assert(vinix_linuxkpi_task_enqueue(&actor.model));
    ww_test_actor_join(&actor);
    assert(actor.result == -EINTR && !mutex_waiters(&lock.base));
    ww_mutex_unlock(&lock);
    ww_mutex_destroy(&lock); ww_mutex_destroy(&private);
}

static void ww_test_wounded_handoff(void)
{
    DEFINE_WW_CLASS(class);
    struct ww_mutex target, private;
    ww_mutex_init(&target, &class); ww_mutex_init(&private, &class);
    assert(!ww_mutex_lock(&target, NULL));
    struct ww_test_actor actor;
    ww_test_actor_start(&actor, &class, &private, &target, 0, false, false);
    ww_test_actor_go(&actor); ww_test_wait(&actor.model.parked, 1);
    /* Model wound publication concurrent with a handoff, before its wake.
     * Actual cross-lock wounding and wake are exercised above. */
    __atomic_store_n(&actor.ctx.wounded, 1, __ATOMIC_RELEASE);
    ww_mutex_unlock(&target);
    ww_test_wait(&actor.locked, 1);
    assert(!actor.result && actor.ctx.wounded && actor.ctx.acquired == 2);
    ww_test_actor_release(&actor); ww_test_actor_join(&actor);
    ww_mutex_destroy(&target); ww_mutex_destroy(&private);
}

static void ww_mutex_tests(void)
{
    struct native_task_model controller;
    sync_model_init(&controller, 209); native_task = &controller;
    unsigned int saved_cpu = current_cpu;
    size_t before = live_pages;
    DEFINE_WD_CLASS(wait_die);
    DEFINE_WW_CLASS(wound_wait);
    /* Every WW runtime path, including parked waiters and stack context
     * reuse, must operate without an allocation. Host pthread bookkeeping
     * is outside the LinuxKPI page allocator. */
    fail_allocation = true;
    ww_test_basic(&wait_die); ww_test_basic(&wound_wait);
    ww_test_wait_die_inversion(false); ww_test_wait_die_inversion(true);
    ww_test_wait_die_three_cycle(); ww_test_wait_die_queued_older();
    ww_test_wound_blocked_elsewhere(); ww_test_wounded_free_lock();
    ww_test_first_lock(&wait_die); ww_test_first_lock(&wound_wait);
    ww_test_first_request_does_not_wound();
    ww_test_waiter_fairness(&wait_die); ww_test_waiter_fairness(&wound_wait);
    ww_test_interrupt_and_handoff(&wait_die); ww_test_interrupt_and_handoff(&wound_wait);
    ww_test_wounded_handoff();
    /* Distinct classes can nest using independent transaction contexts. */
    struct ww_mutex a, b; struct ww_acquire_ctx ac, bc;
    ww_mutex_init(&a, &wait_die); ww_mutex_init(&b, &wound_wait);
    ww_acquire_init(&ac, &wait_die); ww_acquire_init(&bc, &wound_wait);
    assert(!ww_mutex_lock(&a, &ac) && !ww_mutex_lock(&b, &bc));
    ww_mutex_unlock(&b); ww_mutex_unlock(&a);
    ww_acquire_fini(&bc); ww_acquire_fini(&ac);
    ww_mutex_destroy(&b); ww_mutex_destroy(&a);
    fail_allocation = false;
    assert(live_pages == before && task_is_running(current) && interrupts && !preempt_depth);
    current_cpu = saved_cpu; native_task = NULL; sync_model_destroy(&controller);
}

#endif
