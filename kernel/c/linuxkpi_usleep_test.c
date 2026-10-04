/* SPDX-License-Identifier: GPL-2.0-only */
#if defined(VINIX_LINUXKPI) && !defined(VINIX_LINUXKPI_HOST_TEST)
#include <linux/completion.h>
#include <linux/delay.h>
#include <linux/errno.h>
#include <linux/jiffies.h>
#include <linux/sched.h>
#include <linux/sched/task.h>
#include <vinix/runtime.h>
#include <pthread.h>

/* These observers require the fixture's retained task until their last call.
 * An empty deferred list alone cannot prove a detached free has finished. */
size_t vinix_linuxkpi_test_task_time_waiters(struct task_struct *task);
bool vinix_linuxkpi_test_thread_reap_ready(void *owner);
bool vinix_linuxkpi_test_reap_quiescent(void);
void vinix_linuxkpi_test_task_signal(void *owner, u64 pending);
extern int kprintf(const char *, ...);

#define NATIVE_USLEEP_LONG_US 50000UL
#define NATIVE_USLEEP_LONG_NS (NATIVE_USLEEP_LONG_US * 1000ULL)

struct native_usleep_worker {
    struct task_struct *task;
    pthread_t thread;
    struct completion entered, go, series_done, long_go, long_started;
    struct completion long_done, release, done;
    u64 long_start, long_elapsed, failed_elapsed;
    unsigned long failed_min;
    unsigned int cpu, state, kind, failed_case, reasons;
    unsigned int early_wakes, signal_sent, signal_reparked;
    bool initialized, started, cancel;
};

static void native_usleep_call(struct native_usleep_worker *worker,
                               unsigned long min, unsigned long max)
{
    if (worker->kind == 0) usleep_range(min, max);
    else if (worker->kind == 1) usleep_idle_range(min, max);
    else usleep_range_state(min, max, worker->state);
}

static void native_usleep_check(struct native_usleep_worker *worker, unsigned int index,
                                unsigned long min, u64 elapsed,
                                unsigned long flags, unsigned int depth)
{
    unsigned int reasons = 0;
    if (elapsed < min * 1000ULL) reasons |= 1;
    if (!task_is_running(current)) reasons |= 2;
    if (!vinix_linuxkpi_may_sleep() || vinix_linuxkpi_irq_flags() != flags ||
        vinix_linuxkpi_preempt_count() != depth) reasons |= 4;
    if (vinix_linuxkpi_cpu_id() != worker->cpu) reasons |= 8;
    if (current->in_iowait) reasons |= 16;
    if (reasons && !worker->reasons) {
        worker->failed_case = index;
        worker->failed_min = min;
        worker->failed_elapsed = elapsed;
    }
    worker->reasons |= reasons;
}

static void *native_usleep_worker(void *argument)
{
    struct native_usleep_worker *worker = argument;
    __atomic_store_n(&worker->task, get_task_struct(current), __ATOMIC_RELEASE);
    if (vinix_linuxkpi_worker_bind(worker->cpu)) worker->reasons |= 32;
    complete(&worker->entered);
    wait_for_completion(&worker->go);
    if (__atomic_load_n(&worker->cancel, __ATOMIC_ACQUIRE)) goto out;

    static const unsigned long ranges[][2] = {
        { 0, 0 }, { 0, 500 }, { 1, 1 }, { 100, 250 },
        { 400, 500 }, { 1000, 2000 }, { 3000, 4000 },
    };
    /* Every range must work even when this caller's next page allocation
     * fails. Constructors are tested separately on the controlling thread. */
    vinix_linuxkpi_test_alloc_oom(0);
    for (unsigned int round = 0; round < 4; round++) {
        for (unsigned int i = 0; i < ARRAY_SIZE(ranges); i++) {
            if (__atomic_load_n(&worker->cancel, __ATOMIC_ACQUIRE)) goto out;
            unsigned long flags = vinix_linuxkpi_irq_flags();
            unsigned int depth = vinix_linuxkpi_preempt_count();
            u64 before = vinix_linuxkpi_clock_ns();
            native_usleep_call(worker, ranges[i][0], ranges[i][1]);
            native_usleep_check(worker, round * ARRAY_SIZE(ranges) + i,
                                ranges[i][0], vinix_linuxkpi_clock_ns() - before,
                                flags, depth);
        }
    }
    if (worker->kind == 0) {
        unsigned long flags = vinix_linuxkpi_irq_flags();
        unsigned int depth = vinix_linuxkpi_preempt_count();
        u64 before = vinix_linuxkpi_clock_ns();
        usleep_range_state(1000, 2000, TASK_RUNNING);
        native_usleep_check(worker, 28, 1000, vinix_linuxkpi_clock_ns() - before,
                            flags, depth);
    }
    vinix_linuxkpi_test_alloc_oom(-1);
    complete(&worker->series_done);
    wait_for_completion(&worker->long_go);
    if (__atomic_load_n(&worker->cancel, __ATOMIC_ACQUIRE)) goto out;
    unsigned long flags = vinix_linuxkpi_irq_flags();
    unsigned int depth = vinix_linuxkpi_preempt_count();
    worker->long_start = vinix_linuxkpi_clock_ns();
    complete(&worker->long_started);
    vinix_linuxkpi_test_alloc_oom(0);
    native_usleep_call(worker, NATIVE_USLEEP_LONG_US, NATIVE_USLEEP_LONG_US + 1000);
    worker->long_elapsed = vinix_linuxkpi_clock_ns() - worker->long_start;
    vinix_linuxkpi_test_alloc_oom(-1);
    native_usleep_check(worker, 29, NATIVE_USLEEP_LONG_US, worker->long_elapsed,
                        flags, depth);
    vinix_linuxkpi_test_task_signal(worker->task->vinix_thread, 0);
    complete(&worker->long_done);
    wait_for_completion(&worker->release);
out:
    vinix_linuxkpi_test_alloc_oom(-1);
    vinix_linuxkpi_test_task_signal(worker->task->vinix_thread, 0);
    if (!task_is_running(current) || !vinix_linuxkpi_may_sleep()) worker->reasons |= 64;
    complete(&worker->done);
    pthread_exit(NULL);
    return NULL;
}

