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

/* Failure-only diagnostics run in test process context. Keep normal callback
 * and reader paths silent so diagnostics do not change their scheduling. */
extern int kprintf(const char *, ...) __attribute__((format(printf, 1, 2)));
#define NATIVE_SRCU_FAILURE(stage, format, ...) \
    kprintf("linuxkpi: SRCU self-test " stage " failed at line %u: " format "\n", \
            (unsigned int)__LINE__, ##__VA_ARGS__)
#define NATIVE_SRCU_THREAD_FAILURE(test) do { \
    if (!(test)->result) (test)->failure_line = __LINE__; \
    (test)->result = -EIO; \
} while (0)

enum native_srcu_operation { NATIVE_SRCU_READER, NATIVE_SRCU_SYNC, NATIVE_SRCU_BARRIER };
struct native_srcu_thread {
    struct srcu_struct *ssp;
    struct task_struct *task;
    pthread_t thread;
    struct completion entered, release_one, one_done, release, done;
    enum native_srcu_operation operation;
    int idx[2], result;
    unsigned int failure_line;
    bool nested, initialized, started;
};

static void *native_srcu_thread(void *argument)
{
    struct native_srcu_thread *test = argument;
    test->task = get_task_struct(current);
    if (test->operation == NATIVE_SRCU_READER) {
        if (vinix_linuxkpi_worker_bind(0)) NATIVE_SRCU_THREAD_FAILURE(test);
        test->idx[0] = srcu_read_lock(test->ssp);
        if (test->nested) test->idx[1] = srcu_read_lock(test->ssp);
        complete(&test->entered);
        cond_resched();
        msleep(1);
        if (!vinix_linuxkpi_may_sleep() || vinix_linuxkpi_cpu_id() != 0)
            NATIVE_SRCU_THREAD_FAILURE(test);
        unsigned int target = vinix_linuxkpi_percpu_count() > 1 ? 1 : 0;
        if (vinix_linuxkpi_worker_bind(target)) NATIVE_SRCU_THREAD_FAILURE(test);
        if (test->nested) {
            wait_for_completion(&test->release_one);
            srcu_read_unlock(test->ssp, test->idx[1]);
            complete(&test->one_done);
        }
        wait_for_completion(&test->release);
        cond_resched();
        msleep(1);
        if (vinix_linuxkpi_cpu_id() != target) NATIVE_SRCU_THREAD_FAILURE(test);
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
    if (test->result)
        NATIVE_SRCU_FAILURE("reader thread", "operation=%u error=%d condition_line=%u idx=%d/%d",
                            test->operation, test->result, test->failure_line,
                            test->idx[0], test->idx[1]);
    put_task_struct(test->task);
    test->started = false;
    return test->result;
}

static int native_srcu_flip(struct srcu_struct *ssp, unsigned int old)
{
    unsigned long deadline = jiffies + 500;
    while ((READ_ONCE(ssp->srcu_idx) & 1) == old) {
        if (time_after_eq(jiffies, deadline)) {
            NATIVE_SRCU_FAILURE("bank flip", "old=%u idx=%u gp=%lu needed=%lu ticks=%lu",
                                old, READ_ONCE(ssp->srcu_idx),
                                READ_ONCE(ssp->srcu_sup->srcu_gp_seq),
                                READ_ONCE(ssp->srcu_sup->srcu_gp_seq_needed), jiffies);
            return -EIO;
        }
        msleep(1);
    }
    return 0;
}

static int native_srcu_poll(struct srcu_struct *ssp, unsigned long cookie)
{
    unsigned long deadline = jiffies + 500;
    while (!poll_state_synchronize_srcu(ssp, cookie)) {
        if (time_after_eq(jiffies, deadline)) {
            NATIVE_SRCU_FAILURE("cookie poll", "cookie=%lu idx=%u gp=%lu needed=%lu ticks=%lu",
                                cookie, READ_ONCE(ssp->srcu_idx),
                                READ_ONCE(ssp->srcu_sup->srcu_gp_seq),
                                READ_ONCE(ssp->srcu_sup->srcu_gp_seq_needed), jiffies);
            return -EIO;
        }
        msleep(1);
    }
    return 0;
}

static int native_srcu_readers(void)
{
    struct srcu_struct ssp = {0};
    struct native_srcu_thread old = {0}, late = {0}, sync = {0}, barrier = {0};
    int result = init_srcu_struct(&ssp);
    if (result) {
        NATIVE_SRCU_FAILURE("reader domain init", "error=%d", result);
        return result;
    }
    if (native_srcu_start(&old, &ssp, NATIVE_SRCU_READER, true) ||
        !wait_for_completion_timeout(&old.entered, 500)) {
        NATIVE_SRCU_FAILURE("old reader entry", "started=%u", old.started);
        result = -EIO; goto out;
    }
    unsigned int bank = old.idx[0];
    unsigned int target = vinix_linuxkpi_percpu_count() > 1 ? 1 : 0;
    struct srcu_data *source = per_cpu_ptr(ssp.sda, 0);
    struct srcu_data *destination = per_cpu_ptr(ssp.sda, target);
    if (bank > 1 || old.idx[1] != (int)bank ||
        atomic_long_read(&source->srcu_lock_count[bank]) != 2 ||
        atomic_long_read(&destination->srcu_unlock_count[bank])) {
        NATIVE_SRCU_FAILURE("nested reader counts", "bank=%u nested=%d locks=%ld unlocks=%ld",
                            bank, old.idx[1],
                            bank <= 1 ? atomic_long_read(&source->srcu_lock_count[bank]) : -1L,
                            bank <= 1 ? atomic_long_read(&destination->srcu_unlock_count[bank]) : -1L);
        result = -EIO; goto out;
    }
    /* An empty callback barrier cannot create a reader grace period. */
    if (native_srcu_start(&barrier, &ssp, NATIVE_SRCU_BARRIER, false) ||
        !wait_for_completion_timeout(&barrier.done, 500)) {
        NATIVE_SRCU_FAILURE("empty callback barrier", "started=%u done=%u", barrier.started,
                            completion_done(&barrier.done));
        result = -EIO; goto out;
    }
    if (native_srcu_join(&barrier)) result = -EIO;
    if (native_srcu_start(&sync, &ssp, NATIVE_SRCU_SYNC, false) ||
        native_srcu_flip(&ssp, bank)) {
        NATIVE_SRCU_FAILURE("first GP start", "started=%u", sync.started);
        result = -EIO; goto out;
    }
    if (native_srcu_start(&late, &ssp, NATIVE_SRCU_READER, false) ||
        !wait_for_completion_timeout(&late.entered, 500)) {
        NATIVE_SRCU_FAILURE("late reader entry", "started=%u", late.started);
        result = -EIO; goto out;
    }
    if (late.idx[0] == (int)bank || completion_done(&sync.done)) {
        NATIVE_SRCU_FAILURE("late reader separation", "old_bank=%u late_bank=%d sync_done=%u",
                            bank, late.idx[0], completion_done(&sync.done));
        result = -EIO;
    }
    unsigned long during = get_state_synchronize_srcu(&ssp);
    complete(&old.release_one);
    if (!wait_for_completion_timeout(&old.one_done, 500) || completion_done(&sync.done) ||
        atomic_long_read(&destination->srcu_unlock_count[bank]) != 1) {
        NATIVE_SRCU_FAILURE("one nested unlock", "one_done=%u sync_done=%u unlocks=%ld",
                            completion_done(&old.one_done), completion_done(&sync.done),
                            atomic_long_read(&destination->srcu_unlock_count[bank]));
        result = -EIO;
    }
    complete(&old.release);
    if (!wait_for_completion_timeout(&sync.done, 500)) {
        NATIVE_SRCU_FAILURE("first GP completion", "gp=%lu needed=%lu", READ_ONCE(ssp.srcu_sup->srcu_gp_seq),
                            READ_ONCE(ssp.srcu_sup->srcu_gp_seq_needed));
        result = -EIO; goto out;
    }
    if (completion_done(&late.done) || poll_state_synchronize_srcu(&ssp, during)) {
        NATIVE_SRCU_FAILURE("first GP boundary", "late_done=%u cookie=%lu gp=%lu",
                            completion_done(&late.done), during, READ_ONCE(ssp.srcu_sup->srcu_gp_seq));
        result = -EIO;
    }
    if (native_srcu_join(&old)) result = -EIO;
    if (native_srcu_join(&sync)) result = -EIO;
    if (atomic_long_read(&source->srcu_lock_count[bank]) != 2 ||
        atomic_long_read(&destination->srcu_unlock_count[bank]) != 2) {
        NATIVE_SRCU_FAILURE("migrated reader counts", "locks=%ld unlocks=%ld",
                            atomic_long_read(&source->srcu_lock_count[bank]),
                            atomic_long_read(&destination->srcu_unlock_count[bank]));
        result = -EIO;
    }
    /* A cookie captured in an already-running GP needs the next full GP.
     * The late reader blocks that one, but did not block the first one. */
    unsigned long next = start_poll_synchronize_srcu(&ssp);
    if (native_srcu_flip(&ssp, late.idx[0]) || poll_state_synchronize_srcu(&ssp, during) ||
        poll_state_synchronize_srcu(&ssp, next)) {
        NATIVE_SRCU_FAILURE("second GP boundary", "during=%lu next=%lu gp=%lu late_bank=%d",
                            during, next, READ_ONCE(ssp.srcu_sup->srcu_gp_seq), late.idx[0]);
        result = -EIO;
    }
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
    unsigned int failure_line;
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
        NATIVE_SRCU_THREAD_FAILURE(test);
    kfree(callback); /* Dispatcher must never reread this head after return. */
}

struct native_srcu_barrier_probe {
    struct rcu_head head;
    struct srcu_struct *ssp;
    struct task_struct *task;
    pthread_t thread;
    struct completion ready;
    unsigned int cpu;
    unsigned int waiter_cpu, waiter_failure_line, callback_failure_line;
    unsigned int task_state_at_failure;
    bool task_queued_at_failure;
    bool entered, gp_done, barrier_started, barrier_done, callback_done, observed_park;
    int result, route_error;
};

static void *native_srcu_barrier_waiter(void *argument)
{
    struct native_srcu_barrier_probe *test = argument;
    test->task = get_task_struct(current);
    test->waiter_cpu = vinix_linuxkpi_cpu_id();
    complete(&test->ready);
    unsigned long deadline = jiffies + 500;
    while (!__atomic_load_n(&test->entered, __ATOMIC_ACQUIRE)) {
        if (time_after_eq(jiffies, deadline)) {
            test->waiter_failure_line = __LINE__;
            __atomic_store_n(&test->result, -EIO, __ATOMIC_RELEASE);
            goto out;
        }
        cond_resched();
    }
    if (vinix_linuxkpi_worker_bind((test->cpu + 1) % vinix_linuxkpi_percpu_count())) {
        test->waiter_failure_line = __LINE__;
        __atomic_store_n(&test->result, -EIO, __ATOMIC_RELEASE);
    }
    test->waiter_cpu = vinix_linuxkpi_cpu_id();
    /* A separate full GP must progress while the callback dispatcher is
     * held. This also warms the private queue's second worker deterministically. */
    unsigned long cookie = start_poll_synchronize_srcu(test->ssp);
    if (native_srcu_poll(test->ssp, cookie)) {
        test->waiter_failure_line = __LINE__;
        __atomic_store_n(&test->result, -EIO, __ATOMIC_RELEASE);
    } else __atomic_store_n(&test->gp_done, true, __ATOMIC_RELEASE);
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
    /* This callback pins its CPU while observing a separate process-context
     * barrier waiter. Route the retained waiter before publishing entry: it
     * may have been preempted on this very CPU and cannot run its own bind
     * until this callback returns. The controller acquired ready before
     * submission and retains task through join and callback completion. */
    test->route_error = vinix_linuxkpi_test_worker_route(test->task->vinix_thread,
                        (test->cpu + 1) % vinix_linuxkpi_percpu_count());
    if (test->route_error) {
        test->callback_failure_line = __LINE__;
        __atomic_store_n(&test->result, -EIO, __ATOMIC_RELEASE);
    }
    __atomic_store_n(&test->entered, true, __ATOMIC_RELEASE);
    if (test->route_error) {
        __atomic_store_n(&test->callback_done, true, __ATOMIC_RELEASE);
        return;
    }
    unsigned long deadline = jiffies + 500;
    for (;;) {
        if (__atomic_load_n(&test->barrier_done, __ATOMIC_ACQUIRE) ||
            time_after_eq(jiffies, deadline)) {
            test->callback_failure_line = __LINE__;
            test->task_state_at_failure = __atomic_load_n(&test->task->__state, __ATOMIC_ACQUIRE);
            test->task_queued_at_failure = vinix_linuxkpi_task_queued(test->task->vinix_thread);
            __atomic_store_n(&test->result, -EIO, __ATOMIC_RELEASE);
            break;
        }
        if (__atomic_load_n(&test->barrier_started, __ATOMIC_ACQUIRE) &&
            __atomic_load_n(&test->task->__state, __ATOMIC_ACQUIRE) == TASK_UNINTERRUPTIBLE &&
            !vinix_linuxkpi_task_queued(test->task->vinix_thread)) {
            if (!__atomic_load_n(&test->gp_done, __ATOMIC_ACQUIRE)) {
                test->callback_failure_line = __LINE__;
                __atomic_store_n(&test->result, -EIO, __ATOMIC_RELEASE);
            }
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
    if (result) {
        NATIVE_SRCU_FAILURE("callback domain init", "error=%d", result);
        return result;
    }
    unsigned int submitted = 0;
    bool probe_started = false, probe_submitted = false;
    for (unsigned int i = 0; i < ARRAY_SIZE(callbacks); i++) {
        callbacks[i] = kzalloc(sizeof(*callbacks[i]), GFP_KERNEL);
        if (!callbacks[i]) {
            NATIVE_SRCU_FAILURE("callback allocation", "index=%u", i);
            result = -ENOMEM; goto out;
        }
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
    if (test.count != ARRAY_SIZE(callbacks) || test.result) {
        NATIVE_SRCU_FAILURE("callback sequence", "count=%u error=%d condition_line=%u",
                            test.count, test.result, test.failure_line);
        result = -EIO;
    }
    if (vinix_linuxkpi_percpu_count() > 1) {
        init_completion(&probe.ready);
        if (pthread_create(&probe.thread, NULL, native_srcu_barrier_waiter, &probe)) {
            NATIVE_SRCU_FAILURE("barrier waiter creation", "error=%d", -ENOMEM);
            result = -ENOMEM;
            goto out;
        }
        probe_started = true;
        if (!wait_for_completion_timeout(&probe.ready, 500)) {
            NATIVE_SRCU_FAILURE("barrier waiter entry", "started=%u", probe_started);
            result = -EIO; goto out;
        }
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
        if (!probe.observed_park || __atomic_load_n(&probe.result, __ATOMIC_ACQUIRE)) {
            NATIVE_SRCU_FAILURE("callback barrier park", "park=%u error=%d route_error=%d callback_line=%u waiter_line=%u callback_cpu=%u waiter_cpu=%u state=%u queued=%u entered=%u gp_done=%u started=%u done=%u callback_done=%u",
                                probe.observed_park, __atomic_load_n(&probe.result, __ATOMIC_ACQUIRE),
                                probe.route_error,
                                probe.callback_failure_line, probe.waiter_failure_line,
                                probe.cpu, probe.waiter_cpu, probe.task_state_at_failure,
                                probe.task_queued_at_failure, probe.entered, probe.gp_done,
                                probe.barrier_started, probe.barrier_done, probe.callback_done);
            result = -EIO;
        }
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
    if (result) {
        NATIVE_SRCU_FAILURE("work caller domain init", "error=%d", result);
        return result;
    }
    struct workqueue_struct *wq = alloc_workqueue("vinix-srcu-caller", 0, 1);
    if (!wq) {
        NATIVE_SRCU_FAILURE("work caller queue allocation", "error=%d", -ENOMEM);
        cleanup_srcu_struct(&ssp); return -ENOMEM;
    }
    struct native_srcu_work_test test = { .ssp = &ssp };
    INIT_WORK_ONSTACK(&test.work, native_srcu_work_callback);
    init_completion(&test.done);
    BUG_ON(!queue_work_on(0, wq, &test.work));
    if (!wait_for_completion_timeout(&test.done, 500)) {
        NATIVE_SRCU_FAILURE("work caller completion", "gp=%lu needed=%lu",
                            READ_ONCE(ssp.srcu_sup->srcu_gp_seq),
                            READ_ONCE(ssp.srcu_sup->srcu_gp_seq_needed));
        result = -EIO;
    }
    destroy_workqueue(wq); /* Keep the stack record alive through callback return. */
    if (test.result) {
        NATIVE_SRCU_FAILURE("work caller context", "error=%d", test.result);
        result = -EIO;
    }
    cleanup_srcu_struct(&ssp);
    return result;
}

int vinix_linuxkpi_srcu_native_selftest(void)
{
    int result = native_srcu_readers();
    if (result) NATIVE_SRCU_FAILURE("reader batch", "error=%d", result);
    int error = native_srcu_callbacks();
    if (error) {
        NATIVE_SRCU_FAILURE("callback batch", "error=%d", error);
        result = -EIO;
    }
    error = native_srcu_work_progress();
    if (error) {
        NATIVE_SRCU_FAILURE("work caller batch", "error=%d", error);
        result = -EIO;
    }
    /* Fail usage allocation and then per-CPU allocation independently. A
     * partially initialized domain is discarded without calling cleanup. */
    for (unsigned int repeat = 0; repeat < 20; repeat++) {
        for (int stage = 0; stage < 2; stage++) {
            struct srcu_struct ssp = {0};
            vinix_linuxkpi_test_alloc_oom(stage);
            int error = init_srcu_struct(&ssp);
            vinix_linuxkpi_test_alloc_oom(-1);
            if (error != -ENOMEM) {
                NATIVE_SRCU_FAILURE("constructor fault", "repeat=%u stage=%d error=%d",
                                    repeat, stage, error);
                result = -EIO;
            }
            if (error && (ssp.sda || ssp.srcu_sup)) {
                NATIVE_SRCU_FAILURE("constructor rollback", "repeat=%u stage=%d sda_present=%u usage_present=%u",
                                    repeat, stage, !!ssp.sda, !!ssp.srcu_sup);
                result = -EIO;
            }
            if (!error) cleanup_srcu_struct(&ssp);
        }
    }
    /* Reinitialization never reuses freed per-CPU storage or callback work. */
    for (unsigned int repeat = 0; repeat < 8; repeat++) {
        struct srcu_struct ssp = {0};
        if (init_srcu_struct(&ssp)) {
            NATIVE_SRCU_FAILURE("domain reinitialization", "repeat=%u", repeat);
            return -ENOMEM;
        }
        int index = srcu_read_lock(&ssp);
        msleep(1);
        srcu_read_unlock(&ssp, index);
        synchronize_srcu_expedited(&ssp);
        unsigned long cookie = start_poll_synchronize_srcu(&ssp);
        if (native_srcu_poll(&ssp, cookie)) {
            NATIVE_SRCU_FAILURE("reinitialized domain poll", "repeat=%u cookie=%lu", repeat, cookie);
            result = -EIO;
        }
        srcu_barrier(&ssp);
        cleanup_srcu_struct(&ssp);
    }
    return result;
}
#endif
