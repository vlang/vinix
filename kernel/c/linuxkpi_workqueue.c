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
void vinix_linuxkpi_host_pool_publish_gate(struct workqueue_struct *wq);
#else
#include <pthread.h>
int npf_vsnprintf(char *, size_t, const char *, va_list);
#endif

/* Ordered queues retain one worker; unbound queues grow a private pool on
 * demand. CPU-bound queues, reclaim, priority, freezer and RCU-work APIs stay
 * unsupported. The upstream work/timer layouts and macros are unchanged. */
struct native_worker;
struct workqueue_struct {
    struct list_head all;
    struct list_head pending;
    struct list_head delayed;
    struct list_head sleepers;
    struct list_head workers;
    struct native_worker *manager;
    u64 sequence, generation;
    unsigned int drainers, nr_workers, nr_running, max_active;
    bool stop, destroying, ordered, system;
    char name[32];
} __aligned(1UL << WORK_STRUCT_FLAG_BITS);

struct native_worker {
    struct list_head entry;
    struct workqueue_struct *wq;
    struct task_struct *task;
    pthread_t thread;
    struct completion ready;
};
struct workqueue_struct *system_unbound_wq;

struct work_barrier {
    struct work_struct work;
    struct work_struct *target;
    u64 sequence, generation;
    bool captured, queue;
};
static void barrier_callback(struct work_struct *work);

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
    u64 sequence, generation;
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
    return (data & (WORK_STRUCT_PWQ | WORK_STRUCT_INACTIVE)) == WORK_STRUCT_PWQ ?
        (void *)(data & WORK_STRUCT_WQ_DATA_MASK) : NULL;
}
/* INACTIVE distinguishes a timer reservation from executable work. Both use
 * the original entry/data fields, without an allocation for each timer arm. */
static struct workqueue_struct *delayed_locked(struct work_struct *work)
{
    unsigned long data = atomic_long_read(&work->data);
    return (data & (WORK_STRUCT_PWQ | WORK_STRUCT_INACTIVE)) ==
        (WORK_STRUCT_PWQ | WORK_STRUCT_INACTIVE) ?
        (void *)(data & WORK_STRUCT_WQ_DATA_MASK) : NULL;
}
static void mark_data_locked(struct workqueue_struct *wq, struct work_struct *work,
                             bool inactive)
{
    BUG_ON((unsigned long)wq & WORK_STRUCT_FLAG_MASK);
    atomic_long_set(&work->data, (unsigned long)wq | WORK_STRUCT_PENDING | WORK_STRUCT_PWQ |
                    (inactive ? WORK_STRUCT_INACTIVE : 0));
}
static void mark_queued_locked(struct workqueue_struct *wq, struct work_struct *work)
{ mark_data_locked(wq, work, false); }
static void wake_workers_locked(struct workqueue_struct *wq)
{
    struct native_worker *worker;
    list_for_each_entry(worker, &wq->workers, entry) wake_up_process(worker->task);
    if (wq->manager) wake_up_process(wq->manager->task);
}
static void wake_sleepers_locked(struct workqueue_struct *wq)
{
    struct work_wait *wait;
    list_for_each_entry(wait, &wq->sleepers, entry) wake_up_process(wait->task);
}
static void capture_markers_locked(struct workqueue_struct *wq);
static bool detach_locked(struct work_struct *work)
{
    struct workqueue_struct *wq = queued_locked(work);
    if (!wq) return false;
    list_del_init(&work->entry);
    atomic_long_set(&work->data, WORK_STRUCT_NO_POOL);
    capture_markers_locked(wq);
    wake_workers_locked(wq);
    wake_sleepers_locked(wq);
    return true;
}

static bool accepting_locked(struct workqueue_struct *wq)
{
    BUG_ON(wq->stop);
    if (!wq->drainers && !wq->destroying) return true;
    struct work_run *run = current_locked();
    return run && run->wq == wq;
}
bool queue_work_on(int cpu, struct workqueue_struct *wq, struct work_struct *work)
{
    BUG_ON(!wq || !work->func);
    if (WARN_ON_ONCE(cpu != WORK_CPU_UNBOUND)) return false;
    unsigned long flags;
    raw_spin_lock_irqsave(&work_lock, flags);
    if (work_pending(work) || canceling_locked(work) ||
        !accepting_locked(wq)) {
        raw_spin_unlock_irqrestore(&work_lock, flags);
        return false;
    }
    mark_queued_locked(wq, work);
    list_add_tail(&work->entry, &wq->pending);
    wake_workers_locked(wq);
    raw_spin_unlock_irqrestore(&work_lock, flags);
    return true;
}

