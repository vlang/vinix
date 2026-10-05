/* SPDX-License-Identifier: GPL-2.0-only */
#ifdef VINIX_LINUXKPI
#ifdef VINIX_LINUXKPI_HOST_TEST
#include <pthread.h>
/* The host pthread declarations precede Linux compiler and clock macros. */
#undef CLOCKS_PER_SEC
#undef CLOCK_REALTIME
#undef CLOCK_MONOTONIC
#undef CLOCK_PROCESS_CPUTIME_ID
#undef CLOCK_THREAD_CPUTIME_ID
#undef CLOCK_MONOTONIC_RAW
#undef CLOCK_REALTIME_COARSE
#undef CLOCK_MONOTONIC_COARSE
#undef TIMER_ABSTIME
#endif
#include <linux/workqueue.h>
#include <linux/completion.h>
#include <linux/sched.h>
#include <linux/sched/task.h>
#include <linux/slab.h>
#include <linux/delay.h>
#ifdef VINIX_LINUXKPI_HOST_TEST
int vsnprintf(char *, size_t, const char *, va_list);
void vinix_linuxkpi_host_worker_enter(void);
void vinix_linuxkpi_host_worker_leave(void);
void vinix_linuxkpi_host_delayed_timer_gate(struct timer_list *timer);
void vinix_linuxkpi_host_pool_publish_gate(struct workqueue_struct *wq, unsigned int cpu);
#else
#include <pthread.h>
int npf_vsnprintf(char *, size_t, const char *, va_list);
#endif

#ifndef VINIX_LINUXKPI_HOST_TEST
struct native_work_test {
    struct work_struct work;
    struct workqueue_struct *wq;
    struct completion entered, gate;
    unsigned int index, calls, limit;
    unsigned int *count, *order;
    int *result;
    bool hold, free_self;
};
static void native_work_callback(struct work_struct *work)
{
    struct native_work_test *test = container_of(work, struct native_work_test, work);
    if (!vinix_linuxkpi_may_sleep() || current_work() != work) *test->result = -EIO;
    if (test->count) {
        unsigned int index = (*test->count)++;
        if (test->order) test->order[index] = test->index;
    }
    test->calls++;
    if (test->hold) {
        complete(&test->entered);
        wait_for_completion(&test->gate);
    }
    msleep(1); /* Exercise the real scheduler inside a work callback. */
    if (test->calls < test->limit && !queue_work(test->wq, work)) *test->result = -EIO;
    if (test->free_self) kfree(test);
}
static void native_work_init(struct native_work_test *test, struct workqueue_struct *wq, int *result)
{
    *test = (struct native_work_test){ .wq = wq, .result = result };
    INIT_WORK_ONSTACK(&test->work, native_work_callback);
    init_completion(&test->entered);
    init_completion(&test->gate);
}
int vinix_linuxkpi_workqueue_native_selftest(void)
{
    struct workqueue_struct *queues[4] = {0};
    struct native_work_test tests[4][24], chains[4];
    unsigned int order[4][24], count[4] = {0}, freed[4] = {0};
    int results[4] = {0};
    int result = 0;
    for (unsigned int cpu = 0; cpu < ARRAY_SIZE(queues); cpu++) {
        queues[cpu] = alloc_ordered_workqueue("vinix-test-%u", 0, cpu);
        if (!queues[cpu]) { result = -ENOMEM; goto out; }
    }
    for (unsigned int cpu = 0; cpu < ARRAY_SIZE(queues); cpu++) {
        for (unsigned int i = 0; i < ARRAY_SIZE(tests[cpu]); i++) {
            native_work_init(&tests[cpu][i], queues[cpu], &results[cpu]);
            tests[cpu][i].index = i;
            tests[cpu][i].order = order[cpu];
            tests[cpu][i].count = &count[cpu];
        }
        tests[cpu][0].hold = true;
        if (!queue_work(queues[cpu], &tests[cpu][0].work)) results[cpu] = -EIO;
        wait_for_completion(&tests[cpu][0].entered);
        for (unsigned int i = 1; i < ARRAY_SIZE(tests[cpu]); i++) {
            if (!queue_work(queues[cpu], &tests[cpu][i].work) ||
                queue_work(queues[cpu], &tests[cpu][i].work)) results[cpu] = -EIO;
        }
        if (!cancel_work_sync(&tests[cpu][7].work)) results[cpu] = -EIO;
        complete(&tests[cpu][0].gate);
    }
    for (unsigned int cpu = 0; cpu < ARRAY_SIZE(queues); cpu++) {
        flush_workqueue(queues[cpu]);
        if (count[cpu] != 23 || tests[cpu][7].calls) results[cpu] = -EIO;
        for (unsigned int i = 0; i < count[cpu]; i++)
            if (order[cpu][i] != i + (i >= 7)) results[cpu] = -EIO;
        native_work_init(&chains[cpu], queues[cpu], &results[cpu]);
        chains[cpu].limit = 8;
        if (!queue_work(queues[cpu], &chains[cpu].work)) results[cpu] = -EIO;
    }
    for (unsigned int cpu = 0; cpu < ARRAY_SIZE(queues); cpu++) {
        drain_workqueue(queues[cpu]);
        if (chains[cpu].calls != 8 || work_busy(&chains[cpu].work)) results[cpu] = -EIO;
        for (unsigned int i = 0; i < 16; i++) {
            struct native_work_test *test = kzalloc(sizeof(*test), GFP_KERNEL);
            if (!test) { results[cpu] = -ENOMEM; break; }
            native_work_init(test, queues[cpu], &results[cpu]);
            test->free_self = true;
            test->count = &freed[cpu];
            if (!queue_work(queues[cpu], &test->work)) { kfree(test); results[cpu] = -EIO; }
        }
        flush_workqueue(queues[cpu]);
        if (freed[cpu] != 16) results[cpu] = -EIO;
    }
out:
    for (unsigned int cpu = 0; cpu < ARRAY_SIZE(queues); cpu++) {
        if (queues[cpu]) destroy_workqueue(queues[cpu]);
        if (results[cpu]) result = results[cpu];
    }
    return result;
}

