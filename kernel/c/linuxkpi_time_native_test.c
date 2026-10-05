/* SPDX-License-Identifier: GPL-2.0-only */
/* Time conversion helpers adapted from Linux kernel/time/time.c.
 * Copyright (C) 1991, 1992 Linus Torvalds. */
#ifdef VINIX_LINUXKPI
#include <linux/sched.h>
#include <linux/sched/signal.h>
#include <linux/spinlock.h>
#include <linux/list.h>
#include <linux/ktime.h>
#include <linux/delay.h>

/* Independent native fixtures retained from the C implementation. */
#ifndef VINIX_LINUXKPI_HOST_TEST
#include <pthread.h>
#include <linux/sched/task.h>
#include <linux/completion.h>
void vinix_linuxkpi_test_task_signal(void *thread, u64 pending);

struct native_time_worker {
    struct task_struct *task;
    int result;
    struct native_time_failure {
        unsigned int reasons;
        unsigned long elapsed;
        long timeout, queue, simple, completion, completed, interrupted, killable;
    } failures[8];
};

/* Native fixtures retain the borrowed task through this locked pointer-only
 * inspection. Permanent services may legitimately be sleeping at the same
 * time; this observer does not inspect their unrelated arm/expiry cycles. */
size_t vinix_linuxkpi_test_task_time_waiters(struct task_struct *task);

static void *native_time_worker(void *argument)
{
    struct native_time_worker *worker = argument;
    worker->task = get_task_struct(current);
    for (unsigned int i = 0; i < 8; i++) {
        struct native_time_failure failure = {0};
        unsigned long start = jiffies;
        failure.timeout = schedule_timeout_uninterruptible(2);
        failure.elapsed = jiffies - start;
        if (failure.timeout) failure.reasons |= 1;
        if (time_before(jiffies, start + 2)) failure.reasons |= 2;
        DECLARE_WAIT_QUEUE_HEAD(queue);
        failure.queue = wait_event_timeout(queue, false, 1);
        if (failure.queue || waitqueue_active(&queue)) failure.reasons |= 4;
        DECLARE_SWAIT_QUEUE_HEAD(simple);
        failure.simple = swait_event_timeout_exclusive(simple, false, 1);
        if (failure.simple || swait_active(&simple)) failure.reasons |= 8;
        DECLARE_COMPLETION_ONSTACK(completion);
        failure.completion = wait_for_completion_timeout(&completion, 1);
        if (failure.completion || swait_active(&completion.wait)) failure.reasons |= 16;
        complete(&completion);
        failure.completed = wait_for_completion_timeout(&completion, 0);
        if (failure.completed != 1) failure.reasons |= 32;
        vinix_linuxkpi_test_task_signal(worker->task->vinix_thread, 1ULL << 14);
        failure.interrupted = wait_for_completion_interruptible_timeout(&completion, 5);
        if (failure.interrupted != -ERESTARTSYS) failure.reasons |= 64;
        /* The native signal enqueue must not finish this killable sleep. */
        failure.killable = schedule_timeout_killable(2);
        if (failure.killable) failure.reasons |= 128;
        vinix_linuxkpi_test_task_signal(worker->task->vinix_thread, 0);
        if (!task_is_running(current)) failure.reasons |= 256;
        if (!vinix_linuxkpi_may_sleep()) failure.reasons |= 512;
        if (failure.reasons) {
            worker->result = -EIO;
            worker->failures[i] = failure;
        }
    }
    pthread_exit(NULL);
    return NULL;
}

int vinix_linuxkpi_time_native_selftest(void)
{
    extern int kprintf(const char *, ...);
    extern bool vinix_linuxkpi_test_thread_reap_ready(void *owner);
    extern bool vinix_linuxkpi_test_reap_quiescent(void);
    struct native_time_worker workers[4] = {0};
    pthread_t threads[4];
    int result = 0;
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++)
        BUG_ON(pthread_create(&threads[i], NULL, native_time_worker, &workers[i]));
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++)
        BUG_ON(pthread_join(threads[i], NULL));
    u64 retirement_started = vinix_linuxkpi_clock_ns();
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++) {
        if (workers[i].result) result = -EIO;
        for (unsigned int round = 0; round < ARRAY_SIZE(workers[i].failures); round++) {
            struct native_time_failure *failure = &workers[i].failures[round];
            if (!failure->reasons) continue;
            /* Diagnostic formatting happens on the controller after join,
             * without a deadline lock or callback pin held. */
            kprintf("linuxkpi: time test worker=%u round=%u reasons=0x%x elapsed=%lu timeout=%ld queue=%ld simple=%ld completion=%ld completed=%ld interrupted=%ld killable=%ld\n",
                    i, round, failure->reasons, failure->elapsed, failure->timeout,
                    failure->queue, failure->simple, failure->completion,
                    failure->completed, failure->interrupted, failure->killable);
        }
        while (__atomic_load_n(&workers[i].task->__state, __ATOMIC_ACQUIRE) != TASK_DEAD) {
            if (vinix_linuxkpi_clock_ns() - retirement_started >= 1000000000ULL) {
                kprintf("linuxkpi: time test worker=%u did not publish TASK_DEAD\n", i);
                BUG();
            }
            cond_resched();
        }
        size_t retained = vinix_linuxkpi_test_task_time_waiters(workers[i].task);
        if (retained) {
            kprintf("linuxkpi: time test worker=%u retained %zu timeout records after join\n", i, retained);
            /* A deadline still owns pointers into this task's stack. Do not
             * release its final pin or let the controller's fixture expire. */
            BUG();
        }
    }
    /* DEAD and join precede the final switch off the exiting task's stacks.
     * Observe every retained worker's off-stack deferred-list handoff before
     * releasing any final pin. A stable free count alone cannot prove it. */
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++)
        while (!vinix_linuxkpi_test_thread_reap_ready(workers[i].task->vinix_thread)) {
            if (vinix_linuxkpi_clock_ns() - retirement_started >= 1000000000ULL) {
                kprintf("linuxkpi: time test worker=%u did not reach off-stack reaper\n", i);
                BUG(); /* Retain all tasks and the enclosing fixture on failure. */
            }
            cond_resched();
        }
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++)
        put_task_struct(workers[i].task); /* Last access; can free the native Thread. */
    /* Another CPU can detach a ready node before this CPU's last-put scan.
     * Wait for its actual free too, without inspecting any released task. */
    while (!vinix_linuxkpi_test_reap_quiescent()) {
        if (vinix_linuxkpi_clock_ns() - retirement_started >= 1000000000ULL) {
            kprintf("linuxkpi: time test deferred frees did not finish\n");
            BUG();
        }
        cond_resched();
    }
    return result;
}
#endif
#endif