static void promote_delayed_locked(struct delayed_work *dwork)
{
    struct work_struct *work = &dwork->work;
    struct workqueue_struct *wq = delayed_locked(work);
    if (!wq) return;
    list_del_init(&work->entry);
    mark_queued_locked(wq, work);
    list_add_tail(&work->entry, &wq->pending);
    wake_workers_locked(wq);
}
void delayed_work_timer_fn(struct timer_list *timer)
{
    struct delayed_work *dwork = from_timer(dwork, timer, timer);
#ifdef VINIX_LINUXKPI_HOST_TEST
    vinix_linuxkpi_host_delayed_timer_gate(timer);
#endif
    BUG_ON(vinix_linuxkpi_irq_flags() & (1UL << 9));
    unsigned long flags;
    raw_spin_lock_irqsave(&work_lock, flags);
    promote_delayed_locked(dwork);
    raw_spin_unlock_irqrestore(&work_lock, flags);
    /* An executable work callback may free the enclosing delayed_work as
     * soon as we release work_lock. Never access dwork or timer afterward. */
}
static void arm_delayed_locked(int cpu, struct workqueue_struct *wq,
                               struct delayed_work *dwork, unsigned long delay)
{
    BUG_ON(dwork->timer.function != delayed_work_timer_fn ||
           dwork->timer.flags != TIMER_IRQSAFE);
    dwork->wq = wq;
    dwork->cpu = cpu;
    mark_data_locked(wq, &dwork->work, delay != 0);
    if (!delay) {
        list_add_tail(&dwork->work.entry, &wq->pending);
        wake_workers_locked(wq);
        return;
    }
    list_add_tail(&dwork->work.entry, &wq->delayed);
    BUG_ON(mod_timer(&dwork->timer, jiffies + delay));
}
bool queue_delayed_work_on(int cpu, struct workqueue_struct *wq,
                           struct delayed_work *dwork, unsigned long delay)
{
    BUG_ON(!wq || !dwork->work.func);
    if (WARN_ON_ONCE(cpu != WORK_CPU_UNBOUND)) return false;
    unsigned long flags;
    raw_spin_lock_irqsave(&work_lock, flags);
    bool accepted = !work_pending(&dwork->work) &&
        !canceling_locked(&dwork->work) && accepting_locked(wq);
    if (accepted) arm_delayed_locked(cpu, wq, dwork, delay);
    raw_spin_unlock_irqrestore(&work_lock, flags);
    return accepted;
}
/* work_lock -> timer_lock is the only nested order. A timer callback never
 * holds timer_lock while taking work_lock. If its transfer is in flight, drop
 * work_lock before retrying; IRQ-off/atomic callers cannot sleep here. */
static int grab_delayed_locked(struct delayed_work *dwork)
{
    if (canceling_locked(&dwork->work)) return -ENOENT;
    struct workqueue_struct *wq = delayed_locked(&dwork->work);
    if (!wq) return detach_locked(&dwork->work);
    int result = try_to_del_timer_sync(&dwork->timer);
    if (result < 0) return -EAGAIN;
    BUG_ON(!result);
    list_del_init(&dwork->work.entry);
    atomic_long_set(&dwork->work.data, WORK_STRUCT_NO_POOL);
    return 1;
}
static int grab_delayed_retry_locked(struct delayed_work *dwork, unsigned long *flags)
{
    int result;
    while ((result = grab_delayed_locked(dwork)) == -EAGAIN) {
        raw_spin_unlock_irqrestore(&work_lock, *flags);
        vinix_linuxkpi_spin_wait();
        cond_resched();
        raw_spin_lock_irqsave(&work_lock, *flags);
    }
    return result;
}
bool mod_delayed_work_on(int cpu, struct workqueue_struct *wq,
                         struct delayed_work *dwork, unsigned long delay)
{
    BUG_ON(!wq || !dwork->work.func);
    if (WARN_ON_ONCE(cpu != WORK_CPU_UNBOUND)) return false;
    unsigned long flags;
    raw_spin_lock_irqsave(&work_lock, flags);
    bool pending = true;
    if (!canceling_locked(&dwork->work) && accepting_locked(wq)) {
        int grabbed = grab_delayed_retry_locked(dwork, &flags);
        pending = grabbed != 0;
        /* A concurrent synchronous canceller can claim it during a retry. */
        if (grabbed >= 0 && !canceling_locked(&dwork->work) && accepting_locked(wq))
            arm_delayed_locked(cpu, wq, dwork, delay);
    }
    raw_spin_unlock_irqrestore(&work_lock, flags);
    return pending;
}
bool cancel_delayed_work(struct delayed_work *dwork)
{
    unsigned long flags;
    raw_spin_lock_irqsave(&work_lock, flags);
    bool pending = grab_delayed_retry_locked(dwork, &flags) > 0;
    raw_spin_unlock_irqrestore(&work_lock, flags);
    return pending;
}

