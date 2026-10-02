/* SPDX-License-Identifier: GPL-2.0-only */
/* Jiffy rounding adapted from Linux kernel/time/timer.c.
 * Copyright (C) 1991, 1992 Linus Torvalds. */
#ifdef VINIX_LINUXKPI
#include <linux/timer.h>
#include <linux/sched.h>
#include <linux/sched/task.h>
#include <linux/completion.h>

/* Preserve upstream timer_list and its lockless pending query. Queue links,
 * function shutdown and active callback records share one native raw lock. */
static DEFINE_RAW_SPINLOCK(timer_lock);
static HLIST_HEAD(pending_timers);
static HLIST_HEAD(ready_timers);
static LIST_HEAD(running_timers);
static struct task_struct *timer_worker;

struct timer_run {
    struct list_head entry;
    struct timer_list *timer;
    struct task_struct *task;
};

static struct timer_run *running_locked(const struct timer_list *timer)
{
    struct timer_run *run;
    list_for_each_entry(run, &running_timers, entry)
        if (run->timer == timer) return run;
    return NULL;
}

static struct timer_list *due_locked(void)
{
    struct timer_list *timer;
    hlist_for_each_entry(timer, &ready_timers, entry)
        if (!running_locked(timer)) return timer;
    return NULL;
}

static int detach_locked(struct timer_list *timer)
{
    if (!timer_pending(timer)) return 0;
    hlist_del_init(&timer->entry);
    return 1;
}

/* TIMER_PINNED/add_timer_on need native CPU placement. Deferrable/NOHZ timers
 * are also pending. Reject those modes instead of silently changing them. */
void init_timer_key(struct timer_list *timer, void (*function)(struct timer_list *),
                    unsigned int flags, const char *name, struct lock_class_key *key)
{
    BUG_ON(flags & ~TIMER_IRQSAFE);
    INIT_HLIST_NODE(&timer->entry);
    timer->expires = 0;
    timer->function = function;
    timer->flags = flags;
}

static int modify_timer(struct timer_list *timer, unsigned long expires,
                        bool pending_only, bool reduce, bool add)
{
    unsigned long flags;
    raw_spin_lock_irqsave(&timer_lock, flags);
    BUG_ON(timer->flags & ~TIMER_IRQSAFE);
    int pending = timer_pending(timer);
    if (add && pending) {
        WARN_ON_ONCE(true);
        raw_spin_unlock_irqrestore(&timer_lock, flags);
        return 0;
    }
    if (!timer->function || (pending_only && !pending)) {
        raw_spin_unlock_irqrestore(&timer_lock, flags);
        return 0;
    }
    if (pending && (timer->expires == expires || (reduce && time_before_eq(timer->expires, expires)))) {
        raw_spin_unlock_irqrestore(&timer_lock, flags);
        return 1;
    }
    detach_locked(timer);
    WRITE_ONCE(timer->expires, expires);
    hlist_add_head(&timer->entry, &pending_timers);
    raw_spin_unlock_irqrestore(&timer_lock, flags);
    return pending;
}

int mod_timer(struct timer_list *timer, unsigned long expires)
{
    return modify_timer(timer, expires, false, false, false);
}
int mod_timer_pending(struct timer_list *timer, unsigned long expires)
{
    return modify_timer(timer, expires, true, false, false);
}
int timer_reduce(struct timer_list *timer, unsigned long expires)
{
    return modify_timer(timer, expires, false, true, false);
}
void add_timer(struct timer_list *timer)
{
    modify_timer(timer, timer->expires, false, false, true);
}

static int delete_timer(struct timer_list *timer, bool sync, bool shutdown, bool blocking)
{
    unsigned long flags;
    raw_spin_lock_irqsave(&timer_lock, flags);
    struct timer_run *run = running_locked(timer);
    if (sync && run) {
        /* Waiting from the callback itself (or its interrupt) cannot finish. */
        BUG_ON(blocking && run->task == current);
        raw_spin_unlock_irqrestore(&timer_lock, flags);
        return -1;
    }
    int pending = detach_locked(timer);
    if (shutdown) WRITE_ONCE(timer->function, NULL);
    raw_spin_unlock_irqrestore(&timer_lock, flags);
    return pending;
}

