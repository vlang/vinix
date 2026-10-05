/* SPDX-License-Identifier: GPL-2.0-only */
/* Wait-queue routines adapted from Linux kernel/sched/wait.c:
 * (C) 2004 Nadia Yvette Chambers, Oracle. The scheduler and mutex backend,
 * stack-lifetime synchronization and native tests are Vinix-specific. */
#ifdef VINIX_LINUXKPI
#include <linux/bug.h>
#include <linux/errno.h>
#include <linux/kernel.h>
#include <linux/sched.h>
#include <linux/sched/signal.h>
#include <linux/mutex.h>
#include <linux/completion.h>
#include <linux/limits.h>

int vinix_linuxkpi_sync_selftest(void)
{
    DEFINE_MUTEX(lock);
    if (!mutex_trylock(&lock) || !mutex_is_locked(&lock) || mutex_trylock(&lock)) return -EIO;
    mutex_unlock(&lock);
    mutex_lock(&lock);
    mutex_unlock(&lock);
    mutex_destroy(&lock);
    DECLARE_WAIT_QUEUE_HEAD(queue);
    DEFINE_WAIT(wait);
    prepare_to_wait(&queue, &wait, TASK_UNINTERRUPTIBLE);
    if (!waitqueue_active(&queue)) return -EIO;
    wake_up(&queue); /* Wake before the task removes itself from the run queue. */
    finish_wait(&queue, &wait);
    if (waitqueue_active(&queue) || !task_is_running(current)) return -EIO;
    DECLARE_SWAIT_QUEUE_HEAD(simple);
    DECLARE_SWAITQUEUE(swait);
    prepare_to_swait_exclusive(&simple, &swait, TASK_UNINTERRUPTIBLE);
    swake_up_one(&simple);
    finish_swait(&simple, &swait);
    if (swait_active(&simple) || !task_is_running(current)) return -EIO;
    DECLARE_COMPLETION_ONSTACK(completion);
    if (try_wait_for_completion(&completion) || completion_done(&completion)) return -EIO;
    complete(&completion);
    complete(&completion);
    wait_for_completion(&completion);
    if (!try_wait_for_completion(&completion) || try_wait_for_completion(&completion)) return -EIO;
    complete_all(&completion);
    wait_for_completion(&completion);
    if (!try_wait_for_completion(&completion) || completion.done != UINT_MAX) return -EIO;
    reinit_completion(&completion);
    return completion_done(&completion) ? -EIO : 0;
}

#ifndef VINIX_LINUXKPI_HOST_TEST
#include <pthread.h>
#include <linux/sched/task.h>

struct native_sync_test {
    struct mutex lock;
    struct wait_queue_head queue;
    struct swait_queue_head simple;
    struct completion ready, stage, release;
    unsigned int counter, go, simple_go, payload;
};
struct native_sync_worker {
    struct native_sync_test *test;
    struct task_struct *task;
    int result;
};

static void *native_sync_worker(void *argument)
{
    struct native_sync_worker *worker = argument;
    struct native_sync_test *test = worker->test;
    worker->task = get_task_struct(current); /* Controller releases after exit. */
    for (unsigned int i = 0; i < 32; i++) {
        mutex_lock(&test->lock);
        unsigned int previous = test->counter;
        cond_resched(); /* Contenders really park while the owner is yielded. */
        test->counter = previous + 1;
        mutex_unlock(&test->lock);
    }
    complete(&test->ready);
    wait_event(test->queue, __atomic_load_n(&test->go, __ATOMIC_ACQUIRE));
    if (test->payload != 0x1234) worker->result = -EIO;
    complete(&test->stage);
    swait_event_exclusive(test->simple, __atomic_load_n(&test->simple_go, __ATOMIC_ACQUIRE));
    complete(&test->stage);
    wait_for_completion(&test->release);
    if (!task_is_running(current) || !vinix_linuxkpi_may_sleep()) worker->result = -EIO;
    pthread_exit(NULL);
    return NULL;
}

static unsigned int native_queue_count(struct list_head *head)
{
    unsigned int result = 0;
    struct list_head *entry;
    list_for_each(entry, head) result++;
    return result;
}

int vinix_linuxkpi_sync_native_selftest(void)
{
    struct native_sync_test test = {0};
    mutex_init(&test.lock);
    init_waitqueue_head(&test.queue);
    init_swait_queue_head(&test.simple);
    init_completion(&test.ready);
    init_completion(&test.stage);
    init_completion(&test.release);
    struct native_sync_worker workers[4];
    pthread_t threads[4];
    int result = 0;
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++) {
        workers[i] = (struct native_sync_worker){ .test = &test };
        BUG_ON(pthread_create(&threads[i], NULL, native_sync_worker, &workers[i]));
    }
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++) wait_for_completion(&test.ready);
    if (test.counter != ARRAY_SIZE(workers) * 32) result = -EIO;
    for (;;) {
        unsigned long flags;
        spin_lock_irqsave(&test.queue.lock, flags);
        unsigned int count = native_queue_count(&test.queue.head);
        spin_unlock_irqrestore(&test.queue.lock, flags);
        if (count == ARRAY_SIZE(workers)) break;
        cond_resched();
    }
    test.payload = 0x1234;
    __atomic_store_n(&test.go, 1, __ATOMIC_RELEASE);
    wake_up_all(&test.queue);
    for (;;) {
        unsigned long flags;
        raw_spin_lock_irqsave(&test.simple.lock, flags);
        unsigned int count = native_queue_count(&test.simple.task_list);
        raw_spin_unlock_irqrestore(&test.simple.lock, flags);
        if (count == ARRAY_SIZE(workers)) break;
        cond_resched();
    }
    __atomic_store_n(&test.simple_go, 1, __ATOMIC_RELEASE);
    swake_up_all(&test.simple);
    for (unsigned int i = 0; i < ARRAY_SIZE(workers) * 2; i++) wait_for_completion(&test.stage);
    for (;;) {
        unsigned long flags;
        raw_spin_lock_irqsave(&test.release.wait.lock, flags);
        unsigned int count = native_queue_count(&test.release.wait.task_list);
        raw_spin_unlock_irqrestore(&test.release.wait.lock, flags);
        if (count == ARRAY_SIZE(workers)) break;
        cond_resched();
    }
    complete_all(&test.release);
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++) {
        BUG_ON(pthread_join(threads[i], NULL));
        if (workers[i].result) result = -EIO;
        while (__atomic_load_n(&workers[i].task->__state, __ATOMIC_ACQUIRE) != TASK_DEAD) cond_resched();
        put_task_struct(workers[i].task); /* Last access; native owner can be freed. */
    }
    if (waitqueue_active(&test.queue) || swait_active(&test.simple) ||
        swait_active(&test.ready.wait) || swait_active(&test.stage.wait) ||
        swait_active(&test.release.wait) || test.stage.done || test.ready.done) result = -EIO;
    mutex_destroy(&test.lock);
    return result;
}
#endif
#endif
