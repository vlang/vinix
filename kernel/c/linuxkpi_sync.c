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

/* Every waiter is on the sleeping task's stack. Queue locks serialize its
 * removal with every producer before that stack frame can return. Producers
 * must keep the enclosing mutex/queue/completion alive until they return. */
struct mutex_waiter {
    struct list_head entry;
    struct task_struct *task;
};

void __mutex_init(struct mutex *lock, const char *name, struct lock_class_key *key)
{
    atomic_long_set(&lock->owner, 0);
    raw_spin_lock_init(&lock->wait_lock);
    INIT_LIST_HEAD(&lock->wait_list);
}

bool mutex_is_locked(struct mutex *lock)
{
    return atomic_long_read(&lock->owner) != 0;
}

void mutex_destroy(struct mutex *lock)
{
    unsigned long flags;
    raw_spin_lock_irqsave(&lock->wait_lock, flags);
    BUG_ON(mutex_is_locked(lock) || !list_empty(&lock->wait_list));
    raw_spin_unlock_irqrestore(&lock->wait_lock, flags);
}

static int mutex_acquire(struct mutex *lock, unsigned int state)
{
    might_sleep();
    struct task_struct *task = current;
    struct mutex_waiter wait = { .task = task };
    unsigned long flags;
    raw_spin_lock_irqsave(&lock->wait_lock, flags);
    long owner = atomic_long_read(&lock->owner);
    BUG_ON(owner == (long)task); /* Recursive acquisition is invalid. */
    if (!owner) {
        BUG_ON(!list_empty(&lock->wait_list));
        atomic_long_set(&lock->owner, (long)task);
        raw_spin_unlock_irqrestore(&lock->wait_lock, flags);
        return 0;
    }
    list_add_tail(&wait.entry, &lock->wait_list);
    for (;;) {
        /* A handoff wins a concurrent signal: this task now owns the lock. */
        if (atomic_long_read(&lock->owner) == (long)task) {
            BUG_ON(!list_empty(&wait.entry));
            __set_current_state(TASK_RUNNING);
            raw_spin_unlock_irqrestore(&lock->wait_lock, flags);
            return 0;
        }
        if (signal_pending_state(state, task)) {
            list_del_init(&wait.entry);
            __set_current_state(TASK_RUNNING);
            raw_spin_unlock_irqrestore(&lock->wait_lock, flags);
            return -EINTR;
        }
        set_current_state(state);
        raw_spin_unlock_irqrestore(&lock->wait_lock, flags);
        schedule();
        raw_spin_lock_irqsave(&lock->wait_lock, flags);
    }
}

void mutex_lock(struct mutex *lock) { (void)mutex_acquire(lock, TASK_UNINTERRUPTIBLE); }
void mutex_lock_io(struct mutex *lock)
{
    /* Match Linux's non-lockdep scope exactly. Intent alone does not count
     * runnable tasks; the native scheduler owns actual blocked-CPU slots. */
    int token = io_schedule_prepare();
    mutex_lock(lock);
    io_schedule_finish(token);
}
int mutex_lock_interruptible(struct mutex *lock) { return mutex_acquire(lock, TASK_INTERRUPTIBLE); }
int mutex_lock_killable(struct mutex *lock) { return mutex_acquire(lock, TASK_KILLABLE); }

int mutex_trylock(struct mutex *lock)
{
    unsigned long flags;
    raw_spin_lock_irqsave(&lock->wait_lock, flags);
    int acquired = !atomic_long_read(&lock->owner);
    if (acquired) {
        BUG_ON(!list_empty(&lock->wait_list));
        atomic_long_set(&lock->owner, (long)current);
    }
    raw_spin_unlock_irqrestore(&lock->wait_lock, flags);
    return acquired;
}

void mutex_unlock(struct mutex *lock)
{
    struct task_struct *task = current;
    unsigned long flags;
    raw_spin_lock_irqsave(&lock->wait_lock, flags);
    BUG_ON(atomic_long_read(&lock->owner) != (long)task);
    if (list_empty(&lock->wait_list)) atomic_long_set_release(&lock->owner, 0);
    else {
        struct mutex_waiter *wait = list_first_entry(&lock->wait_list, struct mutex_waiter, entry);
        struct task_struct *next = wait->task;
        list_del_init(&wait->entry);
        /* FIFO direct handoff prevents a new arrival from stealing the lock.
         * Do not access the waiter's stack after publishing the wakeup. */
        atomic_long_set_release(&lock->owner, (long)next);
        wake_up_process(next);
    }
    raw_spin_unlock_irqrestore(&lock->wait_lock, flags);
}

