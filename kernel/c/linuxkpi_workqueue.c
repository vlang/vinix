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
#ifdef VINIX_LINUXKPI_HOST_TEST
int vsnprintf(char *, size_t, const char *, va_list);
void vinix_linuxkpi_host_worker_enter(void);
void vinix_linuxkpi_host_worker_leave(void);
#else
#include <pthread.h>
int npf_vsnprintf(char *, size_t, const char *, va_list);
#endif

/* First workqueue backend: explicit ordered queues only. A dedicated native
 * worker guarantees FIFO execution even when a callback sleeps. Concurrent,
 * per-CPU, reclaim, priority, freezer and delayed-work APIs remain unresolved
 * or allocation fails; they must not silently inherit single-thread behavior.
 * The upstream work_struct layout and initialization macros are unchanged. */
struct workqueue_struct {
    struct list_head all;
    struct list_head pending;
    struct list_head sleepers;
    struct task_struct *task;
    pthread_t thread;
    struct completion ready;
    unsigned int drainers;
    bool stop, destroying;
    char name[32];
} __aligned(1UL << WORK_STRUCT_FLAG_BITS);

static DEFINE_RAW_SPINLOCK(work_lock);
static LIST_HEAD(running_works);
static LIST_HEAD(canceling_works);
static LIST_HEAD(all_queues);

struct work_wait {
    struct list_head entry;
    struct task_struct *task;
    bool done;
};
struct work_run {
    struct list_head entry, waiters;
    struct workqueue_struct *wq;
    struct work_struct *work;
    struct task_struct *task;
};
struct work_cancel {
    struct list_head entry;
    struct work_struct *work;
};

static struct work_run *running_locked(struct work_struct *work)
{
    struct work_run *run;
    list_for_each_entry(run, &running_works, entry)
        if (run->work == work) return run;
    return NULL;
}
static struct work_run *current_locked(void)
{
    struct work_run *run;
    struct task_struct *task = current;
    list_for_each_entry(run, &running_works, entry)
        if (run->task == task) return run;
    return NULL;
}
static bool canceling_locked(struct work_struct *work)
{
    struct work_cancel *cancel;
    list_for_each_entry(cancel, &canceling_works, entry)
        if (cancel->work == work) return true;
    return false;
}
static struct workqueue_struct *queued_locked(struct work_struct *work)
{
    unsigned long data = atomic_long_read(&work->data);
    return (data & WORK_STRUCT_PWQ) ?
        (void *)(data & WORK_STRUCT_WQ_DATA_MASK) : NULL;
}
static void mark_queued_locked(struct workqueue_struct *wq, struct work_struct *work)
{
    BUG_ON((unsigned long)wq & WORK_STRUCT_FLAG_MASK);
    atomic_long_set(&work->data, (unsigned long)wq | WORK_STRUCT_PENDING | WORK_STRUCT_PWQ);
}
static void wake_sleepers_locked(struct workqueue_struct *wq)
{
    struct work_wait *wait;
    list_for_each_entry(wait, &wq->sleepers, entry) wake_up_process(wait->task);
}
static bool detach_locked(struct work_struct *work)
{
    struct workqueue_struct *wq = queued_locked(work);
    if (!wq) return false;
    list_del_init(&work->entry);
    atomic_long_set(&work->data, WORK_STRUCT_NO_POOL);
    wake_up_process(wq->task);
    wake_sleepers_locked(wq);
    return true;
}

bool queue_work_on(int cpu, struct workqueue_struct *wq, struct work_struct *work)
{
    BUG_ON(!wq || !work->func);
    if (WARN_ON_ONCE(cpu != WORK_CPU_UNBOUND)) return false;
    unsigned long flags;
    raw_spin_lock_irqsave(&work_lock, flags);
    struct work_run *run = current_locked();
    if (work_pending(work) || canceling_locked(work) ||
        ((wq->drainers || wq->destroying) && (!run || run->wq != wq))) {
        raw_spin_unlock_irqrestore(&work_lock, flags);
        return false;
    }
    BUG_ON(wq->stop);
    mark_queued_locked(wq, work);
    list_add_tail(&work->entry, &wq->pending);
    wake_up_process(wq->task);
    raw_spin_unlock_irqrestore(&work_lock, flags);
    return true;
}