int timer_delete(struct timer_list *timer) { return delete_timer(timer, false, false, false); }
int timer_shutdown(struct timer_list *timer) { return delete_timer(timer, false, true, false); }
int try_to_del_timer_sync(struct timer_list *timer) { return delete_timer(timer, true, false, false); }

static int delete_sync(struct timer_list *timer, bool shutdown)
{
    /* Ordinary callbacks run with IRQs enabled. As with Linux, waiting while
     * interrupts are disabled is only supported for TIMER_IRQSAFE timers. */
    BUG_ON(!(timer->flags & TIMER_IRQSAFE) && !(vinix_linuxkpi_irq_flags() & (1UL << 9)));
    int result;
    while ((result = delete_timer(timer, true, shutdown, true)) < 0) {
        vinix_linuxkpi_spin_wait();
        cond_resched();
    }
    return result;
}
int timer_delete_sync(struct timer_list *timer) { return delete_sync(timer, false); }
int timer_shutdown_sync(struct timer_list *timer) { return delete_sync(timer, true); }

/* Called after jiffies publication, outside the sleep-deadline lock. The PIT
 * only wakes the worker; arbitrary callbacks never run inside its ISR. */
void vinix_linuxkpi_timer_tick(void)
{
    unsigned long flags;
    raw_spin_lock_irqsave(&timer_lock, flags);
    struct timer_list *timer;
    struct hlist_node *next;
    /* Promotion happens only on ticks. A callback rearming at/past jiffies
     * waits for another tick, instead of looping indefinitely in dispatch. */
    hlist_for_each_entry_safe(timer, next, &pending_timers, entry) {
        if (time_after_eq(jiffies, timer->expires)) {
            hlist_del_init(&timer->entry);
            hlist_add_head(&timer->entry, &ready_timers);
        }
    }
    if (timer_worker && due_locked()) wake_up_process(timer_worker);
    raw_spin_unlock_irqrestore(&timer_lock, flags);
}

unsigned int vinix_linuxkpi_timer_dispatch(void)
{
    might_sleep();
    unsigned int count = 0;
    for (;;) {
        struct timer_run run = { .task = current };
        unsigned long flags;
        raw_spin_lock_irqsave(&timer_lock, flags);
        struct timer_list *timer = due_locked();
        if (!timer) {
            raw_spin_unlock_irqrestore(&timer_lock, flags);
            return count;
        }
        run.timer = timer;
        void (*function)(struct timer_list *) = timer->function;
        bool irq_safe = timer->flags & TIMER_IRQSAFE;
        BUG_ON(!function);
        detach_locked(timer);
        list_add_tail(&run.entry, &running_timers);
        /* Retain one preemption pin across unlock, callback and bookkeeping.
         * Normal callbacks permit IRQs; IRQSAFE callbacks keep them disabled. */
        preempt_disable();
        raw_spin_unlock_irqrestore(&timer_lock, irq_safe ? 0 : flags);
        unsigned int depth = preempt_count();
        function(timer);
        BUG_ON(preempt_count() != depth ||
               !!(vinix_linuxkpi_irq_flags() & (1UL << 9)) == irq_safe);
        raw_spin_lock_irqsave(&timer_lock, flags);
        /* A callback may free its own object. Never dereference timer here. */
        list_del_init(&run.entry);
        raw_spin_unlock_irqrestore(&timer_lock, flags);
        if (irq_safe) vinix_linuxkpi_irq_restore(1UL << 9);
        preempt_enable();
        count++;
    }
}

size_t vinix_linuxkpi_timer_active(void)
{
    unsigned long flags;
    size_t count = 0;
    raw_spin_lock_irqsave(&timer_lock, flags);
    struct hlist_node *node;
    hlist_for_each(node, &pending_timers) count++;
    hlist_for_each(node, &ready_timers) count++;
    struct list_head *entry;
    list_for_each(entry, &running_timers) count++;
    raw_spin_unlock_irqrestore(&timer_lock, flags);
    return count;
}

