/* SPDX-License-Identifier: GPL-2.0-only */
#if defined(VINIX_LINUXKPI) && !defined(VINIX_LINUXKPI_HOST_TEST)
#include <linux/init.h>
#include <linux/bitops.h>
#include <linux/sched.h>
#include <linux/sched/task.h>
#include <linux/sched/stat.h>
#include <linux/wait_bit.h>
#include <linux/completion.h>
#include <linux/delay.h>
#include <linux/errno.h>
#include <linux/jiffies.h>
#include <vinix/runtime.h>
#include <pthread.h>

void vinix_linuxkpi_test_task_signal(void *thread, u64 pending);
int vinix_linuxkpi_test_worker_route(void *thread, unsigned int cpu);

enum native_io_operation {
    NATIVE_IO_SLEEP, NATIVE_IO_TIMEOUT, NATIVE_IO_BIT, NATIVE_IO_LOCK,
    NATIVE_IO_PREEMPT, NATIVE_IO_ORDINARY, NATIVE_IO_EXIT_COUNTED,
};
struct native_io_thread {
    struct task_struct *task;
    pthread_t thread;
    struct completion entered, go, acquired, release, done;
    unsigned long *word;
    const unsigned int *baseline;
    long timeout, remaining;
    unsigned int cpu, resumed_cpu, state;
    enum native_io_operation operation;
    int value, result;
    bool initialized, started, nested, cancel;
};

static void *native_io_thread(void *argument)
{
    struct native_io_thread *test = argument;
    __atomic_store_n(&test->task, get_task_struct(current), __ATOMIC_RELEASE);
    int outer = -1;
    if (vinix_linuxkpi_worker_bind(test->cpu) || current->in_iowait) test->result = -EIO;
    complete(&test->entered);
    wait_for_completion(&test->go);
    if (__atomic_load_n(&test->cancel, __ATOMIC_ACQUIRE)) goto out;
    if (test->nested) {
        outer = io_schedule_prepare();
        int inner = io_schedule_prepare();
        if (outer || inner != 1 || !current->in_iowait) test->result = -EIO;
        io_schedule_finish(inner);
        if (!current->in_iowait) test->result = -EIO;
    }
    if (test->operation == NATIVE_IO_EXIT_COUNTED) {
        /* Exit after the actual off-queue transition, before an explicit park.
         * Keep IRQs off so no scheduler switch can strand the exiting task.
         * pthread_exit's real dead dequeue must retire the counted CPU token
         * even though this prepared scope can never return to finish. */
        int token = io_schedule_prepare();
        unsigned long flags = vinix_linuxkpi_irq_save(), wait_flags;
        raw_spin_lock_irqsave(&test->task->vinix_wait_lock, wait_flags);
        set_current_state(TASK_UNINTERRUPTIBLE);
        vinix_linuxkpi_task_dequeue(test->task->vinix_thread);
        vinix_linuxkpi_iowait_block(test->task->vinix_thread);
        raw_spin_unlock_irqrestore(&test->task->vinix_wait_lock, wait_flags);
        if (token || nr_iowait_cpu(test->cpu) != test->baseline[test->cpu] + 1)
            test->result = -EIO;
        (void)flags; /* IRQs deliberately remain disabled until final exit. */
        complete(&test->done);
        pthread_exit(NULL);
    }
    if (test->operation == NATIVE_IO_BIT)
        test->value = wait_on_bit_io(test->word, 0, test->state);
    else if (test->operation == NATIVE_IO_LOCK) {
        test->value = wait_on_bit_lock_io(test->word, 0, test->state);
        if (!test->value) {
            if (!test_bit(0, test->word) || current->in_iowait) test->result = -EIO;
            complete(&test->acquired);
            wait_for_completion(&test->release);
            clear_and_wake_up_bit(0, test->word);
        }
    } else {
        set_current_state(test->state);
        /* Cleanup publishes cancellation before wake, pairing with the full
         * state-store barrier even if it races this prepare-before-park gap. */
        if (__atomic_load_n(&test->cancel, __ATOMIC_ACQUIRE)) __set_current_state(TASK_RUNNING);
        else {
            if (test->operation == NATIVE_IO_PREEMPT) vinix_linuxkpi_test_park_preempt();
            if (test->operation == NATIVE_IO_TIMEOUT)
                test->remaining = io_schedule_timeout(test->timeout);
            else if (test->operation == NATIVE_IO_ORDINARY) schedule();
            else io_schedule();
        }
    }
    test->resumed_cpu = vinix_linuxkpi_cpu_id();
out:
    if (outer >= 0) {
        if (!current->in_iowait) test->result = -EIO;
        io_schedule_finish(outer);
    }
    vinix_linuxkpi_test_task_signal(test->task->vinix_thread, 0);
    if (current->in_iowait || !task_is_running(current) || !vinix_linuxkpi_may_sleep())
        test->result = -EIO;
    complete(&test->done);
    pthread_exit(NULL);
    return NULL;
}

