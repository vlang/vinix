/* SPDX-License-Identifier: GPL-2.0-only */
#if defined(VINIX_LINUXKPI) && !defined(VINIX_LINUXKPI_HOST_TEST)
#include <linux/completion.h>
#include <linux/delay.h>
#include <linux/errno.h>
#include <linux/jiffies.h>
#include <linux/percpu.h>
#include <linux/sched.h>
#include <linux/sched/task.h>
#include <linux/slab.h>
#include <linux/srcu.h>
#include <vinix/runtime.h>
#include <pthread.h>

enum native_srcu_operation { NATIVE_SRCU_READER, NATIVE_SRCU_SYNC, NATIVE_SRCU_BARRIER };
struct native_srcu_thread {
    struct srcu_struct *ssp;
    struct task_struct *task;
    pthread_t thread;
    struct completion entered, release_one, one_done, release, done;
    enum native_srcu_operation operation;
    int idx[2], result;
    bool nested, initialized, started;
};

static void *native_srcu_thread(void *argument)
{
    struct native_srcu_thread *test = argument;
    test->task = get_task_struct(current);
    if (test->operation == NATIVE_SRCU_READER) {
        if (vinix_linuxkpi_worker_bind(0)) test->result = -EIO;
        test->idx[0] = srcu_read_lock(test->ssp);
        if (test->nested) test->idx[1] = srcu_read_lock(test->ssp);
        complete(&test->entered);
        cond_resched();
        msleep(1);
        if (!vinix_linuxkpi_may_sleep() || vinix_linuxkpi_cpu_id() != 0)
            test->result = -EIO;
        unsigned int target = vinix_linuxkpi_percpu_count() > 1 ? 1 : 0;
        if (vinix_linuxkpi_worker_bind(target)) test->result = -EIO;
        if (test->nested) {
            wait_for_completion(&test->release_one);
            srcu_read_unlock(test->ssp, test->idx[1]);
            complete(&test->one_done);
        }
        wait_for_completion(&test->release);
        cond_resched();
        msleep(1);
        if (vinix_linuxkpi_cpu_id() != target) test->result = -EIO;
        srcu_read_unlock(test->ssp, test->idx[0]);
    } else {
        complete(&test->entered);
        if (test->operation == NATIVE_SRCU_SYNC) synchronize_srcu(test->ssp);
        else srcu_barrier(test->ssp);
    }
    complete(&test->done);
    pthread_exit(NULL);
    return NULL;
}

static int native_srcu_start(struct native_srcu_thread *test, struct srcu_struct *ssp,
                              enum native_srcu_operation operation, bool nested)
{
    *test = (struct native_srcu_thread){ .ssp = ssp, .operation = operation, .nested = nested };
    init_completion(&test->entered);
    init_completion(&test->release_one);
    init_completion(&test->one_done);
    init_completion(&test->release);
    init_completion(&test->done);
    test->initialized = true;
    if (pthread_create(&test->thread, NULL, native_srcu_thread, test)) return -ENOMEM;
    test->started = true;
    return 0;
}

static int native_srcu_join(struct native_srcu_thread *test)
{
    if (!test->started) return 0;
    BUG_ON(pthread_join(test->thread, NULL));
    while (__atomic_load_n(&test->task->__state, __ATOMIC_ACQUIRE) != TASK_DEAD) cond_resched();
    put_task_struct(test->task);
    test->started = false;
    return test->result;
}

static int native_srcu_flip(struct srcu_struct *ssp, unsigned int old)
{
    unsigned long deadline = jiffies + 500;
    while ((READ_ONCE(ssp->srcu_idx) & 1) == old) {
        if (time_after_eq(jiffies, deadline)) return -EIO;
        msleep(1);
    }
    return 0;
}

static int native_srcu_poll(struct srcu_struct *ssp, unsigned long cookie)
{
    unsigned long deadline = jiffies + 500;
    while (!poll_state_synchronize_srcu(ssp, cookie)) {
        if (time_after_eq(jiffies, deadline)) return -EIO;
        msleep(1);
    }
    return 0;
}