struct native_delayed_frees { atomic_t count; struct completion done; };
struct native_delayed_test {
    struct delayed_work work;
    struct workqueue_struct *wq;
    struct completion done;
    struct native_delayed_frees *frees;
    unsigned long earliest;
    unsigned int calls, limit;
    int *result;
};
static void native_delayed_callback(struct work_struct *work)
{
    struct native_delayed_test *test = container_of(to_delayed_work(work), struct native_delayed_test, work);
    if (!vinix_linuxkpi_may_sleep() || current_work() != work ||
        time_before(jiffies, test->earliest)) *test->result = -EIO;
    test->calls++;
    msleep(1);
    if (test->frees) {
        struct native_delayed_frees *frees = test->frees;
        kfree(test);
        if (atomic_inc_return(&frees->count) == 8) complete(&frees->done);
        return;
    }
    if (test->calls < test->limit) {
        test->earliest = jiffies + 2;
        if (!queue_delayed_work(test->wq, &test->work, 2)) *test->result = -EIO;
    } else complete(&test->done);
}
static void native_delayed_init(struct native_delayed_test *test,
                                struct workqueue_struct *wq, int *result)
{
    *test = (struct native_delayed_test){ .wq = wq, .result = result, .earliest = jiffies };
    INIT_DELAYED_WORK_ONSTACK(&test->work, native_delayed_callback);
    init_completion(&test->done);
}
int vinix_linuxkpi_delayed_work_native_selftest(void)
{
    struct workqueue_struct *queues[4] = {0};
    struct native_delayed_test tests[4];
    struct native_delayed_test *heap[4][8] = {0};
    struct native_delayed_frees frees[4];
    int results[4] = {0}, result = 0;
    bool submitted = false;
    for (unsigned int i = 0; i < ARRAY_SIZE(queues); i++) {
        queues[i] = alloc_ordered_workqueue("vinix-delayed-%u", 0, i);
        if (!queues[i]) { result = -ENOMEM; goto out; }
    }
    for (unsigned int i = 0; i < ARRAY_SIZE(queues); i++) {
        native_delayed_init(&tests[i], queues[i], &results[i]);
        tests[i].limit = 4;
        if (!queue_delayed_work(queues[i], &tests[i].work, 1000)) results[i] = -EIO;
        tests[i].earliest = jiffies + 2;
        if (!mod_delayed_work(queues[i], &tests[i].work, 2)) results[i] = -EIO;
    }
    for (unsigned int i = 0; i < ARRAY_SIZE(queues); i++) {
        if (!wait_for_completion_timeout(&tests[i].done, 500)) results[i] = -EIO;
        cancel_delayed_work_sync(&tests[i].work);
        if (tests[i].calls != 4 || work_busy(&tests[i].work.work)) results[i] = -EIO;

        native_delayed_init(&tests[i], queues[i], &results[i]);
        if (!queue_delayed_work(queues[i], &tests[i].work, 100000) ||
            !flush_delayed_work(&tests[i].work)) results[i] = -EIO;
        if (tests[i].calls != 1 || timer_pending(&tests[i].work.timer)) results[i] = -EIO;
        cancel_delayed_work_sync(&tests[i].work);

        native_delayed_init(&tests[i], queues[i], &results[i]);
        unsigned long flags = vinix_linuxkpi_irq_save();
        if (!queue_delayed_work(queues[i], &tests[i].work, 100000) ||
            !mod_delayed_work(queues[i], &tests[i].work, 200000) ||
            !cancel_delayed_work(&tests[i].work) ||
            (vinix_linuxkpi_irq_flags() & (1UL << 9))) results[i] = -EIO;
        vinix_linuxkpi_irq_restore(flags);
        if (tests[i].calls || work_busy(&tests[i].work.work)) results[i] = -EIO;
        if (!queue_delayed_work(queues[i], &tests[i].work, 100000) ||
            !cancel_delayed_work_sync(&tests[i].work)) results[i] = -EIO;
    }
    /* Allocate the entire batch before publishing any object. Allocation
     * failure can then free only unsubmitted objects with no callback race. */
    for (unsigned int i = 0; i < ARRAY_SIZE(queues); i++) {
        atomic_set(&frees[i].count, 0);
        init_completion(&frees[i].done);
        for (unsigned int j = 0; j < ARRAY_SIZE(heap[i]); j++) {
            heap[i][j] = kzalloc(sizeof(*heap[i][j]), GFP_KERNEL);
            if (!heap[i][j]) { result = -ENOMEM; goto out; }
            native_delayed_init(heap[i][j], queues[i], &results[i]);
            heap[i][j]->frees = &frees[i];
        }
    }
    submitted = true;
    for (unsigned int i = 0; i < ARRAY_SIZE(queues); i++)
        for (unsigned int j = 0; j < ARRAY_SIZE(heap[i]); j++) {
            heap[i][j]->earliest = jiffies + 2;
            BUG_ON(!queue_delayed_work(queues[i], &heap[i][j]->work, 2));
        }
    for (unsigned int i = 0; i < ARRAY_SIZE(queues); i++) {
        if (!wait_for_completion_timeout(&frees[i].done, 500)) {
            results[i] = -EIO;
            wait_for_completion(&frees[i].done);
        }
        flush_workqueue(queues[i]);
        if (atomic_read(&frees[i].count) != 8) results[i] = -EIO;
    }
out:
    for (unsigned int i = 0; i < ARRAY_SIZE(queues); i++) {
        if (!submitted)
            for (unsigned int j = 0; j < ARRAY_SIZE(heap[i]); j++) kfree(heap[i][j]);
        if (queues[i]) destroy_workqueue(queues[i]);
        if (results[i]) result = results[i];
    }
    /* A self-freeing work callback can finish on another CPU before the
     * timer dispatcher retires its pointer-only transfer record. */
    unsigned long retire_by = jiffies + 500;
    while (vinix_linuxkpi_timer_active() && time_before(jiffies, retire_by)) msleep(1);
    if (vinix_linuxkpi_timer_active()) result = -EIO;
    return result;
}