static unsigned long round_jiffy(unsigned long tick, int cpu, bool up)
{
    unsigned long original = tick;
    tick += cpu * 3;
    unsigned int remainder = tick % HZ;
    tick -= remainder;
    if (up || remainder >= HZ / 4) tick += HZ;
    tick -= cpu * 3;
    return time_is_after_jiffies(tick) ? tick : original;
}
unsigned long __round_jiffies(unsigned long tick, int cpu) { return round_jiffy(tick, cpu, false); }
unsigned long __round_jiffies_up(unsigned long tick, int cpu) { return round_jiffy(tick, cpu, true); }
unsigned long __round_jiffies_relative(unsigned long tick, int cpu)
{
    unsigned long now = jiffies;
    return round_jiffy(tick + now, cpu, false) - now;
}
unsigned long __round_jiffies_up_relative(unsigned long tick, int cpu)
{
    unsigned long now = jiffies;
    return round_jiffy(tick + now, cpu, true) - now;
}
unsigned long round_jiffies(unsigned long tick) { return __round_jiffies(tick, vinix_linuxkpi_cpu_id()); }
unsigned long round_jiffies_up(unsigned long tick) { return __round_jiffies_up(tick, vinix_linuxkpi_cpu_id()); }
unsigned long round_jiffies_relative(unsigned long tick) { return __round_jiffies_relative(tick, vinix_linuxkpi_cpu_id()); }
unsigned long round_jiffies_up_relative(unsigned long tick) { return __round_jiffies_up_relative(tick, vinix_linuxkpi_cpu_id()); }

static void unexpected_callback(struct timer_list *timer) { BUG(); }
int vinix_linuxkpi_timer_selftest(void)
{
    DEFINE_TIMER(timer, unexpected_callback);
    unsigned long expires = jiffies + 10000;
    int result = 0;
    if (timer_pending(&timer) || mod_timer_pending(&timer, expires)) result = -EIO;
    if (timer_reduce(&timer, expires) || !timer_pending(&timer)) result = -EIO;
    if (mod_timer(&timer, expires) != 1 || timer_reduce(&timer, expires + 1) != 1 ||
        timer.expires != expires) result = -EIO;
    if (try_to_del_timer_sync(&timer) != 1 || timer_delete_sync(&timer)) result = -EIO;
    timer.expires = expires;
    add_timer(&timer);
    if (timer_shutdown_sync(&timer) != 1 || timer_pending(&timer) || timer.function) result = -EIO;
    if (mod_timer(&timer, expires) || timer_pending(&timer)) result = -EIO;
    return result;
}

#ifndef VINIX_LINUXKPI_HOST_TEST
#include <pthread.h>
static DECLARE_COMPLETION(worker_ready);
static void *timer_thread(void *argument)
{
    unsigned long flags;
    struct task_struct *task = get_task_struct(current);
    raw_spin_lock_irqsave(&timer_lock, flags);
    timer_worker = task; /* Owned boot-lifetime reference; the worker never exits. */
    raw_spin_unlock_irqrestore(&timer_lock, flags);
    complete(&worker_ready);
    for (;;) {
        vinix_linuxkpi_timer_dispatch();
        raw_spin_lock_irqsave(&timer_lock, flags);
        if (due_locked()) {
            raw_spin_unlock_irqrestore(&timer_lock, flags);
            continue;
        }
        set_current_state(TASK_UNINTERRUPTIBLE);
        raw_spin_unlock_irqrestore(&timer_lock, flags);
        schedule();
    }
    return NULL;
}

int vinix_linuxkpi_timer_bootstrap(void)
{
    pthread_t thread;
    if (pthread_create(&thread, NULL, timer_thread, NULL)) return -ENOMEM;
    BUG_ON(pthread_detach(thread));
    wait_for_completion(&worker_ready);
    return 0;
}