static int native_io_start(struct native_io_thread *test, enum native_io_operation operation,
                           unsigned int cpu, unsigned int state, long timeout,
                           unsigned long *word, const unsigned int *baseline, bool nested)
{
    *test = (struct native_io_thread){ .operation = operation, .cpu = cpu, .state = state,
        .timeout = timeout, .word = word, .baseline = baseline, .nested = nested };
    init_completion(&test->entered);
    init_completion(&test->go);
    init_completion(&test->acquired);
    init_completion(&test->release);
    init_completion(&test->done);
    test->initialized = true;
    if (pthread_create(&test->thread, NULL, native_io_thread, test)) return -ENOMEM;
    test->started = true;
    return wait_for_completion_timeout(&test->entered, 500) ? 0 : -EIO;
}

static int native_io_parked(struct native_io_thread *test)
{
    unsigned long deadline = jiffies + 500;
    for (;;) {
        if (completion_done(&test->done)) return -EIO;
        if (__atomic_load_n(&test->task->__state, __ATOMIC_ACQUIRE) == test->state &&
            !vinix_linuxkpi_task_queued(test->task->vinix_thread)) return 0;
        if (time_after_eq(jiffies, deadline)) return -EIO;
        msleep(1);
    }
}

static int native_io_join(struct native_io_thread *test)
{
    if (!test->started) return 0;
    BUG_ON(pthread_join(test->thread, NULL));
    while (__atomic_load_n(&test->task->__state, __ATOMIC_ACQUIRE) != TASK_DEAD) cond_resched();
    int result = test->result;
    put_task_struct(test->task);
    test->started = false;
    return result;
}

static int native_io_counts(const unsigned int *baseline, unsigned int cpu0, unsigned int cpu1)
{
    unsigned long deadline = jiffies + 500;
    unsigned int count = vinix_linuxkpi_percpu_count();
    for (;;) {
        unsigned int total = 0;
        bool matches = true;
        for (unsigned int cpu = 0; cpu < count; cpu++) {
            unsigned int expected = baseline[cpu] + (cpu == 0 ? cpu0 : cpu == 1 ? cpu1 : 0);
            total += expected;
            if (nr_iowait_cpu(cpu) != expected) matches = false;
        }
        if (matches && nr_iowait() == total) return 0;
        if (time_after_eq(jiffies, deadline)) return -EIO;
        msleep(1);
    }
}

static void native_io_release(struct native_io_thread *test)
{
    if (!test->initialized) return;
    __atomic_store_n(&test->cancel, true, __ATOMIC_RELEASE);
    complete_all(&test->go);
    complete_all(&test->release);
    struct task_struct *task = __atomic_load_n(&test->task, __ATOMIC_ACQUIRE);
    if (test->started && task && test->operation != NATIVE_IO_EXIT_COUNTED) wake_up_process(task);
}

static int native_io_pool_counts(const unsigned int *baseline)
{
    struct native_io_thread tests[3] = {{0}};
    int result = 0;
    for (unsigned int i = 0; i < ARRAY_SIZE(tests); i++) {
        unsigned int cpu = i == 2 ? 1 : 0;
        if (native_io_start(&tests[i], i == 1 ? NATIVE_IO_PREEMPT : NATIVE_IO_SLEEP,
                             cpu, TASK_UNINTERRUPTIBLE, 0, NULL, baseline, i == 0))
            { result = -EIO; goto out; }
        complete(&tests[i].go);
        if (native_io_parked(&tests[i])) { result = -EIO; goto out; }
    }
    if (native_io_counts(baseline, 2, 1)) { result = -EIO; goto out; }
    /* Native delivery of a disallowed signal briefly makes a task runnable;
     * the actual schedule state filter must return it to the same I/O wait. */
    vinix_linuxkpi_test_task_signal(tests[1].task->vinix_thread, 1ULL << 14);
    if (native_io_parked(&tests[1]) || native_io_counts(baseline, 2, 1)) result = -EIO;
    /* Change affinity while asleep. The accepted wake must decrement CPU 0,
     * though this task is claimed and resumes on CPU 1. */
    if (vinix_linuxkpi_test_worker_route(tests[0].task->vinix_thread, 1)) result = -EIO;
    wake_up_process(tests[0].task);
    wake_up_process(tests[0].task); /* Duplicate wake must not decrement twice. */
    if (!wait_for_completion_timeout(&tests[0].done, 500) || tests[0].resumed_cpu != 1 ||
        native_io_counts(baseline, 1, 1)) result = -EIO;
out:
    for (unsigned int i = 0; i < ARRAY_SIZE(tests); i++) native_io_release(&tests[i]);
    for (unsigned int i = 0; i < ARRAY_SIZE(tests); i++)
        if (native_io_join(&tests[i])) result = -EIO;
    if (native_io_counts(baseline, 0, 0)) result = -EIO;
    return result;
}