/* Flush snapshots are stack markers in the original pending list. They
 * never consume a worker or an active slot. Work behind a queue marker belongs
 * to its next generation, even if an older blocked item has not started yet.
 * Thus overlapping flushes can wait independent boundaries without a color
 * limit, allocation on enqueue, or blocking later work needed for progress. */
static bool target_pending_before_locked(struct workqueue_struct *wq,
                                         struct work_barrier *barrier)
{
    struct list_head *entry;
    list_for_each(entry, &wq->pending) {
        if (entry == &barrier->work.entry) break;
        if (list_entry(entry, struct work_struct, entry) == barrier->target) return true;
    }
    return false;
}
static void capture_markers_locked(struct workqueue_struct *wq)
{
    struct work_struct *work;
    list_for_each_entry(work, &wq->pending, entry) {
        if (work->func != barrier_callback) continue;
        struct work_barrier *barrier = container_of(work, struct work_barrier, work);
        if (!barrier->queue && !barrier->captured && !target_pending_before_locked(wq, barrier)) {
            barrier->sequence = wq->sequence;
            barrier->captured = true;
        }
    }
}
static struct work_struct *select_work_locked(struct workqueue_struct *wq, u64 *generation)
{
    u64 epoch = wq->generation;
    struct work_struct *work;
    list_for_each_entry(work, &wq->pending, entry) {
        if (work->func != barrier_callback) continue;
        struct work_barrier *barrier = container_of(work, struct work_barrier, work);
        if (barrier->queue) { epoch = barrier->generation; break; }
    }
    list_for_each_entry(work, &wq->pending, entry) {
        if (work->func == barrier_callback) {
            struct work_barrier *barrier = container_of(work, struct work_barrier, work);
            if (wq->ordered) return NULL;
            if (barrier->queue) epoch = barrier->generation + 1;
            continue;
        }
        if (!running_locked(work)) {
            if (generation) *generation = epoch;
            return work;
        }
        if (wq->ordered) return NULL;
    }
    return NULL;
}
static bool marker_ready_locked(struct workqueue_struct *wq, struct work_barrier *barrier)
{
    if (barrier->queue) {
        if (wq->pending.next != &barrier->work.entry) return false;
        struct work_run *run;
        list_for_each_entry(run, &running_works, entry)
            if (run->wq == wq && run->generation <= barrier->generation) return false;
        return true;
    }
    if (!barrier->captured) return false;
    struct work_run *run = running_locked(barrier->target);
    return !run || run->wq != wq || run->sequence > barrier->sequence;
}
static void wait_marker_locked(struct workqueue_struct *wq, struct work_barrier *barrier,
                                unsigned long *flags)
{
    struct work_wait wait = { .task = current };
    list_add_tail(&wait.entry, &wq->sleepers);
    while (!marker_ready_locked(wq, barrier)) {
        set_current_state(TASK_UNINTERRUPTIBLE);
        raw_spin_unlock_irqrestore(&work_lock, *flags);
        schedule();
        raw_spin_lock_irqsave(&work_lock, *flags);
    }
    list_del_init(&wait.entry);
    BUG_ON(!detach_locked(&barrier->work));
}
static void worker_enter(struct native_worker *worker)
{
#ifdef VINIX_LINUXKPI_HOST_TEST
    vinix_linuxkpi_host_worker_enter();
#endif
    worker->task = get_task_struct(current); /* Owned until join and final exit. */
    complete(&worker->ready);
}
static void worker_leave(void)
{
#ifdef VINIX_LINUXKPI_HOST_TEST
    vinix_linuxkpi_host_worker_leave();
#else
    pthread_exit(NULL);
#endif
}
static void *work_worker(void *argument)
{
    struct native_worker *worker = argument;
    struct workqueue_struct *wq = worker->wq;
    worker_enter(worker);
    unsigned long flags;
    for (;;) {
        struct work_run run = { .wq = wq, .task = current };
        INIT_LIST_HEAD(&run.waiters);
        raw_spin_lock_irqsave(&work_lock, flags);
        struct work_struct *work;
        while (!(work = select_work_locked(wq, &run.generation)) && !wq->stop) {
            set_current_state(TASK_UNINTERRUPTIBLE);
            raw_spin_unlock_irqrestore(&work_lock, flags);
            schedule();
            raw_spin_lock_irqsave(&work_lock, flags);
        }
        if (wq->stop) {
            raw_spin_unlock_irqrestore(&work_lock, flags);
            break;
        }
        work_func_t function = work->func;
        run.work = work;
        BUG_ON(++wq->sequence == 0);
        run.sequence = wq->sequence;
        detach_locked(work);
        wq->nr_running++;
        list_add_tail(&run.entry, &running_works);
        wake_workers_locked(wq);
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
        BUG_ON(!wq->nr_running);
        wq->nr_running--;
        wake_sleepers_locked(wq);
        /* A requeued item may now belong to a different worker pool. */
        struct list_head *entry;
        list_for_each(entry, &all_queues) {
            struct workqueue_struct *other = list_entry(entry, struct workqueue_struct, all);
            wake_workers_locked(other);
        }
        raw_spin_unlock_irqrestore(&work_lock, flags);
    }
    worker_leave();
    return NULL;
}
static struct native_worker *start_worker(struct workqueue_struct *wq,
                                          void *(*function)(void *))
{
    struct native_worker *worker = kzalloc(sizeof(*worker), GFP_KERNEL);
    if (!worker) return NULL;
    worker->wq = wq;
    init_completion(&worker->ready);
    if (pthread_create(&worker->thread, NULL, function, worker)) {
        kfree(worker);
        return NULL;
    }
    wait_for_completion(&worker->ready);
    return worker;
}
static void join_worker(struct native_worker *worker)
{
    BUG_ON(pthread_join(worker->thread, NULL));
    while (__atomic_load_n(&worker->task->__state, __ATOMIC_ACQUIRE) != TASK_DEAD) cond_resched();
    put_task_struct(worker->task);
    kfree(worker);
}
static void *pool_manager(void *argument)
{
    struct native_worker *manager = argument;
    struct workqueue_struct *wq = manager->wq;
    worker_enter(manager);
    unsigned long flags;
    for (;;) {
        raw_spin_lock_irqsave(&work_lock, flags);
        while (!wq->stop && (wq->nr_workers >= wq->max_active ||
               wq->nr_running < wq->nr_workers || !select_work_locked(wq, NULL))) {
            set_current_state(TASK_UNINTERRUPTIBLE);
            raw_spin_unlock_irqrestore(&work_lock, flags);
            schedule();
            raw_spin_lock_irqsave(&work_lock, flags);
        }
        bool stop = wq->stop;
        raw_spin_unlock_irqrestore(&work_lock, flags);
        if (stop) break;
        /* Only this manager grows its pool. Allocation/thread creation happen
         * with IRQs enabled, never on the atomic producer's enqueue path. */
        struct native_worker *worker = start_worker(wq, work_worker);
        if (!worker) { msleep(1); continue; }
#ifdef VINIX_LINUXKPI_HOST_TEST
        vinix_linuxkpi_host_pool_publish_gate(wq);
#endif
        raw_spin_lock_irqsave(&work_lock, flags);
        list_add_tail(&worker->entry, &wq->workers);
        wq->nr_workers++;
        wake_workers_locked(wq);
        raw_spin_unlock_irqrestore(&work_lock, flags);
    }
    worker_leave();
    return NULL;
}