static void *ordered_worker(void *argument)
{
#ifdef VINIX_LINUXKPI_HOST_TEST
    vinix_linuxkpi_host_worker_enter();
#endif
    struct workqueue_struct *wq = argument;
    wq->task = get_task_struct(current); /* Owned until join and final exit. */
    complete(&wq->ready);
    unsigned long flags;
    for (;;) {
        struct work_run run = { .wq = wq, .task = current };
        INIT_LIST_HEAD(&run.waiters);
        raw_spin_lock_irqsave(&work_lock, flags);
        while (list_empty(&wq->pending) && !wq->stop) {
            set_current_state(TASK_UNINTERRUPTIBLE);
            raw_spin_unlock_irqrestore(&work_lock, flags);
            schedule();
            raw_spin_lock_irqsave(&work_lock, flags);
        }
        if (wq->stop) {
            raw_spin_unlock_irqrestore(&work_lock, flags);
            break;
        }
        struct work_struct *work = list_first_entry(&wq->pending, struct work_struct, entry);
        /* Requeueing onto another queue must never execute the same work
         * concurrently. Its original running record wakes us when finished. */
        if (running_locked(work)) {
            set_current_state(TASK_UNINTERRUPTIBLE);
            raw_spin_unlock_irqrestore(&work_lock, flags);
            schedule();
            continue;
        }
        work_func_t function = work->func;
        run.work = work;
        detach_locked(work);
        list_add_tail(&run.entry, &running_works);
        raw_spin_unlock_irqrestore(&work_lock, flags);
        function(work); /* Sleeping and self-freeing callbacks are supported. */
        BUG_ON(!vinix_linuxkpi_may_sleep() || !task_is_running(current));
        raw_spin_lock_irqsave(&work_lock, flags);
        /* Never dereference work after its callback: it may have freed itself.
         * Stack records and stack waiters are detached under the same lock. */
        struct work_wait *wait, *next;
        list_for_each_entry_safe(wait, next, &run.waiters, entry) {
            list_del_init(&wait->entry);
            wait->done = true;
            wake_up_process(wait->task);
        }
        list_del_init(&run.entry);
        wake_sleepers_locked(wq);
        /* A requeued item may now belong to a different ordered worker. */
        struct list_head *entry;
        list_for_each(entry, &all_queues) {
            struct workqueue_struct *other = list_entry(entry, struct workqueue_struct, all);
            wake_up_process(other->task);
        }
        raw_spin_unlock_irqrestore(&work_lock, flags);
    }
#ifdef VINIX_LINUXKPI_HOST_TEST
    vinix_linuxkpi_host_worker_leave();
#else
    pthread_exit(NULL);
#endif
    return NULL;
}

struct workqueue_struct *alloc_workqueue(const char *fmt, unsigned int flags, int max_active, ...)
{
    const unsigned int supported = WQ_UNBOUND | __WQ_ORDERED | __WQ_ORDERED_EXPLICIT;
    if ((flags & ~supported) || !(flags & WQ_UNBOUND) ||
        !(flags & __WQ_ORDERED) || max_active != 1) return NULL;
    might_sleep();
    struct workqueue_struct *wq = kzalloc(sizeof(*wq), GFP_KERNEL);
    if (!wq) return NULL;
    INIT_LIST_HEAD(&wq->pending);
    INIT_LIST_HEAD(&wq->sleepers);
    init_completion(&wq->ready);
    va_list arguments;
    va_start(arguments, max_active);
#ifdef VINIX_LINUXKPI_HOST_TEST
    vsnprintf(wq->name, sizeof(wq->name), fmt, arguments);
#else
    npf_vsnprintf(wq->name, sizeof(wq->name), fmt, arguments);
#endif
    va_end(arguments);
    if (pthread_create(&wq->thread, NULL, ordered_worker, wq)) {
        kfree(wq);
        return NULL;
    }
    wait_for_completion(&wq->ready);
    unsigned long irq_flags;
    raw_spin_lock_irqsave(&work_lock, irq_flags);
    list_add_tail(&wq->all, &all_queues);
    raw_spin_unlock_irqrestore(&work_lock, irq_flags);
    return wq;
}

static void attach_running_locked(struct work_run *run, struct work_wait *wait)
{
    *wait = (struct work_wait){ .task = current, .done = !run };
    INIT_LIST_HEAD(&wait->entry);
    if (run) {
        BUG_ON(run->task == current);
        list_add_tail(&wait->entry, &run->waiters);
    }
}
static void wait_attached_locked(struct work_wait *wait, unsigned long *flags)
{
    while (!wait->done) {
        set_current_state(TASK_UNINTERRUPTIBLE);
        raw_spin_unlock_irqrestore(&work_lock, *flags);
        schedule();
        raw_spin_lock_irqsave(&work_lock, *flags);
    }
    BUG_ON(!list_empty(&wait->entry));
}
static void wait_running_locked(struct work_run *run, unsigned long *flags)
{
    struct work_wait wait;
    attach_running_locked(run, &wait);
    wait_attached_locked(&wait, flags);
}

bool cancel_work(struct work_struct *work)
{
    unsigned long flags;
    raw_spin_lock_irqsave(&work_lock, flags);
    bool pending = detach_locked(work);
    raw_spin_unlock_irqrestore(&work_lock, flags);
    return pending;
}

bool cancel_work_sync(struct work_struct *work)
{
    might_sleep();
    struct work_cancel cancel = { .work = work };
    unsigned long flags;
    raw_spin_lock_irqsave(&work_lock, flags);
    bool pending = detach_locked(work);
    list_add_tail(&cancel.entry, &canceling_works);
    atomic_long_set(&work->data, WORK_STRUCT_NO_POOL | WORK_STRUCT_PENDING | WORK_OFFQ_CANCELING);
    wait_running_locked(running_locked(work), &flags);
    list_del_init(&cancel.entry);
    if (!canceling_locked(work)) atomic_long_set(&work->data, WORK_STRUCT_NO_POOL);
    raw_spin_unlock_irqrestore(&work_lock, flags);
    return pending;
}