static void native_usleep_release(struct native_usleep_worker *worker)
{
    if (!worker->initialized) return;
    __atomic_store_n(&worker->cancel, true, __ATOMIC_RELEASE);
    complete_all(&worker->go);
    complete_all(&worker->long_go);
    complete_all(&worker->release);
    struct task_struct *task = __atomic_load_n(&worker->task, __ATOMIC_ACQUIRE);
    if (worker->started && task) {
        vinix_linuxkpi_test_task_signal(task->vinix_thread, 0);
        wake_up_process(task);
    }
}

static int native_usleep_retire(struct native_usleep_worker *workers, unsigned int count)
{
    int result = 0;
    for (unsigned int i = 0; i < count; i++) native_usleep_release(&workers[i]);
    for (unsigned int i = 0; i < count; i++) {
        if (!workers[i].started) continue;
        /* Cancellation cannot shorten an already-started uninterruptible
         * range. Keep every stack record alive through natural expiration. */
        if (!wait_for_completion_timeout(&workers[i].done, 500)) {
            kprintf("linuxkpi: usleep worker=%u did not finish before cleanup watchdog\n", i);
            BUG();
        }
        BUG_ON(pthread_join(workers[i].thread, NULL));
    }
    u64 retirement_started = vinix_linuxkpi_clock_ns();
    for (unsigned int i = 0; i < count; i++) {
        if (!workers[i].started) continue;
        struct task_struct *task = __atomic_load_n(&workers[i].task, __ATOMIC_ACQUIRE);
        BUG_ON(!task);
        if (workers[i].reasons) {
            kprintf("linuxkpi: usleep worker=%u reasons=0x%x case=%u min=%lu elapsed_ns=%llu\n",
                    i, workers[i].reasons, workers[i].failed_case, workers[i].failed_min,
                    (unsigned long long)workers[i].failed_elapsed);
            result = -EIO;
        }
        while (__atomic_load_n(&task->__state, __ATOMIC_ACQUIRE) != TASK_DEAD) {
            if (vinix_linuxkpi_clock_ns() - retirement_started >= 1000000000ULL) {
                kprintf("linuxkpi: usleep worker=%u did not publish TASK_DEAD\n", i);
                BUG();
            }
            cond_resched();
        }
        size_t retained = vinix_linuxkpi_test_task_time_waiters(task);
        if (retained) {
            kprintf("linuxkpi: usleep worker=%u retained %zu deadline records\n", i, retained);
            BUG(); /* Preserve the retained native stacks and controller frame. */
        }
    }
    for (unsigned int i = 0; i < count; i++) {
        if (!workers[i].started) continue;
        while (!vinix_linuxkpi_test_thread_reap_ready(workers[i].task->vinix_thread)) {
            if (vinix_linuxkpi_clock_ns() - retirement_started >= 1000000000ULL) {
                kprintf("linuxkpi: usleep worker=%u did not reach off-stack reaper\n", i);
                BUG();
            }
            cond_resched();
        }
    }
    for (unsigned int i = 0; i < count; i++) {
        if (!workers[i].started) continue;
        put_task_struct(workers[i].task); /* Last read of this retained task. */
        workers[i].started = false;
    }
    while (!vinix_linuxkpi_test_reap_quiescent()) {
        if (vinix_linuxkpi_clock_ns() - retirement_started >= 1000000000ULL) {
            kprintf("linuxkpi: usleep deferred frees did not finish\n");
            BUG();
        }
        cond_resched();
    }
    return result;
}