struct workqueue_struct *alloc_workqueue(const char *fmt, unsigned int flags, int max_active, ...)
{
    const unsigned int supported = WQ_UNBOUND | __WQ_ORDERED | __WQ_ORDERED_EXPLICIT;
    bool ordered = flags & __WQ_ORDERED;
    if ((flags & ~supported) || !(flags & WQ_UNBOUND) ||
        (ordered && max_active != 1) || max_active < 0 ||
        (!ordered && (flags & __WQ_ORDERED_EXPLICIT))) return NULL;
    if (!max_active) max_active = WQ_DFL_ACTIVE;
    if (max_active > WQ_UNBOUND_MAX_ACTIVE) {
        WARN_ON_ONCE(true);
        max_active = WQ_UNBOUND_MAX_ACTIVE;
    }
    might_sleep();
    struct workqueue_struct *wq = kzalloc(sizeof(*wq), GFP_KERNEL);
    if (!wq) return NULL;
    INIT_LIST_HEAD(&wq->all);
    INIT_LIST_HEAD(&wq->pending);
    INIT_LIST_HEAD(&wq->delayed);
    INIT_LIST_HEAD(&wq->sleepers);
    INIT_LIST_HEAD(&wq->workers);
    wq->max_active = max_active;
    wq->ordered = ordered;
    va_list arguments;
    va_start(arguments, max_active);
#ifdef VINIX_LINUXKPI_HOST_TEST
    vsnprintf(wq->name, sizeof(wq->name), fmt, arguments);
#else
    npf_vsnprintf(wq->name, sizeof(wq->name), fmt, arguments);
#endif
    va_end(arguments);
    struct native_worker *worker = start_worker(wq, work_worker);
    if (!worker) { kfree(wq); return NULL; }
    list_add_tail(&worker->entry, &wq->workers);
    wq->nr_workers = 1;
    if (!ordered && max_active > 1) {
        wq->manager = start_worker(wq, pool_manager);
        if (!wq->manager) { destroy_workqueue(wq); return NULL; }
    }
    unsigned long irq_flags;
    raw_spin_lock_irqsave(&work_lock, irq_flags);
    list_add_tail(&wq->all, &all_queues);
    raw_spin_unlock_irqrestore(&work_lock, irq_flags);
    return wq;
}