struct native_timer_test {
    struct timer_list timer;
    struct completion done;
    unsigned int calls;
    int result;
    unsigned int callback_reasons;
    unsigned long bad_tick, bad_expires, bad_irq_flags;
    unsigned int bad_depth;
    bool irq_safe;
};
static void native_timer_callback(struct timer_list *timer)
{
    struct native_timer_test *test = from_timer(test, timer, timer);
    unsigned int reasons = 0, depth = preempt_count();
    unsigned long flags = vinix_linuxkpi_irq_flags(), now = jiffies;
    if (vinix_linuxkpi_may_sleep()) reasons |= 1;
    if (!depth) reasons |= 2;
    if (timer_pending(timer)) reasons |= 4;
    if (!!(flags & (1UL << 9)) == test->irq_safe) reasons |= 8;
    if (time_before(now, timer->expires)) reasons |= 16;
    if (reasons) {
        test->result = -EIO;
        test->callback_reasons |= reasons;
        test->bad_tick = now;
        test->bad_expires = timer->expires;
        test->bad_irq_flags = flags;
        test->bad_depth = depth;
    }
    if (++test->calls < 4) mod_timer(timer, jiffies + 2);
    else complete(&test->done);
}
struct native_timer_failure {
    unsigned int reasons, callback_reasons, calls, depth;
    unsigned long elapsed, tick, expires, irq_flags;
};
struct native_timer_worker {
    struct task_struct *task;
    int result;
    struct native_timer_failure failures[12];
};
static void *native_timer_worker(void *argument)
{
    struct native_timer_worker *worker = argument;
    worker->task = get_task_struct(current);
    for (unsigned int round = 0; round < 12; round++) {
        struct native_timer_test test = { .irq_safe = !!(round & 1) };
        init_completion(&test.done);
        timer_setup_on_stack(&test.timer, native_timer_callback, test.irq_safe ? TIMER_IRQSAFE : 0);
        unsigned int reasons = 0;
        unsigned long started = jiffies;
        mod_timer(&test.timer, jiffies + 2);
        /* Native scheduler/TCG latency does not guarantee four callback
         * dispatches within 100 ms. Keep a finite watchdog while checking
         * callback ordering, context, rearm and shutdown independently. */
        if (!wait_for_completion_timeout(&test.done, 500)) reasons |= 1;
        timer_shutdown_sync(&test.timer);
        unsigned long elapsed = jiffies - started;
        if (test.calls != 4) reasons |= 2;
        if (test.result) reasons |= 4;
        if (timer_pending(&test.timer)) reasons |= 8;
        mod_timer(&test.timer, jiffies + 1);
        if (timer_pending(&test.timer)) reasons |= 16;
        destroy_timer_on_stack(&test.timer);
        if (!vinix_linuxkpi_may_sleep()) reasons |= 32;
        if (reasons) {
            worker->result = -EIO;
            worker->failures[round] = (struct native_timer_failure){
                .reasons = reasons, .callback_reasons = test.callback_reasons,
                .calls = test.calls, .elapsed = elapsed, .depth = test.bad_depth,
                .tick = test.bad_tick, .expires = test.bad_expires, .irq_flags = test.bad_irq_flags,
            };
        }
    }
    pthread_exit(NULL);
    return NULL;
}
int vinix_linuxkpi_timer_native_selftest(void)
{
    extern int kprintf(const char *, ...);
    struct native_timer_worker workers[4] = {0};
    pthread_t threads[4];
    int result = 0;
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++)
        BUG_ON(pthread_create(&threads[i], NULL, native_timer_worker, &workers[i]));
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++) {
        BUG_ON(pthread_join(threads[i], NULL));
        if (workers[i].result) result = -EIO;
        for (unsigned int round = 0; round < ARRAY_SIZE(workers[i].failures); round++) {
            struct native_timer_failure *failure = &workers[i].failures[round];
            if (!failure->reasons) continue;
            /* Formatting happens on the controller, after synchronous timer
             * shutdown and join, with no timer lock or callback pin held. */
            kprintf("linuxkpi: timer test worker=%u round=%u reasons=0x%x callback=0x%x calls=%u elapsed=%lu ticks depth=%u tick=%lu expires=%lu irq=0x%lx\n",
                    i, round, failure->reasons, failure->callback_reasons, failure->calls,
                    failure->elapsed, failure->depth, failure->tick, failure->expires, failure->irq_flags);
        }
        while (__atomic_load_n(&workers[i].task->__state, __ATOMIC_ACQUIRE) != TASK_DEAD) cond_resched();
        put_task_struct(workers[i].task);
    }
    size_t active = vinix_linuxkpi_timer_active();
    if (active) {
        kprintf("linuxkpi: timer test retained %zu active timers\n", active);
        result = -EIO;
    }
    return result;
}
#endif
#endif