struct work_barrier { struct work_struct work; struct completion done; };
static void barrier_callback(struct work_struct *work)
{
    struct work_barrier *barrier = container_of(work, struct work_barrier, work);
    complete(&barrier->done);
}
static void init_barrier(struct work_barrier *barrier)
{
    INIT_WORK_ONSTACK(&barrier->work, barrier_callback);
    init_completion(&barrier->done);
}

bool flush_work(struct work_struct *work)
{
    might_sleep();
    struct work_barrier barrier;
    init_barrier(&barrier);
    unsigned long flags;
    raw_spin_lock_irqsave(&work_lock, flags);
    struct workqueue_struct *wq = queued_locked(work);
    if (wq) {
        BUG_ON(wq->task == current);
        /* A prior instance can still run on another queue. If the queued
         * instance is canceled, its barrier alone does not wait for that
         * callback; retain a separate stack waiter on its running record. */
        struct work_wait running;
        attach_running_locked(running_locked(work), &running);
        mark_queued_locked(wq, &barrier.work);
        list_add(&barrier.work.entry, &work->entry);
        wake_up_process(wq->task);
        raw_spin_unlock_irqrestore(&work_lock, flags);
        wait_for_completion(&barrier.done);
        raw_spin_lock_irqsave(&work_lock, flags);
        wait_attached_locked(&running, &flags);
        raw_spin_unlock_irqrestore(&work_lock, flags);
        destroy_work_on_stack(&barrier.work);
        return true;
    }
    struct work_run *run = running_locked(work);
    bool busy = !!run;
    wait_running_locked(run, &flags);
    raw_spin_unlock_irqrestore(&work_lock, flags);
    return busy;
}

void __flush_workqueue(struct workqueue_struct *wq)
{
    might_sleep();
    struct work_barrier barrier;
    init_barrier(&barrier);
    unsigned long flags;
    raw_spin_lock_irqsave(&work_lock, flags);
    BUG_ON(wq->task == current || wq->stop);
    mark_queued_locked(wq, &barrier.work);
    list_add_tail(&barrier.work.entry, &wq->pending);
    wake_up_process(wq->task);
    raw_spin_unlock_irqrestore(&work_lock, flags);
    wait_for_completion(&barrier.done);
    destroy_work_on_stack(&barrier.work);
}

static bool active_locked(struct workqueue_struct *wq)
{
    if (!list_empty(&wq->pending)) return true;
    struct work_run *run;
    list_for_each_entry(run, &running_works, entry)
        if (run->wq == wq) return true;
    return false;
}
static void drain_locked(struct workqueue_struct *wq, unsigned long *flags)
{
    BUG_ON(wq->task == current);
    struct work_wait wait = { .task = current };
    list_add_tail(&wait.entry, &wq->sleepers);
    wq->drainers++;
    while (active_locked(wq)) {
        set_current_state(TASK_UNINTERRUPTIBLE);
        raw_spin_unlock_irqrestore(&work_lock, *flags);
        schedule();
        raw_spin_lock_irqsave(&work_lock, *flags);
    }
    wq->drainers--;
    list_del_init(&wait.entry);
}
void drain_workqueue(struct workqueue_struct *wq)
{
    might_sleep();
    unsigned long flags;
    raw_spin_lock_irqsave(&work_lock, flags);
    drain_locked(wq, &flags);
    raw_spin_unlock_irqrestore(&work_lock, flags);
}
void destroy_workqueue(struct workqueue_struct *wq)
{
    might_sleep();
    unsigned long flags;
    raw_spin_lock_irqsave(&work_lock, flags);
    BUG_ON(wq->destroying);
    wq->destroying = true;
    drain_locked(wq, &flags);
    BUG_ON(!list_empty(&wq->sleepers));
    wq->stop = true;
    list_del_init(&wq->all);
    wake_up_process(wq->task);
    raw_spin_unlock_irqrestore(&work_lock, flags);
    BUG_ON(pthread_join(wq->thread, NULL));
    while (__atomic_load_n(&wq->task->__state, __ATOMIC_ACQUIRE) != TASK_DEAD) cond_resched();
    put_task_struct(wq->task);
    kfree(wq);
}

struct work_struct *current_work(void)
{
    unsigned long flags;
    raw_spin_lock_irqsave(&work_lock, flags);
    struct work_run *run = current_locked();
    struct work_struct *work = run ? run->work : NULL;
    raw_spin_unlock_irqrestore(&work_lock, flags);
    return work;
}
unsigned int work_busy(struct work_struct *work)
{
    unsigned long flags;
    raw_spin_lock_irqsave(&work_lock, flags);
    unsigned int busy = work_pending(work) ? WORK_BUSY_PENDING : 0;
    if (running_locked(work)) busy |= WORK_BUSY_RUNNING;
    raw_spin_unlock_irqrestore(&work_lock, flags);
    return busy;
}

#ifndef VINIX_LINUXKPI_HOST_TEST
#include <linux/delay.h>
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
#endif
#endif