int vinix_linuxkpi_workqueue_bootstrap(void)
{
    if (system_unbound_wq) return 0; /* Serialized boot initialization. */
    system_unbound_wq = alloc_workqueue("events_unbound", WQ_UNBOUND, 0);
    if (!system_unbound_wq) return -ENOMEM;
    system_unbound_wq->system = true;
    return 0;
}
#ifdef VINIX_LINUXKPI_HOST_TEST
bool vinix_linuxkpi_host_workqueue_stopped(struct workqueue_struct *wq)
{
    unsigned long flags;
    raw_spin_lock_irqsave(&work_lock, flags);
    bool stop = wq->stop;
    raw_spin_unlock_irqrestore(&work_lock, flags);
    return stop;
}
void vinix_linuxkpi_workqueue_shutdown_for_test(void)
{
    struct workqueue_struct *wq = system_unbound_wq;
    system_unbound_wq = NULL;
    if (wq) { wq->system = false; destroy_workqueue(wq); }
}
#endif

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

static bool cancel_sync(struct work_struct *work, struct delayed_work *dwork)
{
    might_sleep();
    struct work_cancel cancel = { .work = work };
    unsigned long flags;
    raw_spin_lock_irqsave(&work_lock, flags);
    BUG_ON(!dwork && delayed_locked(work));
    bool pending = dwork ? grab_delayed_retry_locked(dwork, &flags) > 0 : detach_locked(work);
    list_add_tail(&cancel.entry, &canceling_works);
    atomic_long_set(&work->data, WORK_STRUCT_NO_POOL | WORK_STRUCT_PENDING | WORK_OFFQ_CANCELING);
    if (dwork) {
        raw_spin_unlock_irqrestore(&work_lock, flags);
        /* The guard prevents rearming while the old timer callback finishes.
         * Never wait for it under work_lock: it needs that lock to return. */
        timer_delete_sync(&dwork->timer);
        raw_spin_lock_irqsave(&work_lock, flags);
    }
    wait_running_locked(running_locked(work), &flags);
    list_del_init(&cancel.entry);
    if (!canceling_locked(work)) atomic_long_set(&work->data, WORK_STRUCT_NO_POOL);
    raw_spin_unlock_irqrestore(&work_lock, flags);
    return pending;
}
bool cancel_work_sync(struct work_struct *work) { return cancel_sync(work, NULL); }
bool cancel_delayed_work_sync(struct delayed_work *dwork) { return cancel_sync(&dwork->work, dwork); }