int atomic_dec_and_mutex_lock(atomic_t *count, struct mutex *lock)
{
    if (atomic_add_unless(count, -1, 1)) return 0;
    mutex_lock(lock);
    if (atomic_dec_and_test(count)) return 1;
    mutex_unlock(lock);
    return 0;
}

void __init_waitqueue_head(struct wait_queue_head *head, const char *name, struct lock_class_key *key)
{
    spin_lock_init(&head->lock);
    INIT_LIST_HEAD(&head->head);
}

void add_wait_queue(struct wait_queue_head *head, struct wait_queue_entry *wait)
{
    unsigned long flags;
    wait->flags &= ~WQ_FLAG_EXCLUSIVE;
    spin_lock_irqsave(&head->lock, flags);
    __add_wait_queue(head, wait);
    spin_unlock_irqrestore(&head->lock, flags);
}

void add_wait_queue_exclusive(struct wait_queue_head *head, struct wait_queue_entry *wait)
{
    unsigned long flags;
    wait->flags |= WQ_FLAG_EXCLUSIVE;
    spin_lock_irqsave(&head->lock, flags);
    __add_wait_queue_entry_tail(head, wait);
    spin_unlock_irqrestore(&head->lock, flags);
}

void add_wait_queue_priority(struct wait_queue_head *head, struct wait_queue_entry *wait)
{
    unsigned long flags;
    wait->flags |= WQ_FLAG_EXCLUSIVE | WQ_FLAG_PRIORITY;
    spin_lock_irqsave(&head->lock, flags);
    __add_wait_queue(head, wait);
    spin_unlock_irqrestore(&head->lock, flags);
}

void remove_wait_queue(struct wait_queue_head *head, struct wait_queue_entry *wait)
{
    unsigned long flags;
    spin_lock_irqsave(&head->lock, flags);
    list_del_init(&wait->entry);
    spin_unlock_irqrestore(&head->lock, flags);
}

static int wake_queue_locked(struct wait_queue_head *head, unsigned int mode, int quota, void *key)
{
    struct wait_queue_entry *wait, *next;
    int remaining = quota;
    list_for_each_entry_safe(wait, next, &head->head, entry) {
        unsigned int flags = wait->flags; /* Callback can remove its entry. */
        if (flags & WQ_FLAG_BOOKMARK) continue;
        int result = wait->func(wait, mode, 0, key);
        if (result < 0) break;
        if (result && (flags & WQ_FLAG_EXCLUSIVE) && !--remaining) break;
    }
    return quota - remaining;
}

int __wake_up(struct wait_queue_head *head, unsigned int mode, int quota, void *key)
{
    unsigned long flags;
    spin_lock_irqsave(&head->lock, flags);
    int result = wake_queue_locked(head, mode, quota, key);
    spin_unlock_irqrestore(&head->lock, flags);
    return result;
}

void __wake_up_locked(struct wait_queue_head *head, unsigned int mode, int quota)
{
    (void)wake_queue_locked(head, mode, quota, NULL);
}

void __wake_up_locked_key(struct wait_queue_head *head, unsigned int mode, void *key)
{
    (void)wake_queue_locked(head, mode, 1, key);
}

int default_wake_function(struct wait_queue_entry *wait, unsigned int mode, int flags, void *key)
{
    /* CPU placement hints have no native bridge yet. Never silently drop one. */
    BUG_ON(flags);
    return wake_up_state(wait->private, mode);
}

int autoremove_wake_function(struct wait_queue_entry *wait, unsigned int mode, int flags, void *key)
{
    int result = default_wake_function(wait, mode, flags, key);
    if (result) list_del_init_careful(&wait->entry);
    return result;
}

void init_wait_entry(struct wait_queue_entry *wait, int flags)
{
    wait->flags = flags;
    wait->private = current;
    wait->func = autoremove_wake_function;
    INIT_LIST_HEAD(&wait->entry);
}

void prepare_to_wait(struct wait_queue_head *head, struct wait_queue_entry *wait, int state)
{
    unsigned long flags;
    wait->flags &= ~WQ_FLAG_EXCLUSIVE;
    spin_lock_irqsave(&head->lock, flags);
    if (list_empty(&wait->entry)) __add_wait_queue(head, wait);
    set_current_state(state);
    spin_unlock_irqrestore(&head->lock, flags);
}