struct native_parallel_test {
    struct work_struct work;
    struct workqueue_struct *wq;
    struct native_parallel_test *target;
    struct completion entered, gate, done;
    struct native_delayed_frees *frees;
    atomic_t active;
    unsigned int calls, limit, failure_reasons;
    int result;
    int *free_result;
    unsigned int *free_reasons;
    bool hold;
};
enum native_parallel_failure_reason {
    NATIVE_PARALLEL_CONTEXT = BIT(0), NATIVE_PARALLEL_CURRENT = BIT(1),
    NATIVE_PARALLEL_OVERLAP = BIT(2), NATIVE_PARALLEL_TARGET_QUEUE = BIT(3),
    NATIVE_PARALLEL_TARGET_RESULT = BIT(4), NATIVE_PARALLEL_REQUEUE = BIT(5),
    NATIVE_PARALLEL_ACTIVE = BIT(6),
};
static void native_parallel_failure(struct native_parallel_test *test, unsigned int reason)
{
    test->failure_reasons |= reason;
    test->result = -EIO;
}
/* Read callback-owned fields only after flush/cancel/destruction has stopped
 * every writer. Timeout reports deliberately pass no live callback record. */
static void native_parallel_report(const char *stage, unsigned int queue, unsigned int item,
                                   unsigned long ticks, struct native_parallel_test *test,
                                   int observed, int expected, unsigned int reasons)
{
    extern int kprintf(const char *, ...);
    kprintf("linuxkpi: unbound test %s failed queue=%u item=%u ticks=%lu observed=%d expected=%d calls=%u active=%d callback_result=%d reasons=0x%x\n",
            stage, queue, item, ticks, observed, expected, test ? test->calls : 0,
            test ? atomic_read(&test->active) : 0, test ? test->result : 0,
            test ? test->failure_reasons : reasons);
}
static void native_parallel_callback(struct work_struct *work)
{
    struct native_parallel_test *test = container_of(work, struct native_parallel_test, work);
    /* Keep the original short-circuit evaluation order, including whether
     * the initial active increment runs when the context check fails. */
    if (!vinix_linuxkpi_may_sleep()) native_parallel_failure(test, NATIVE_PARALLEL_CONTEXT);
    else if (current_work() != work) native_parallel_failure(test, NATIVE_PARALLEL_CURRENT);
    else if (atomic_inc_return(&test->active) != 1)
        native_parallel_failure(test, NATIVE_PARALLEL_OVERLAP);
    test->calls++;
    if (test->hold) {
        complete(&test->entered);
        wait_for_completion(&test->gate);
    }
    msleep(1);
    if (test->target) {
        if (!queue_work(test->wq, &test->target->work))
            native_parallel_failure(test, NATIVE_PARALLEL_TARGET_QUEUE);
        flush_work(&test->target->work);
        if (test->target->calls != 1 || atomic_read(&test->target->active))
            native_parallel_failure(test, NATIVE_PARALLEL_TARGET_RESULT);
    }
    if (test->calls < test->limit && !queue_work(test->wq, work))
        native_parallel_failure(test, NATIVE_PARALLEL_REQUEUE);
    if (atomic_dec_return(&test->active)) native_parallel_failure(test, NATIVE_PARALLEL_ACTIVE);
    if (test->frees) {
        struct native_delayed_frees *frees = test->frees;
        *test->free_result = test->result;
        *test->free_reasons = test->failure_reasons;
        kfree(test);
        if (atomic_inc_return(&frees->count) == 8) complete(&frees->done);
        return;
    }
    if (test->calls >= test->limit) complete(&test->done);
}
static void native_parallel_init(struct native_parallel_test *test, struct workqueue_struct *wq)
{
    *test = (struct native_parallel_test){ .wq = wq, .limit = 1 };
    INIT_WORK_ONSTACK(&test->work, native_parallel_callback);
    atomic_set(&test->active, 0);
    init_completion(&test->entered);
    init_completion(&test->gate);
    init_completion(&test->done);
}
int vinix_linuxkpi_unbound_work_native_selftest(void)
{
    struct workqueue_struct *queues[3] = {0};
    struct native_parallel_test held[3][8], extra[2], chains[3][4];
    struct native_parallel_test *heap[3][8] = {0};
    struct native_delayed_frees frees[3];
    int free_results[3][8] = {0}, result = 0;
    unsigned int free_reasons[3][8] = {0};
    const unsigned int limit[3] = {2, 4, 8};
    bool held_submitted = false, heap_submitted = false;
    queues[0] = alloc_workqueue("vinix-parallel-2", WQ_UNBOUND, 2);
    queues[1] = alloc_workqueue("vinix-parallel-4", WQ_UNBOUND, 4);
    queues[2] = system_unbound_wq;
    if (!queues[0] || !queues[1] || !queues[2]) {
        result = -ENOMEM;
        native_parallel_report("queue allocation", 0, 0, 0, NULL,
                               !!queues[0] + !!queues[1] + !!queues[2], 3, 0);
        goto out;
    }
    for (unsigned int q = 0; q < ARRAY_SIZE(queues); q++)
        for (unsigned int i = 0; i < limit[q]; i++) {
            native_parallel_init(&held[q][i], queues[q]);
            held[q][i].hold = true;
        }
    held_submitted = true;
    for (unsigned int q = 0; q < ARRAY_SIZE(queues); q++)
        for (unsigned int i = 0; i < limit[q]; i++)
            BUG_ON(!queue_work(queues[q], &held[q][i].work));
    for (unsigned int q = 0; q < ARRAY_SIZE(queues); q++)
        for (unsigned int i = 0; i < limit[q]; i++) {
            unsigned long started = jiffies;
            if (!wait_for_completion_timeout(&held[q][i].entered, 500)) {
                result = -EIO;
                native_parallel_report("held entry timeout", q, i, jiffies - started,
                                       NULL, 0, 1, 0);
                goto out;
            }
        }
    for (unsigned int q = 0; q < ARRAY_SIZE(extra); q++) {
        native_parallel_init(&extra[q], queues[q]);
        BUG_ON(!queue_work(queues[q], &extra[q].work));
        msleep(2);
        unsigned int busy = work_busy(&extra[q].work);
        if (busy != WORK_BUSY_PENDING) {
            result = -EIO;
            native_parallel_report("active-limit pending state", q, 0, 0, NULL,
                                   busy, WORK_BUSY_PENDING, 0);
        }
        complete(&held[q][0].gate);
        flush_work(&extra[q].work);
        if (extra[q].calls != 1 || extra[q].result) {
            result = -EIO;
            native_parallel_report("deferred callback", q, 0, 0, &extra[q],
                                   extra[q].calls, 1, 0);
        }
    }
    for (unsigned int q = 0; q < ARRAY_SIZE(queues); q++) {
        for (unsigned int i = 0; i < limit[q]; i++) complete(&held[q][i].gate);
        flush_workqueue(queues[q]);
        for (unsigned int i = 0; i < limit[q]; i++)
            if (held[q][i].calls != 1 || held[q][i].result) {
                result = -EIO;
                native_parallel_report("held callback", q, i, 0, &held[q][i],
                                       held[q][i].calls, 1, 0);
            }
    }
    held_submitted = false;
    for (unsigned int q = 0; q < ARRAY_SIZE(queues); q++)
        for (unsigned int i = 0; i < ARRAY_SIZE(chains[q]); i++) {
            native_parallel_init(&chains[q][i], queues[q]);
            chains[q][i].limit = 4;
            BUG_ON(!queue_work(queues[q], &chains[q][i].work));
        }
    for (unsigned int q = 0; q < ARRAY_SIZE(queues); q++)
        for (unsigned int i = 0; i < ARRAY_SIZE(chains[q]); i++) {
            unsigned long started = jiffies;
            if (!wait_for_completion_timeout(&chains[q][i].done, 500)) {
                result = -EIO;
                native_parallel_report("requeue timeout", q, i, jiffies - started,
                                       NULL, 0, 1, 0);
            }
            cancel_work_sync(&chains[q][i].work);
            if (chains[q][i].calls != 4 || chains[q][i].result) {
                result = -EIO;
                native_parallel_report("requeue callback", q, i, jiffies - started,
                                       &chains[q][i], chains[q][i].calls, 4, 0);
            }
        }
    struct native_parallel_test nested, target;
    native_parallel_init(&nested, queues[0]);
    native_parallel_init(&target, queues[0]);
    nested.target = &target;
    BUG_ON(!queue_work(queues[0], &nested.work));
    unsigned long nested_started = jiffies;
    if (!wait_for_completion_timeout(&nested.done, 500)) {
        result = -EIO;
        native_parallel_report("nested item-flush timeout", 0, 0, jiffies - nested_started,
                               NULL, 0, 1, 0);
    }
    cancel_work_sync(&nested.work);
    cancel_work_sync(&target.work);
    if (nested.result || target.result || target.calls != 1) {
        result = -EIO;
        if (nested.result)
            native_parallel_report("nested caller", 0, 0, jiffies - nested_started,
                                   &nested, nested.result, 0, 0);
        if (target.result || target.calls != 1)
            native_parallel_report("nested target", 0, 1, jiffies - nested_started,
                                   &target, target.calls, 1, 0);
    }
    for (unsigned int q = 0; q < ARRAY_SIZE(queues); q++) {
        atomic_set(&frees[q].count, 0); init_completion(&frees[q].done);
        for (unsigned int i = 0; i < ARRAY_SIZE(heap[q]); i++) {
            heap[q][i] = kzalloc(sizeof(*heap[q][i]), GFP_KERNEL);
            if (!heap[q][i]) {
                result = -ENOMEM;
                native_parallel_report("self-free allocation", q, i, 0, NULL, 0, 1, 0);
                goto out;
            }
            native_parallel_init(heap[q][i], queues[q]);
            heap[q][i]->frees = &frees[q];
            heap[q][i]->free_result = &free_results[q][i];
            heap[q][i]->free_reasons = &free_reasons[q][i];
        }
    }
    heap_submitted = true;
    for (unsigned int q = 0; q < ARRAY_SIZE(queues); q++)
        for (unsigned int i = 0; i < ARRAY_SIZE(heap[q]); i++)
            BUG_ON(!queue_work(queues[q], &heap[q][i]->work));
    for (unsigned int q = 0; q < ARRAY_SIZE(queues); q++) {
        unsigned long started = jiffies;
        if (!wait_for_completion_timeout(&frees[q].done, 500)) {
            result = -EIO;
            native_parallel_report("self-free timeout", q, 0, jiffies - started,
                                   NULL, atomic_read(&frees[q].count), 8, 0);
            wait_for_completion(&frees[q].done);
        }
        flush_workqueue(queues[q]);
        if (atomic_read(&frees[q].count) != 8) {
            result = -EIO;
            native_parallel_report("self-free count", q, 0, jiffies - started,
                                   NULL, atomic_read(&frees[q].count), 8, 0);
        }
        for (unsigned int i = 0; i < ARRAY_SIZE(heap[q]); i++)
            if (free_results[q][i]) {
                result = -EIO;
                native_parallel_report("self-free callback", q, i, jiffies - started,
                                       NULL, free_results[q][i], 0, free_reasons[q][i]);
            }
    }
out:
    for (unsigned int q = 0; q < ARRAY_SIZE(queues); q++) {
        if (held_submitted)
            for (unsigned int i = 0; i < limit[q]; i++) complete(&held[q][i].gate);
        if (!heap_submitted)
            for (unsigned int i = 0; i < ARRAY_SIZE(heap[q]); i++) kfree(heap[q][i]);
        if (queues[q]) {
            if (q != 2) destroy_workqueue(queues[q]);
            else drain_workqueue(queues[q]);
        }
    }
    return result;
}