static void barrier_callback(struct work_struct *work)
{
    BUG_ON(true); /* Markers are detached by their waiting task, never executed. */
}
static void init_barrier(struct work_barrier *barrier)
{
    INIT_WORK_ONSTACK(&barrier->work, barrier_callback);
    barrier->captured = false;
    barrier->queue = false;
}

static bool flush_work_common(struct work_struct *work, struct delayed_work *dwork)
{
    might_sleep();
    struct work_barrier barrier;
    init_barrier(&barrier);
    unsigned long flags;
    raw_spin_lock_irqsave(&work_lock, flags);
    if (dwork) {
        /* Cancel only a still-reserved timer. Conversion and flush snapshot
         * stay under work_lock, so rearming cannot strand a new reservation. */
        while (delayed_locked(work)) {
            int result = try_to_del_timer_sync(&dwork->timer);
            if (result >= 0) {
                BUG_ON(!result);
                promote_delayed_locked(dwork);
                break;
            }
            raw_spin_unlock_irqrestore(&work_lock, flags);
            vinix_linuxkpi_spin_wait();
            cond_resched();
            raw_spin_lock_irqsave(&work_lock, flags);
        }
    }
    struct workqueue_struct *wq = queued_locked(work);
    if (wq) {
        struct work_run *caller = current_locked();
        BUG_ON(caller && caller->wq == wq && (wq->ordered || wq->max_active == 1));
        /* A prior instance can still run on another queue. If the queued
         * instance is canceled, its barrier alone does not wait for that
         * callback; retain a separate stack waiter on its running record. */
        struct work_wait running;
        attach_running_locked(running_locked(work), &running);
        barrier.target = work;
        mark_queued_locked(wq, &barrier.work);
        list_add(&barrier.work.entry, &work->entry);
        wake_workers_locked(wq);
        wait_marker_locked(wq, &barrier, &flags);
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
bool flush_work(struct work_struct *work) { return flush_work_common(work, NULL); }
bool flush_delayed_work(struct delayed_work *dwork) { return flush_work_common(&dwork->work, dwork); }

void __flush_workqueue(struct workqueue_struct *wq)
{
    might_sleep();
    struct work_barrier barrier;
    init_barrier(&barrier);
    barrier.queue = true;
    unsigned long flags;
    raw_spin_lock_irqsave(&work_lock, flags);
    struct work_run *caller = current_locked();
    BUG_ON((caller && caller->wq == wq) || wq->stop);
    barrier.generation = wq->generation;
    BUG_ON(++wq->generation == 0);
    mark_queued_locked(wq, &barrier.work);
    list_add_tail(&barrier.work.entry, &wq->pending);
    wait_marker_locked(wq, &barrier, &flags);
    raw_spin_unlock_irqrestore(&work_lock, flags);
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
    struct work_run *caller = current_locked();
    BUG_ON(caller && caller->wq == wq);
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
    BUG_ON(wq->destroying || wq->system);
    /* Linux requires owners to cancel delayed timers before queue teardown.
     * Queue flushing/draining intentionally ignores unexpired reservations. */
    BUG_ON(!list_empty(&wq->delayed));
    wq->destroying = true;
    drain_locked(wq, &flags);
    BUG_ON(!list_empty(&wq->delayed));
    BUG_ON(!list_empty(&wq->sleepers));
    wq->stop = true;
    list_del_init(&wq->all);
    wake_workers_locked(wq);
    raw_spin_unlock_irqrestore(&work_lock, flags);
    /* The manager may still be publishing a newly created worker. Join it
     * before traversing the final worker list or freeing the queue. */
    if (wq->manager) join_worker(wq->manager);
    struct native_worker *worker, *next;
    list_for_each_entry_safe(worker, next, &wq->workers, entry) {
        list_del_init(&worker->entry);
        join_worker(worker);
    }
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
    unsigned int calls, limit;
    int result;
    int *free_result;
    bool hold;
};
static void native_parallel_callback(struct work_struct *work)
{
    struct native_parallel_test *test = container_of(work, struct native_parallel_test, work);
    if (!vinix_linuxkpi_may_sleep() || current_work() != work ||
        atomic_inc_return(&test->active) != 1) test->result = -EIO;
    test->calls++;
    if (test->hold) {
        complete(&test->entered);
        wait_for_completion(&test->gate);
    }
    msleep(1);
    if (test->target) {
        if (!queue_work(test->wq, &test->target->work)) test->result = -EIO;
        flush_work(&test->target->work);
        if (test->target->calls != 1 || atomic_read(&test->target->active)) test->result = -EIO;
    }
    if (test->calls < test->limit && !queue_work(test->wq, work)) test->result = -EIO;
    if (atomic_dec_return(&test->active)) test->result = -EIO;
    if (test->frees) {
        struct native_delayed_frees *frees = test->frees;
        *test->free_result = test->result;
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
    const unsigned int limit[3] = {2, 4, 8};
    bool held_submitted = false, heap_submitted = false;
    queues[0] = alloc_workqueue("vinix-parallel-2", WQ_UNBOUND, 2);
    queues[1] = alloc_workqueue("vinix-parallel-4", WQ_UNBOUND, 4);
    queues[2] = system_unbound_wq;
    if (!queues[0] || !queues[1] || !queues[2]) { result = -ENOMEM; goto out; }
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
        for (unsigned int i = 0; i < limit[q]; i++)
            if (!wait_for_completion_timeout(&held[q][i].entered, 500)) {
                result = -EIO;
                goto out;
            }
    for (unsigned int q = 0; q < ARRAY_SIZE(extra); q++) {
        native_parallel_init(&extra[q], queues[q]);
        BUG_ON(!queue_work(queues[q], &extra[q].work));
        msleep(2);
        if (work_busy(&extra[q].work) != WORK_BUSY_PENDING) result = -EIO;
        complete(&held[q][0].gate);
        flush_work(&extra[q].work);
        if (extra[q].calls != 1 || extra[q].result) result = -EIO;
    }
    for (unsigned int q = 0; q < ARRAY_SIZE(queues); q++) {
        for (unsigned int i = 0; i < limit[q]; i++) complete(&held[q][i].gate);
        flush_workqueue(queues[q]);
        for (unsigned int i = 0; i < limit[q]; i++)
            if (held[q][i].calls != 1 || held[q][i].result) result = -EIO;
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
            if (!wait_for_completion_timeout(&chains[q][i].done, 500)) result = -EIO;
            cancel_work_sync(&chains[q][i].work);
            if (chains[q][i].calls != 4 || chains[q][i].result) result = -EIO;
        }
    struct native_parallel_test nested, target;
    native_parallel_init(&nested, queues[0]);
    native_parallel_init(&target, queues[0]);
    nested.target = &target;
    BUG_ON(!queue_work(queues[0], &nested.work));
    if (!wait_for_completion_timeout(&nested.done, 500)) result = -EIO;
    cancel_work_sync(&nested.work);
    cancel_work_sync(&target.work);
    if (nested.result || target.result || target.calls != 1) result = -EIO;
    for (unsigned int q = 0; q < ARRAY_SIZE(queues); q++) {
        atomic_set(&frees[q].count, 0); init_completion(&frees[q].done);
        for (unsigned int i = 0; i < ARRAY_SIZE(heap[q]); i++) {
            heap[q][i] = kzalloc(sizeof(*heap[q][i]), GFP_KERNEL);
            if (!heap[q][i]) { result = -ENOMEM; goto out; }
            native_parallel_init(heap[q][i], queues[q]);
            heap[q][i]->frees = &frees[q];
            heap[q][i]->free_result = &free_results[q][i];
        }
    }
    heap_submitted = true;
    for (unsigned int q = 0; q < ARRAY_SIZE(queues); q++)
        for (unsigned int i = 0; i < ARRAY_SIZE(heap[q]); i++)
            BUG_ON(!queue_work(queues[q], &heap[q][i]->work));
    for (unsigned int q = 0; q < ARRAY_SIZE(queues); q++) {
        if (!wait_for_completion_timeout(&frees[q].done, 500)) {
            result = -EIO;
            wait_for_completion(&frees[q].done);
        }
        flush_workqueue(queues[q]);
        if (atomic_read(&frees[q].count) != 8) result = -EIO;
        for (unsigned int i = 0; i < ARRAY_SIZE(heap[q]); i++)
            if (free_results[q][i]) result = -EIO;
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

#endif
#endif