bool prepare_to_wait_exclusive(struct wait_queue_head *head, struct wait_queue_entry *wait, int state)
{
    unsigned long flags;
    bool first = false;
    wait->flags |= WQ_FLAG_EXCLUSIVE;
    spin_lock_irqsave(&head->lock, flags);
    if (list_empty(&wait->entry)) {
        first = list_empty(&head->head);
        __add_wait_queue_entry_tail(head, wait);
    }
    set_current_state(state);
    spin_unlock_irqrestore(&head->lock, flags);
    return first;
}

long prepare_to_wait_event(struct wait_queue_head *head, struct wait_queue_entry *wait, int state)
{
    unsigned long flags;
    long result = 0;
    spin_lock_irqsave(&head->lock, flags);
    if (signal_pending_state(state, current)) {
        list_del_init(&wait->entry);
        __set_current_state(TASK_RUNNING);
        result = -ERESTARTSYS;
    } else {
        if (list_empty(&wait->entry)) {
            if (wait->flags & WQ_FLAG_EXCLUSIVE) __add_wait_queue_entry_tail(head, wait);
            else __add_wait_queue(head, wait);
        }
        set_current_state(state);
    }
    spin_unlock_irqrestore(&head->lock, flags);
    return result;
}

void finish_wait(struct wait_queue_head *head, struct wait_queue_entry *wait)
{
    unsigned long flags;
    __set_current_state(TASK_RUNNING);
    /* Always take the lock, including after autoremove: the producer must
     * finish its callback before this stack frame can disappear. */
    spin_lock_irqsave(&head->lock, flags);
    list_del_init(&wait->entry);
    spin_unlock_irqrestore(&head->lock, flags);
}

void __init_swait_queue_head(struct swait_queue_head *head, const char *name, struct lock_class_key *key)
{
    raw_spin_lock_init(&head->lock);
    INIT_LIST_HEAD(&head->task_list);
}

void swake_up_locked(struct swait_queue_head *head, int flags)
{
    BUG_ON(flags);
    if (!list_empty(&head->task_list)) {
        struct swait_queue *wait = list_first_entry(&head->task_list, struct swait_queue, task_list);
        struct task_struct *task = wait->task;
        list_del_init(&wait->task_list);
        wake_up_process(task);
    }
}

void swake_up_all_locked(struct swait_queue_head *head)
{
    while (!list_empty(&head->task_list)) swake_up_locked(head, 0);
}

void swake_up_one(struct swait_queue_head *head)
{
    unsigned long flags;
    raw_spin_lock_irqsave(&head->lock, flags);
    swake_up_locked(head, 0);
    raw_spin_unlock_irqrestore(&head->lock, flags);
}

void swake_up_all(struct swait_queue_head *head)
{
    BUG_ON(irqs_disabled());
    LIST_HEAD(pending);
    raw_spin_lock_irq(&head->lock);
    list_splice_init(&head->task_list, &pending);
    while (!list_empty(&pending)) {
        struct swait_queue *wait = list_first_entry(&pending, struct swait_queue, task_list);
        struct task_struct *task = wait->task;
        list_del_init(&wait->task_list);
        wake_up_process(task);
        /* Match swait's bounded hold time. pending is private, but waiters
         * remove from it under head->lock, so inspect it only while locked. */
        raw_spin_unlock_irq(&head->lock);
        raw_spin_lock_irq(&head->lock);
    }
    raw_spin_unlock_irq(&head->lock);
}

void __prepare_to_swait(struct swait_queue_head *head, struct swait_queue *wait)
{
    wait->task = current;
    if (list_empty(&wait->task_list)) list_add_tail(&wait->task_list, &head->task_list);
}

void prepare_to_swait_exclusive(struct swait_queue_head *head, struct swait_queue *wait, int state)
{
    unsigned long flags;
    raw_spin_lock_irqsave(&head->lock, flags);
    __prepare_to_swait(head, wait);
    set_current_state(state);
    raw_spin_unlock_irqrestore(&head->lock, flags);
}

long prepare_to_swait_event(struct swait_queue_head *head, struct swait_queue *wait, int state)
{
    unsigned long flags;
    long result = 0;
    raw_spin_lock_irqsave(&head->lock, flags);
    if (signal_pending_state(state, current)) {
        list_del_init(&wait->task_list);
        __set_current_state(TASK_RUNNING);
        result = -ERESTARTSYS;
    } else {
        __prepare_to_swait(head, wait);
        set_current_state(state);
    }
    raw_spin_unlock_irqrestore(&head->lock, flags);
    return result;
}