static int native_srcu_readers(void)
{
    struct srcu_struct ssp = {0};
    struct native_srcu_thread old = {0}, late = {0}, sync = {0}, barrier = {0};
    int result = init_srcu_struct(&ssp);
    if (result) return result;
    if (native_srcu_start(&old, &ssp, NATIVE_SRCU_READER, true) ||
        !wait_for_completion_timeout(&old.entered, 500)) { result = -EIO; goto out; }
    unsigned int bank = old.idx[0];
    unsigned int target = vinix_linuxkpi_percpu_count() > 1 ? 1 : 0;
    struct srcu_data *source = per_cpu_ptr(ssp.sda, 0);
    struct srcu_data *destination = per_cpu_ptr(ssp.sda, target);
    if (bank > 1 || old.idx[1] != (int)bank ||
        atomic_long_read(&source->srcu_lock_count[bank]) != 2 ||
        atomic_long_read(&destination->srcu_unlock_count[bank])) { result = -EIO; goto out; }
    /* An empty callback barrier cannot create a reader grace period. */
    if (native_srcu_start(&barrier, &ssp, NATIVE_SRCU_BARRIER, false) ||
        !wait_for_completion_timeout(&barrier.done, 500)) { result = -EIO; goto out; }
    if (native_srcu_join(&barrier)) result = -EIO;
    if (native_srcu_start(&sync, &ssp, NATIVE_SRCU_SYNC, false) ||
        native_srcu_flip(&ssp, bank)) { result = -EIO; goto out; }
    if (native_srcu_start(&late, &ssp, NATIVE_SRCU_READER, false) ||
        !wait_for_completion_timeout(&late.entered, 500)) { result = -EIO; goto out; }
    if (late.idx[0] == (int)bank || completion_done(&sync.done)) result = -EIO;
    unsigned long during = get_state_synchronize_srcu(&ssp);
    complete(&old.release_one);
    if (!wait_for_completion_timeout(&old.one_done, 500) || completion_done(&sync.done) ||
        atomic_long_read(&destination->srcu_unlock_count[bank]) != 1) result = -EIO;
    complete(&old.release);
    if (!wait_for_completion_timeout(&sync.done, 500)) { result = -EIO; goto out; }
    if (completion_done(&late.done) || poll_state_synchronize_srcu(&ssp, during)) result = -EIO;
    if (native_srcu_join(&old)) result = -EIO;
    if (native_srcu_join(&sync)) result = -EIO;
    if (atomic_long_read(&source->srcu_lock_count[bank]) != 2 ||
        atomic_long_read(&destination->srcu_unlock_count[bank]) != 2) result = -EIO;
    /* A cookie captured in an already-running GP needs the next full GP.
     * The late reader blocks that one, but did not block the first one. */
    unsigned long next = start_poll_synchronize_srcu(&ssp);
    if (native_srcu_flip(&ssp, late.idx[0]) || poll_state_synchronize_srcu(&ssp, during) ||
        poll_state_synchronize_srcu(&ssp, next)) result = -EIO;
    complete(&late.release);
    if (native_srcu_poll(&ssp, during) || native_srcu_poll(&ssp, next)) result = -EIO;
out:
    /* Every failure path releases both nesting gates before joining waiters. */
    if (old.initialized) {
        complete_all(&old.release_one);
        complete_all(&old.release);
    }
    if (late.initialized) complete_all(&late.release);
    if (native_srcu_join(&old)) result = -EIO;
    if (native_srcu_join(&late)) result = -EIO;
    if (native_srcu_join(&sync)) result = -EIO;
    if (native_srcu_join(&barrier)) result = -EIO;
    srcu_barrier(&ssp);
    cleanup_srcu_struct(&ssp);
    return result;
}

struct native_srcu_callbacks {
    unsigned int count;
    int result;
};
struct native_srcu_callback {
    struct rcu_head head;
    struct native_srcu_callbacks *test;
    unsigned int index;
};

static void native_srcu_free_callback(struct rcu_head *head)
{
    struct native_srcu_callback *callback = container_of(head, struct native_srcu_callback, head);
    struct native_srcu_callbacks *test = callback->test;
    unsigned int index = callback->index;
    if (vinix_linuxkpi_may_sleep() || !vinix_linuxkpi_preempt_count() ||
        !(vinix_linuxkpi_irq_flags() & (1UL << 9)) ||
        __atomic_fetch_add(&test->count, 1, __ATOMIC_ACQ_REL) != index)
        test->result = -EIO;
    kfree(callback); /* Dispatcher must never reread this head after return. */
}

struct native_srcu_barrier_probe {
    struct rcu_head head;
    struct srcu_struct *ssp;
    struct task_struct *task;
    pthread_t thread;
    struct completion ready;
    unsigned int cpu;
    bool entered, gp_done, barrier_started, barrier_done, callback_done, observed_park;
    int result;
};