static int native_io_timeout(const unsigned int *baseline, bool expire, bool interrupt)
{
    struct native_io_thread test = {0};
    unsigned int state = interrupt ? TASK_INTERRUPTIBLE : TASK_UNINTERRUPTIBLE;
    int result = native_io_start(&test, NATIVE_IO_TIMEOUT, 0, state, 200, NULL, baseline, true);
    if (result) goto out;
    complete(&test.go);
    if (native_io_parked(&test) || native_io_counts(baseline, 1, 0)) { result = -EIO; goto out; }
    if (interrupt) vinix_linuxkpi_test_task_signal(test.task->vinix_thread, 1ULL << 14);
    else if (!expire) wake_up_process(test.task);
    if (!wait_for_completion_timeout(&test.done, 500) ||
        (expire ? test.remaining != 0 : test.remaining <= 0 || test.remaining > 200)) result = -EIO;
out:
    native_io_release(&test);
    if (native_io_join(&test) || native_io_counts(baseline, 0, 0)) result = -EIO;
    return result;
}

static int native_io_bits(const unsigned int *baseline, bool lock, bool interrupt)
{
    unsigned long word = 1;
    struct native_io_thread tests[2] = {{0}};
    unsigned int nr = lock && !interrupt ? 2 : 1;
    int result = 0;
    for (unsigned int i = 0; i < nr; i++) {
        if (native_io_start(&tests[i], lock ? NATIVE_IO_LOCK : NATIVE_IO_BIT, 0,
                             interrupt ? TASK_INTERRUPTIBLE : TASK_UNINTERRUPTIBLE,
                             0, &word, baseline, false)) { result = -EIO; goto out; }
        complete(&tests[i].go);
        if (native_io_parked(&tests[i])) { result = -EIO; goto out; }
    }
    if (native_io_counts(baseline, nr, 0)) { result = -EIO; goto out; }
    if (interrupt) {
        vinix_linuxkpi_test_task_signal(tests[0].task->vinix_thread, 1ULL << 14);
        if (!wait_for_completion_timeout(&tests[0].done, 500) || tests[0].value != -EINTR ||
            !test_bit(0, &word)) result = -EIO;
    } else {
        clear_and_wake_up_bit(0, &word);
        if (lock) {
            if (!wait_for_completion_timeout(&tests[0].acquired, 500) ||
                completion_done(&tests[1].acquired) || native_io_counts(baseline, 1, 0))
                { result = -EIO; goto out; }
            complete(&tests[0].release);
            if (!wait_for_completion_timeout(&tests[1].acquired, 500) ||
                native_io_counts(baseline, 0, 0)) result = -EIO;
        } else if (!wait_for_completion_timeout(&tests[0].done, 500)) result = -EIO;
    }
out:
    for (unsigned int i = 0; i < nr; i++) native_io_release(&tests[i]);
    clear_and_wake_up_bit(0, &word);
    for (unsigned int i = 0; i < nr; i++)
        if (native_io_join(&tests[i])) result = -EIO;
    if (waitqueue_active(bit_waitqueue(&word, 0)) || native_io_counts(baseline, 0, 0)) result = -EIO;
    return result;
}