void __finish_swait(struct swait_queue_head *head, struct swait_queue *wait)
{
    __set_current_state(TASK_RUNNING);
    list_del_init(&wait->task_list);
}

void finish_swait(struct swait_queue_head *head, struct swait_queue *wait)
{
    unsigned long flags;
    raw_spin_lock_irqsave(&head->lock, flags);
    __finish_swait(head, wait);
    raw_spin_unlock_irqrestore(&head->lock, flags);
}

void complete(struct completion *completion)
{
    unsigned long flags;
    raw_spin_lock_irqsave(&completion->wait.lock, flags);
    if (completion->done != UINT_MAX) completion->done++;
    swake_up_locked(&completion->wait, 0);
    raw_spin_unlock_irqrestore(&completion->wait.lock, flags);
}

void complete_all(struct completion *completion)
{
    unsigned long flags;
    raw_spin_lock_irqsave(&completion->wait.lock, flags);
    completion->done = UINT_MAX;
    swake_up_all_locked(&completion->wait);
    raw_spin_unlock_irqrestore(&completion->wait.lock, flags);
}

static long completion_wait(struct completion *completion, long timeout, unsigned int state)
{
    might_sleep();
    BUG_ON(state != TASK_UNINTERRUPTIBLE && state != TASK_INTERRUPTIBLE &&
           state != TASK_KILLABLE && state != TASK_IDLE);
    DECLARE_SWAITQUEUE(wait);
    unsigned long flags;
    raw_spin_lock_irqsave(&completion->wait.lock, flags);
    while (!completion->done) {
        if (signal_pending_state(state, current)) { timeout = -ERESTARTSYS; break; }
        if (!timeout) break;
        __prepare_to_swait(&completion->wait, &wait);
        set_current_state(state);
        raw_spin_unlock_irqrestore(&completion->wait.lock, flags);
        timeout = schedule_timeout(timeout);
        raw_spin_lock_irqsave(&completion->wait.lock, flags);
        /* Match Linux's post-schedule loop condition: expiry ends the wait
         * before a newly pending signal can replace the timeout result. */
        if (!timeout) break;
    }
    __finish_swait(&completion->wait, &wait);
    if (completion->done) {
        if (completion->done != UINT_MAX) completion->done--;
        /* A token observed at expiry still succeeds with at least one tick. */
        if (!timeout) timeout = 1;
    }
    raw_spin_unlock_irqrestore(&completion->wait.lock, flags);
    return timeout;
}

int wait_for_completion_state(struct completion *completion, unsigned int state)
{
    long result = completion_wait(completion, MAX_SCHEDULE_TIMEOUT, state);
    return result == -ERESTARTSYS ? result : 0;
}

void wait_for_completion(struct completion *completion)
{
    (void)wait_for_completion_state(completion, TASK_UNINTERRUPTIBLE);
}
int wait_for_completion_interruptible(struct completion *completion)
{
    return wait_for_completion_state(completion, TASK_INTERRUPTIBLE);
}
int wait_for_completion_killable(struct completion *completion)
{
    return wait_for_completion_state(completion, TASK_KILLABLE);
}

unsigned long wait_for_completion_timeout(struct completion *completion, unsigned long timeout)
{
    return completion_wait(completion, timeout, TASK_UNINTERRUPTIBLE);
}
long wait_for_completion_interruptible_timeout(struct completion *completion, unsigned long timeout)
{
    return completion_wait(completion, timeout, TASK_INTERRUPTIBLE);
}
long wait_for_completion_killable_timeout(struct completion *completion, unsigned long timeout)
{
    return completion_wait(completion, timeout, TASK_KILLABLE);
}

bool try_wait_for_completion(struct completion *completion)
{
    unsigned long flags;
    raw_spin_lock_irqsave(&completion->wait.lock, flags);
    bool result = completion->done != 0;
    if (result && completion->done != UINT_MAX) completion->done--;
    raw_spin_unlock_irqrestore(&completion->wait.lock, flags);
    return result;
}

bool completion_done(struct completion *completion)
{
    unsigned long flags;
    raw_spin_lock_irqsave(&completion->wait.lock, flags);
    bool result = completion->done != 0;
    raw_spin_unlock_irqrestore(&completion->wait.lock, flags);
    return result;
}

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