static void *native_srcu_barrier_waiter(void *argument)
{
    struct native_srcu_barrier_probe *test = argument;
    test->task = get_task_struct(current);
    complete(&test->ready);
    unsigned long deadline = jiffies + 500;
    while (!__atomic_load_n(&test->entered, __ATOMIC_ACQUIRE)) {
        if (time_after_eq(jiffies, deadline)) {
            __atomic_store_n(&test->result, -EIO, __ATOMIC_RELEASE);
            goto out;
        }
        cond_resched();
    }
    if (vinix_linuxkpi_worker_bind((test->cpu + 1) % vinix_linuxkpi_percpu_count()))
        __atomic_store_n(&test->result, -EIO, __ATOMIC_RELEASE);
    /* A separate full GP must progress while the callback dispatcher is
     * held. This also warms the private queue's second worker deterministically. */
    unsigned long cookie = start_poll_synchronize_srcu(test->ssp);
    if (native_srcu_poll(test->ssp, cookie))
        __atomic_store_n(&test->result, -EIO, __ATOMIC_RELEASE);
    else __atomic_store_n(&test->gp_done, true, __ATOMIC_RELEASE);
    __atomic_store_n(&test->barrier_started, true, __ATOMIC_RELEASE);
    srcu_barrier(test->ssp);
out:
    __atomic_store_n(&test->barrier_done, true, __ATOMIC_RELEASE);
    pthread_exit(NULL);
    return NULL;
}

static void native_srcu_barrier_callback(struct rcu_head *head)
{
    struct native_srcu_barrier_probe *test = container_of(head, struct native_srcu_barrier_probe, head);
    test->cpu = vinix_linuxkpi_cpu_id();
    __atomic_store_n(&test->entered, true, __ATOMIC_RELEASE);
    unsigned long deadline = jiffies + 500;
    for (;;) {
        if (__atomic_load_n(&test->barrier_done, __ATOMIC_ACQUIRE) ||
            time_after_eq(jiffies, deadline)) {
            __atomic_store_n(&test->result, -EIO, __ATOMIC_RELEASE);
            break;
        }
        if (__atomic_load_n(&test->barrier_started, __ATOMIC_ACQUIRE) &&
            __atomic_load_n(&test->task->__state, __ATOMIC_ACQUIRE) == TASK_UNINTERRUPTIBLE &&
            !vinix_linuxkpi_task_queued(test->task->vinix_thread)) {
            if (!__atomic_load_n(&test->gp_done, __ATOMIC_ACQUIRE))
                __atomic_store_n(&test->result, -EIO, __ATOMIC_RELEASE);
            test->observed_park = true;
            break;
        }
        vinix_linuxkpi_spin_wait();
    }
    __atomic_store_n(&test->callback_done, true, __ATOMIC_RELEASE);
}

static int native_srcu_callbacks(void)
{
    struct srcu_struct ssp = {0};
    struct native_srcu_callbacks test = {0};
    struct native_srcu_callback *callbacks[16] = {0};
    struct native_srcu_barrier_probe probe = { .ssp = &ssp };
    int result = init_srcu_struct(&ssp);
    if (result) return result;
    unsigned int submitted = 0;
    bool probe_started = false, probe_submitted = false;
    for (unsigned int i = 0; i < ARRAY_SIZE(callbacks); i++) {
        callbacks[i] = kzalloc(sizeof(*callbacks[i]), GFP_KERNEL);
        if (!callbacks[i]) { result = -ENOMEM; goto out; }
        callbacks[i]->test = &test;
        callbacks[i]->index = i;
    }
    /* Both producer contexts must enqueue without allocation or waiting. */
    unsigned long flags = vinix_linuxkpi_irq_save();
    for (; submitted < ARRAY_SIZE(callbacks) / 2; submitted++)
        call_srcu(&ssp, &callbacks[submitted]->head, native_srcu_free_callback);
    vinix_linuxkpi_irq_restore(flags);
    vinix_linuxkpi_preempt_disable();
    for (; submitted < ARRAY_SIZE(callbacks); submitted++)
        call_srcu(&ssp, &callbacks[submitted]->head, native_srcu_free_callback);
    vinix_linuxkpi_preempt_enable();
    srcu_barrier(&ssp);
    if (test.count != ARRAY_SIZE(callbacks) || test.result) result = -EIO;
    if (vinix_linuxkpi_percpu_count() > 1) {
        init_completion(&probe.ready);
        if (pthread_create(&probe.thread, NULL, native_srcu_barrier_waiter, &probe)) {
            result = -ENOMEM;
            goto out;
        }
        probe_started = true;
        if (!wait_for_completion_timeout(&probe.ready, 500)) { result = -EIO; goto out; }
        call_srcu(&ssp, &probe.head, native_srcu_barrier_callback);
        probe_submitted = true;
    }
out:
    /* Submitted objects are owned by self-free callbacks, even on failure. */
    for (unsigned int i = submitted; i < ARRAY_SIZE(callbacks); i++) kfree(callbacks[i]);
    if (probe_started) {
        BUG_ON(pthread_join(probe.thread, NULL));
        /* Even a broken early-return barrier cannot let this test drop the
         * task reference while the callback is inspecting that task. */
        if (probe_submitted)
            while (!__atomic_load_n(&probe.callback_done, __ATOMIC_ACQUIRE)) cond_resched();
        while (__atomic_load_n(&probe.task->__state, __ATOMIC_ACQUIRE) != TASK_DEAD) cond_resched();
        put_task_struct(probe.task);
        if (!probe.observed_park || __atomic_load_n(&probe.result, __ATOMIC_ACQUIRE)) result = -EIO;
    }
    srcu_barrier(&ssp);
    cleanup_srcu_struct(&ssp);
    return result;
}

