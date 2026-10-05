/* SPDX-License-Identifier: GPL-2.0-only */
/* Jiffy rounding adapted from Linux kernel/time/timer.c.
 * Copyright (C) 1991, 1992 Linus Torvalds. */
#ifdef VINIX_LINUXKPI
#include <linux/timer.h>
#include <linux/sched.h>
#include <linux/sched/task.h>
#include <linux/completion.h>

/* Independent native fixtures retained from the C implementation. */
#ifndef VINIX_LINUXKPI_HOST_TEST
#include <pthread.h>
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