static int native_usleep_wakes(struct native_usleep_worker *workers, unsigned int count)
{
    unsigned long watchdog = jiffies + 500;
    for (;;) {
        bool finished = true;
        for (unsigned int i = 0; i < count; i++) {
            struct native_usleep_worker *worker = &workers[i];
            if (completion_done(&worker->long_done)) continue;
            finished = false;
            struct task_struct *task = worker->task;
            if (__atomic_load_n(&task->__state, __ATOMIC_ACQUIRE) != worker->state ||
                vinix_linuxkpi_task_queued(task->vinix_thread) ||
                !vinix_linuxkpi_test_task_time_waiters(task)) continue;
            u64 before = vinix_linuxkpi_clock_ns();
            bool early = before - worker->long_start < NATIVE_USLEEP_LONG_NS;
            if (i < 2 && early && !worker->signal_sent) {
                /* Native delivery enqueues even an uninterruptible sleeper.
                 * Observe it park in that same state before accepting a wake. */
                worker->signal_sent = 1;
                vinix_linuxkpi_test_task_signal(task->vinix_thread, 1ULL << 14);
                continue;
            }
            if (early && worker->signal_sent) worker->signal_reparked = 1;
            int accepted = wake_up_process(task);
            if (accepted && vinix_linuxkpi_clock_ns() - worker->long_start < NATIVE_USLEEP_LONG_NS)
                worker->early_wakes++;
        }
        if (finished) break;
        if (time_after_eq(jiffies, watchdog)) {
            kprintf("linuxkpi: usleep did not finish under continuing wakeups\n");
            return -EIO;
        }
        /* This controller progresses while the actual target tasks are
         * off-queue. Keep waking after the original minimum boundary too:
         * restarting that boundary on every wake must not pass this test. */
        msleep(1);
    }
    unsigned int early_wakes = 0, signal_reparks = 0;
    for (unsigned int i = 0; i < count; i++) {
        early_wakes += workers[i].early_wakes;
        signal_reparks += workers[i].signal_reparked;
        if (workers[i].long_elapsed < NATIVE_USLEEP_LONG_NS) return -EIO;
    }
    /* Scheduling can overrun max and reduce the number of early samples.
     * Require a positive control, not a fixed three-wake count per CPU. */
    if (!early_wakes || !signal_reparks) {
        kprintf("linuxkpi: usleep early-wake proof not observed wakes=%u signal_reparks=%u\n",
                early_wakes, signal_reparks);
        return -EIO;
    }
    return 0;
}

static int native_usleep_group(unsigned int fail_after, unsigned int oom_stage)
{
    struct native_usleep_worker workers[4] = {{0}};
    static const unsigned int states[] = {
        TASK_UNINTERRUPTIBLE, TASK_IDLE, TASK_INTERRUPTIBLE, TASK_KILLABLE,
    };
    int result = 0;
    BUG_ON(oom_stage && (oom_stage > 4 || fail_after >= ARRAY_SIZE(workers)));
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++) {
        struct native_usleep_worker *worker = &workers[i];
        worker->cpu = i;
        worker->kind = i;
        worker->state = states[i];
        init_completion(&worker->entered);
        init_completion(&worker->go);
        init_completion(&worker->series_done);
        init_completion(&worker->long_go);
        init_completion(&worker->long_started);
        init_completion(&worker->long_done);
        init_completion(&worker->release);
        init_completion(&worker->done);
        worker->initialized = true;
        if (oom_stage && i == fail_after) vinix_linuxkpi_test_worker_oom(oom_stage);
        int error = pthread_create(&worker->thread, NULL, native_usleep_worker, worker);
        vinix_linuxkpi_test_worker_oom(0);
        if (!error) worker->started = true;
        if (oom_stage && i == fail_after) {
            if (error != EAGAIN || worker->started) result = -EIO;
            goto out;
        }
        if (error) { result = -ENOMEM; goto out; }
        if (!wait_for_completion_timeout(&worker->entered, 500)) { result = -EIO; goto out; }
    }
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++) complete(&workers[i].go);
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++)
        if (!wait_for_completion_timeout(&workers[i].series_done, 500)) { result = -EIO; goto out; }
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++) complete(&workers[i].long_go);
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++)
        if (!wait_for_completion_timeout(&workers[i].long_started, 500)) { result = -EIO; goto out; }
    result = native_usleep_wakes(workers, ARRAY_SIZE(workers));
out:
    if (native_usleep_retire(workers, ARRAY_SIZE(workers))) result = -EIO;
    return result;
}

int vinix_linuxkpi_usleep_native_selftest(void)
{
    if (vinix_linuxkpi_percpu_count() < 4) return -EIO;
    int result = 0;
    for (unsigned int stage = 1; stage <= 4; stage++)
        for (unsigned int before = 0; before < 4; before++)
            if (native_usleep_group(before, stage)) {
                kprintf("linuxkpi: usleep constructor rollback stage=%u after=%u failed\n", stage, before);
                result = -EIO;
            }
    if (native_usleep_group(0, 0)) result = -EIO;
    return result;
}
#endif