struct native_srcu_work_test {
    struct work_struct work;
    struct srcu_struct *ssp;
    struct completion done;
    int result;
};

static void native_srcu_work_callback(struct work_struct *work)
{
    struct native_srcu_work_test *test = container_of(work, struct native_srcu_work_test, work);
    if (!vinix_linuxkpi_may_sleep() || current_work() != work) test->result = -EIO;
    synchronize_srcu(test->ssp);
    synchronize_srcu_expedited(test->ssp);
    srcu_barrier(test->ssp);
    complete(&test->done);
}

static int native_srcu_work_progress(void)
{
    struct srcu_struct ssp = {0};
    int result = init_srcu_struct(&ssp);
    if (result) return result;
    struct workqueue_struct *wq = alloc_workqueue("vinix-srcu-caller", 0, 1);
    if (!wq) { cleanup_srcu_struct(&ssp); return -ENOMEM; }
    struct native_srcu_work_test test = { .ssp = &ssp };
    INIT_WORK_ONSTACK(&test.work, native_srcu_work_callback);
    init_completion(&test.done);
    BUG_ON(!queue_work_on(0, wq, &test.work));
    if (!wait_for_completion_timeout(&test.done, 500)) result = -EIO;
    destroy_workqueue(wq); /* Keep the stack record alive through callback return. */
    if (test.result) result = -EIO;
    cleanup_srcu_struct(&ssp);
    return result;
}

int vinix_linuxkpi_srcu_native_selftest(void)
{
    int result = native_srcu_readers();
    if (native_srcu_callbacks()) result = -EIO;
    if (native_srcu_work_progress()) result = -EIO;
    /* Fail usage allocation and then per-CPU allocation independently. A
     * partially initialized domain is discarded without calling cleanup. */
    for (unsigned int repeat = 0; repeat < 20; repeat++) {
        for (int stage = 0; stage < 2; stage++) {
            struct srcu_struct ssp = {0};
            vinix_linuxkpi_test_alloc_oom(stage);
            int error = init_srcu_struct(&ssp);
            vinix_linuxkpi_test_alloc_oom(-1);
            if (error != -ENOMEM) result = -EIO;
            if (error && (ssp.sda || ssp.srcu_sup)) result = -EIO;
            if (!error) cleanup_srcu_struct(&ssp);
        }
    }
    /* Reinitialization never reuses freed per-CPU storage or callback work. */
    for (unsigned int repeat = 0; repeat < 8; repeat++) {
        struct srcu_struct ssp = {0};
        if (init_srcu_struct(&ssp)) return -ENOMEM;
        int index = srcu_read_lock(&ssp);
        msleep(1);
        srcu_read_unlock(&ssp, index);
        synchronize_srcu_expedited(&ssp);
        unsigned long cookie = start_poll_synchronize_srcu(&ssp);
        if (native_srcu_poll(&ssp, cookie)) result = -EIO;
        srcu_barrier(&ssp);
        cleanup_srcu_struct(&ssp);
    }
    return result;
}
#endif