static int native_io_fast_paths(const unsigned int *baseline)
{
    struct task_struct *task = current;
    int result = 0;
    for (unsigned int i = 0; i < 128; i++) {
        int outer = io_schedule_prepare(), inner = io_schedule_prepare();
        if (outer || inner != 1 || !task->in_iowait) result = -EIO;
        io_schedule_finish(inner);
        if (!task->in_iowait || native_io_counts(baseline, 0, 0)) result = -EIO;
        io_schedule(); /* RUNNING yields; it does not become a counted sleeper. */
        if (io_schedule_timeout(MAX_SCHEDULE_TIMEOUT) != MAX_SCHEDULE_TIMEOUT ||
            io_schedule_timeout(0) || !task->in_iowait) result = -EIO;
        io_schedule_finish(outer);
        set_current_state(TASK_INTERRUPTIBLE);
        vinix_linuxkpi_test_task_signal(task->vinix_thread, 1ULL << 14);
        long remaining = io_schedule_timeout(10);
        if (remaining < 0 || remaining > 10 || task->in_iowait || !task_is_running(task))
            result = -EIO;
        vinix_linuxkpi_test_task_signal(task->vinix_thread, 0);
        /* An accepted wake after dequeue but before the block helper wins
         * without starting an I/O count or parking this live stack. */
        int token = io_schedule_prepare();
        unsigned long flags = vinix_linuxkpi_irq_save(), wait_flags;
        raw_spin_lock_irqsave(&task->vinix_wait_lock, wait_flags);
        set_current_state(TASK_UNINTERRUPTIBLE);
        vinix_linuxkpi_task_dequeue(task->vinix_thread);
        raw_spin_unlock_irqrestore(&task->vinix_wait_lock, wait_flags);
        if (!wake_up_process(task)) result = -EIO;
        raw_spin_lock_irqsave(&task->vinix_wait_lock, wait_flags);
        vinix_linuxkpi_iowait_block(task->vinix_thread);
        raw_spin_unlock_irqrestore(&task->vinix_wait_lock, wait_flags);
        io_schedule_finish(token);
        vinix_linuxkpi_irq_restore(flags);
        if (!task_is_running(task) || task->in_iowait || native_io_counts(baseline, 0, 0))
            result = -EIO;
        unsigned long word = 1;
        struct wait_bit_key key = { .flags = &word, .bit_nr = 0, .timeout = jiffies };
        if (bit_wait_io_timeout(&key, TASK_UNINTERRUPTIBLE) != -EAGAIN || task->in_iowait)
            result = -EIO;
    }
    return result;
}

static int native_io_ordinary_and_exit(const unsigned int *baseline, bool exiting)
{
    struct native_io_thread test = {0};
    int result = native_io_start(&test, exiting ? NATIVE_IO_EXIT_COUNTED : NATIVE_IO_ORDINARY,
                                  0, TASK_UNINTERRUPTIBLE, 0, NULL, baseline, false);
    if (result) goto out;
    complete(&test.go);
    if (exiting) {
        if (!wait_for_completion_timeout(&test.done, 500)) result = -EIO;
    } else {
        if (native_io_parked(&test) || native_io_counts(baseline, 0, 0)) result = -EIO;
    }
out:
    native_io_release(&test);
    if (native_io_join(&test) || native_io_counts(baseline, 0, 0)) result = -EIO;
    return result;
}

int vinix_linuxkpi_io_native_selftest(void)
{
    extern int kprintf(const char *, ...);
    unsigned int count = vinix_linuxkpi_percpu_count(), baseline[256];
    int result = 0;
    if (count < 2 || count > ARRAY_SIZE(baseline)) return -EIO;
    for (unsigned int cpu = 0; cpu < count; cpu++) baseline[cpu] = nr_iowait_cpu(cpu);
    if (native_io_fast_paths(baseline)) { kprintf("linuxkpi: I/O fast/nested/early-wake checks failed\n"); result = -EIO; }
    if (native_io_pool_counts(baseline)) { kprintf("linuxkpi: I/O blocked CPU/migration/preempt checks failed\n"); result = -EIO; }
    for (unsigned int kind = 0; kind < 3; kind++)
        if (native_io_timeout(baseline, kind == 0, kind == 2))
            { kprintf("linuxkpi: I/O timeout/early/signal checks failed\n"); result = -EIO; }
    for (unsigned int lock = 0; lock < 2; lock++)
        for (unsigned int interrupt = 0; interrupt < 2; interrupt++)
            if (native_io_bits(baseline, lock, interrupt))
                { kprintf("linuxkpi: I/O bit/lock/cancel checks failed\n"); result = -EIO; }
    if (native_io_ordinary_and_exit(baseline, false) || native_io_ordinary_and_exit(baseline, true))
        { kprintf("linuxkpi: I/O ordinary-sleep/dead-dequeue checks failed\n"); result = -EIO; }
    if (native_io_counts(baseline, 0, 0) || current->in_iowait ||
        !task_is_running(current) || !vinix_linuxkpi_may_sleep()) result = -EIO;
    return result;
}
#endif