struct native_bound_test {
    struct delayed_work delayed;
    struct workqueue_struct *wq, *requeue_wq;
    struct native_bound_test *dependency;
    struct completion entered, gate, done;
    struct native_delayed_frees *frees;
    int *free_result;
    atomic_t active;
    unsigned int expected_cpu[2], calls, requeue_cpu, failure_reasons;
    int expected_nice, result;
    bool hold, spin, release_spin;
};
enum native_bound_failure_reason {
    NATIVE_BOUND_OVERLAP = BIT(0), NATIVE_BOUND_CONTEXT = BIT(1),
    NATIVE_BOUND_CURRENT = BIT(2), NATIVE_BOUND_CPU = BIT(3),
    NATIVE_BOUND_NICE = BIT(4), NATIVE_BOUND_SLICE = BIT(5),
    NATIVE_BOUND_DEPENDENCY_QUEUE = BIT(6), NATIVE_BOUND_DEPENDENCY_TIMEOUT = BIT(7),
    NATIVE_BOUND_AFTER_SLEEP = BIT(8), NATIVE_BOUND_REQUEUE = BIT(9),
    NATIVE_BOUND_ACTIVE = BIT(10),
};
static void native_bound_failure(struct native_bound_test *test, unsigned int reason)
{
    test->failure_reasons |= reason;
    test->result = -EIO;
}
static void native_bound_callback(struct work_struct *work)
{
    struct native_bound_test *test = container_of(to_delayed_work(work), struct native_bound_test, delayed);
    unsigned int call = test->calls++;
    unsigned int expected = test->expected_cpu[call ? 1 : 0];
    if (atomic_inc_return(&test->active) != 1) native_bound_failure(test, NATIVE_BOUND_OVERLAP);
    if (!vinix_linuxkpi_may_sleep()) native_bound_failure(test, NATIVE_BOUND_CONTEXT);
    if (current_work() != work) native_bound_failure(test, NATIVE_BOUND_CURRENT);
    if (expected != WORK_CPU_UNBOUND && vinix_linuxkpi_cpu_id() != expected)
        native_bound_failure(test, NATIVE_BOUND_CPU);
    if (vinix_linuxkpi_worker_nice() != test->expected_nice) native_bound_failure(test, NATIVE_BOUND_NICE);
    if (vinix_linuxkpi_worker_timeslice() != (test->expected_nice == -20 ? 10000 : 5000))
        native_bound_failure(test, NATIVE_BOUND_SLICE);
    complete(&test->entered);
    while (test->spin && !__atomic_load_n(&test->release_spin, __ATOMIC_ACQUIRE)) cond_resched();
    if (test->hold) wait_for_completion(&test->gate);
    if (test->dependency) {
        if (!queue_work_on(expected, test->wq, &test->dependency->delayed.work))
            native_bound_failure(test, NATIVE_BOUND_DEPENDENCY_QUEUE);
        /* Force preemption on task-dequeue's IRQ restore, before the explicit
         * park call. The actual scheduler sleep hook must enable replacement. */
        vinix_linuxkpi_test_park_preempt();
        if (!wait_for_completion_timeout(&test->dependency->done, 500))
            native_bound_failure(test, NATIVE_BOUND_DEPENDENCY_TIMEOUT);
    }
    cond_resched();
    msleep(1);
    if (expected != WORK_CPU_UNBOUND && vinix_linuxkpi_cpu_id() != expected)
        native_bound_failure(test, NATIVE_BOUND_AFTER_SLEEP);
    if (!call && test->requeue_wq && !queue_work_on(test->requeue_cpu, test->requeue_wq, work))
        native_bound_failure(test, NATIVE_BOUND_REQUEUE);
    if (atomic_dec_return(&test->active)) native_bound_failure(test, NATIVE_BOUND_ACTIVE);
    if (test->frees) {
        struct native_delayed_frees *frees = test->frees;
        *test->free_result = test->result;
        kfree(test);
        if (atomic_inc_return(&frees->count) == 16) complete(&frees->done);
        return;
    }
    if (!test->requeue_wq || call) complete(&test->done);
}
static void native_bound_init(struct native_bound_test *test, struct workqueue_struct *wq,
                               unsigned int cpu, bool highpri)
{
    *test = (struct native_bound_test){ .wq = wq, .expected_cpu = { cpu, cpu },
                                      .expected_nice = highpri ? -20 : 0 };
    INIT_DELAYED_WORK_ONSTACK(&test->delayed, native_bound_callback);
    init_completion(&test->entered);
    init_completion(&test->gate);
    init_completion(&test->done);
    atomic_set(&test->active, 0);
}
static int native_bound_finish(struct native_bound_test *test, const char *stage)
{
    extern int kprintf(const char *, ...);
    unsigned long started = jiffies;
    int result = wait_for_completion_timeout(&test->done, 500) ? 0 : -EIO;
    bool timed_out = result != 0;
    cancel_delayed_work_sync(&test->delayed);
    if (test->result || atomic_read(&test->active)) result = -EIO;
    if (result)
        kprintf("linuxkpi: bound test %s failed: timeout=%u ticks=%lu calls=%u reasons=0x%x active=%d expected_cpu=%u/%u nice=%d\n",
                stage, timed_out, jiffies - started, test->calls, test->failure_reasons,
                atomic_read(&test->active), test->expected_cpu[0], test->expected_cpu[1], test->expected_nice);
    return result;
}
int vinix_linuxkpi_bound_work_native_selftest(void)
{
    unsigned int cpus = min_t(unsigned int, vinix_linuxkpi_percpu_count(), 4);
    struct workqueue_struct *queues[4] = {0};
    struct native_bound_test tests[4], held[4][2], extra[4], spin, blocked, priority;
    struct native_bound_test *heap[16] = {0};
    int free_results[16] = {0};
    struct native_delayed_frees frees;
    bool held_initialized = false, heap_submitted = false;
    int result = 0;
    unsigned int failed_stages = 0;
    unsigned long heap_watchdog_ticks = 0, heap_final_ticks = 0;
    int heap_watchdog_count = -1, heap_final_count = -1;
    queues[0] = alloc_workqueue("vinix-bound", 0, 2);
    queues[1] = alloc_workqueue("vinix-bound-one", 0, 1);
    queues[2] = alloc_workqueue("vinix-unbound-high", WQ_UNBOUND | WQ_HIGHPRI, 2);
    queues[3] = alloc_workqueue("vinix-bound-high", WQ_HIGHPRI, 1);
    for (unsigned int q = 0; q < ARRAY_SIZE(queues); q++)
        if (!queues[q]) { result = -ENOMEM; failed_stages |= BIT(0); goto out; }
    /* Every online test CPU must remain the same across native sleep/yield. */
    for (unsigned int cpu = 0; cpu < cpus; cpu++) {
        native_bound_init(&tests[cpu], queues[0], cpu, false);
        BUG_ON(!queue_work_on(cpu, queues[0], &tests[cpu].delayed.work));
    }
    for (unsigned int cpu = 0; cpu < cpus; cpu++)
        if (native_bound_finish(&tests[cpu], "explicit routing") || tests[cpu].calls != 1)
            { result = -EIO; failed_stages |= BIT(1); }
    unsigned int caller_cpu = get_cpu();
    native_bound_init(&tests[0], queues[0], caller_cpu, false);
    if (!queue_work(queues[0], &tests[0].delayed.work)) { result = -EIO; failed_stages |= BIT(2); }
    put_cpu();
    if (native_bound_finish(&tests[0], "caller routing")) { result = -EIO; failed_stages |= BIT(2); }
    native_bound_init(&tests[0], queues[2], WORK_CPU_UNBOUND, true);
    BUG_ON(!queue_work(queues[2], &tests[0].delayed.work));
    if (native_bound_finish(&tests[0], "unbound high priority")) { result = -EIO; failed_stages |= BIT(3); }
    /* Delayed explicit routing persists despite the global timer worker. */
    native_bound_init(&tests[0], queues[0], cpus - 1, false);
    unsigned long irq_flags = vinix_linuxkpi_irq_save();
    if (!queue_delayed_work_on(0, queues[0], &tests[0].delayed, 100000) ||
        !mod_delayed_work_on(cpus - 1, queues[0], &tests[0].delayed, 2))
        { result = -EIO; failed_stages |= BIT(4); }
    vinix_linuxkpi_irq_restore(irq_flags);
    if (native_bound_finish(&tests[0], "delayed routing")) { result = -EIO; failed_stages |= BIT(4); }
    for (unsigned int migration = 0; migration < 2; migration++) {
        native_bound_init(&tests[0], queues[0], 0, false);
        tests[0].requeue_wq = queues[migration];
        tests[0].requeue_cpu = cpus - 1;
        tests[0].expected_cpu[1] = migration ? cpus - 1 : 0;
        BUG_ON(!queue_work_on(0, queues[0], &tests[0].delayed.work));
        if (native_bound_finish(&tests[0], migration ? "cross-owner requeue" : "same-owner requeue") ||
            tests[0].calls != 2) { result = -EIO; failed_stages |= BIT(5 + migration); }
    }
    native_bound_init(&tests[0], queues[0], 0, false);
    native_bound_init(&tests[1], queues[0], 0, false);
    tests[0].dependency = &tests[1];
    BUG_ON(!queue_work_on(0, queues[0], &tests[0].delayed.work));
    if (native_bound_finish(&tests[0], "nested dependency")) { result = -EIO; failed_stages |= BIT(7); }
    cancel_delayed_work_sync(&tests[1].delayed);
    if (tests[1].calls != 1 || tests[1].result) { result = -EIO; failed_stages |= BIT(7); }
    /* Sleeping callbacks retain active slots, independently on every CPU. */
    for (unsigned int cpu = 0; cpu < cpus; cpu++) {
        for (unsigned int slot = 0; slot < 2; slot++) {
            native_bound_init(&held[cpu][slot], queues[0], cpu, false);
            held[cpu][slot].hold = true;
        }
        native_bound_init(&extra[cpu], queues[0], cpu, false);
    }
    held_initialized = true;
    for (unsigned int cpu = 0; cpu < cpus; cpu++) {
        for (unsigned int slot = 0; slot < 2; slot++) {
            BUG_ON(!queue_work_on(cpu, queues[0], &held[cpu][slot].delayed.work));
            if (!wait_for_completion_timeout(&held[cpu][slot].entered, 500))
                { result = -EIO; failed_stages |= BIT(8); goto out; }
        }
        BUG_ON(!queue_work_on(cpu, queues[0], &extra[cpu].delayed.work));
    }
    msleep(2);
    for (unsigned int cpu = 0; cpu < cpus; cpu++) {
        if (READ_ONCE(extra[cpu].calls)) { result = -EIO; failed_stages |= BIT(8); }
        complete(&held[cpu][0].gate);
        if (native_bound_finish(&extra[cpu], "per-CPU deferred active"))
            { result = -EIO; failed_stages |= BIT(8); }
        complete(&held[cpu][1].gate);
        for (unsigned int slot = 0; slot < 2; slot++)
            if (native_bound_finish(&held[cpu][slot], "per-CPU held active"))
                { result = -EIO; failed_stages |= BIT(8); }
    }
    held_initialized = false;
    /* Normal bound owners share runnable concurrency; high priority uses a
     * separate domain. Only an actual sleep permits blocked normal work. */
    native_bound_init(&spin, queues[0], 0, false);
    native_bound_init(&blocked, queues[1], 0, false);
    native_bound_init(&priority, queues[3], 0, true);
    spin.spin = spin.hold = true;
    BUG_ON(!queue_work_on(0, queues[0], &spin.delayed.work));
    if (!wait_for_completion_timeout(&spin.entered, 500)) { result = -EIO; failed_stages |= BIT(9); }
    BUG_ON(!queue_work_on(0, queues[1], &blocked.delayed.work));
    BUG_ON(!queue_work_on(0, queues[3], &priority.delayed.work));
    if (native_bound_finish(&priority, "isolated priority domain")) { result = -EIO; failed_stages |= BIT(9); }
    if (READ_ONCE(blocked.calls)) { result = -EIO; failed_stages |= BIT(9); }
    __atomic_store_n(&spin.release_spin, true, __ATOMIC_RELEASE);
    if (native_bound_finish(&blocked, "normal domain after sleep")) { result = -EIO; failed_stages |= BIT(9); }
    complete(&spin.gate);
    if (native_bound_finish(&spin, "normal domain spinner")) { result = -EIO; failed_stages |= BIT(9); }
    /* Warm both permanent bound system queues on each CPU before allocation
     * measurement. Temporary self-freeing objects exercise detached records. */
    for (unsigned int cpu = 0; cpu < cpus; cpu++) {
        native_bound_init(&tests[cpu], system_wq, cpu, false);
        BUG_ON(!schedule_work_on(cpu, &tests[cpu].delayed.work));
    }
    for (unsigned int cpu = 0; cpu < cpus; cpu++)
        if (native_bound_finish(&tests[cpu], "system default")) { result = -EIO; failed_stages |= BIT(10); }
    for (unsigned int cpu = 0; cpu < cpus; cpu++) {
        native_bound_init(&tests[cpu], system_highpri_wq, cpu, true);
        BUG_ON(!queue_work_on(cpu, system_highpri_wq, &tests[cpu].delayed.work));
    }
    for (unsigned int cpu = 0; cpu < cpus; cpu++)
        if (native_bound_finish(&tests[cpu], "system high priority")) { result = -EIO; failed_stages |= BIT(11); }
    atomic_set(&frees.count, 0);
    init_completion(&frees.done);
    for (unsigned int i = 0; i < ARRAY_SIZE(heap); i++) {
        heap[i] = kzalloc(sizeof(*heap[i]), GFP_KERNEL);
        if (!heap[i]) { result = -ENOMEM; failed_stages |= BIT(12); goto out; }
        native_bound_init(heap[i], queues[0], i % cpus, false);
        heap[i]->frees = &frees;
        heap[i]->free_result = &free_results[i];
    }
    heap_submitted = true;
    for (unsigned int i = 0; i < ARRAY_SIZE(heap); i++)
        BUG_ON(!queue_work_on(i % cpus, queues[0], &heap[i]->delayed.work));
    unsigned long heap_started = jiffies;
    if (!wait_for_completion_timeout(&frees.done, 500)) {
        heap_watchdog_ticks = jiffies - heap_started;
        heap_watchdog_count = atomic_read(&frees.count);
        result = -EIO;
        failed_stages |= BIT(13);
        wait_for_completion(&frees.done);
    }
    flush_workqueue(queues[0]);
    heap_final_ticks = jiffies - heap_started;
    heap_final_count = atomic_read(&frees.count);
    if (heap_final_count != ARRAY_SIZE(heap)) { result = -EIO; failed_stages |= BIT(13); }
    for (unsigned int i = 0; i < ARRAY_SIZE(heap); i++)
        if (free_results[i]) { result = -EIO; failed_stages |= BIT(14); }
out:
    if (held_initialized)
        for (unsigned int cpu = 0; cpu < cpus; cpu++)
            for (unsigned int slot = 0; slot < 2; slot++) complete(&held[cpu][slot].gate);
    if (!heap_submitted)
        for (unsigned int i = 0; i < ARRAY_SIZE(heap); i++) kfree(heap[i]);
    for (unsigned int q = 0; q < ARRAY_SIZE(queues); q++)
        if (queues[q]) destroy_workqueue(queues[q]);
    if (result) {
        extern int kprintf(const char *, ...);
        kprintf("linuxkpi: bound native self-test failed stages=0x%x result=%d\n", failed_stages, result);
        if (failed_stages & BIT(13))
            kprintf("linuxkpi: bound self-free completion watchdog_ticks=%lu watchdog_count=%d final_ticks=%lu final_count=%d expected=%u\n",
                    heap_watchdog_ticks, heap_watchdog_count, heap_final_ticks,
                    heap_final_count, (unsigned int)ARRAY_SIZE(heap));
    }
    return result;
}

#endif
#endif
