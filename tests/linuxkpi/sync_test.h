/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Included by test.c to share its instrumented native task/queue model. */
#include <sched.h>
#include <linux/mutex.h>
/* These tests use Linux queue macros, not the host's process wait options. */
#undef WSTOPPED
#undef WCONTINUED
#undef WNOWAIT
#include <linux/completion.h>
#include <linux/limits.h>

static void sync_model_init(struct native_task_model *model, unsigned int index)
{
    *model = (struct native_task_model){ .pid = 500 + index, .tgid = 500,
        .name = "sync-worker", HOST_TASK_QUEUE_INIT };
    vinix_linuxkpi_task_init(model->storage, model, model->pid, model->tgid, model->name, 11);
}

static void sync_model_destroy(struct native_task_model *model)
{
    assert(!model->pins);
    assert(!pthread_mutex_destroy(&model->queue_lock));
    assert(!pthread_cond_destroy(&model->queue_changed));
}

static unsigned int sync_list_count(struct list_head *head)
{
    unsigned int count = 0;
    struct list_head *entry;
    list_for_each(entry, head) count++;
    return count;
}

static unsigned int mutex_waiters(struct mutex *lock)
{
    unsigned long flags;
    raw_spin_lock_irqsave(&lock->wait_lock, flags);
    unsigned int count = sync_list_count(&lock->wait_list);
    raw_spin_unlock_irqrestore(&lock->wait_lock, flags);
    return count;
}

static unsigned int queue_waiters(struct wait_queue_head *head)
{
    unsigned long flags;
    spin_lock_irqsave(&head->lock, flags);
    unsigned int count = sync_list_count(&head->head);
    spin_unlock_irqrestore(&head->lock, flags);
    return count;
}

struct mutex_fixture {
    struct mutex lock;
    unsigned int counter, acquired, order[4], release[4];
    bool fifo;
};
struct mutex_worker_test {
    struct native_task_model model;
    struct mutex_fixture *fixture;
    unsigned int index;
    bool killable;
    int result;
};

static void *mutex_worker(void *argument)
{
    struct mutex_worker_test *test = argument;
    struct mutex_fixture *fixture = test->fixture;
    native_task = &test->model;
    current_cpu = test->index;
    if (fixture->fifo) {
        test->result = test->killable ? mutex_lock_killable(&fixture->lock) :
                                      mutex_lock_interruptible(&fixture->lock);
        if (!test->result) {
            unsigned int slot = __atomic_load_n(&fixture->acquired, __ATOMIC_RELAXED);
            fixture->order[slot] = test->index;
            __atomic_store_n(&fixture->acquired, slot + 1, __ATOMIC_RELEASE);
            while (!__atomic_load_n(&fixture->release[test->index], __ATOMIC_ACQUIRE)) sched_yield();
            mutex_unlock(&fixture->lock);
        }
    } else {
        for (unsigned int i = 0; i < 1000; i++) {
            mutex_lock(&fixture->lock);
            unsigned int previous = fixture->counter;
            sched_yield(); /* Force a competing thread to try to acquire it. */
            fixture->counter = previous + 1;
            mutex_unlock(&fixture->lock);
        }
    }
    assert(task_is_running(current) && interrupts && !preempt_depth);
    native_task = NULL;
    return NULL;
}

static void mutex_tests(void)
{
    DEFINE_MUTEX(static_lock);
    assert(!mutex_is_locked(&static_lock) && mutex_trylock(&static_lock) == 1);
    assert(mutex_is_locked(&static_lock) && !mutex_trylock(&static_lock));
    mutex_unlock(&static_lock);
    mutex_lock_nested(&static_lock, 1);
    mutex_unlock(&static_lock);
    atomic_t count = ATOMIC_INIT(2);
    assert(!atomic_dec_and_mutex_lock(&count, &static_lock) && atomic_read(&count) == 1);
    assert(atomic_dec_and_mutex_lock(&count, &static_lock) && atomic_read(&count) == 0);
    mutex_unlock(&static_lock);
    refcount_t refs = REFCOUNT_INIT(2);
    assert(!refcount_dec_and_mutex_lock(&refs, &static_lock) && refcount_read(&refs) == 1);
    assert(refcount_dec_and_mutex_lock(&refs, &static_lock) && refcount_read(&refs) == 0);
    mutex_unlock(&static_lock);
    /* Uncontended acquisitions succeed even with a signal pending. */
    native_task->pending = 1ULL << 14;
    assert(!mutex_lock_interruptible(&static_lock));
    mutex_unlock(&static_lock);
    native_task->pending = 0;
    mutex_destroy(&static_lock);

    struct mutex_fixture fixture = {0};
    mutex_init(&fixture.lock);
    struct mutex_worker_test workers[4];
    pthread_t threads[4];
    for (unsigned int i = 0; i < 4; i++) {
        workers[i] = (struct mutex_worker_test){ .fixture = &fixture, .index = i };
        sync_model_init(&workers[i].model, i);
        assert(!pthread_create(&threads[i], NULL, mutex_worker, &workers[i]));
    }
    for (unsigned int i = 0; i < 4; i++) {
        assert(!pthread_join(threads[i], NULL));
        sync_model_destroy(&workers[i].model);
    }
    assert(fixture.counter == 4000 && !mutex_waiters(&fixture.lock));
    mutex_destroy(&fixture.lock);

    /* Queue in a controlled order; cancel both an interruptible middle entry
     * and a killable tail. The remaining two must receive FIFO handoffs. */
    fixture = (struct mutex_fixture){ .fifo = true };
    mutex_init(&fixture.lock);
    mutex_lock(&fixture.lock);
    for (unsigned int i = 0; i < 4; i++) {
        workers[i] = (struct mutex_worker_test){ .fixture = &fixture, .index = i, .killable = i == 3 };
        sync_model_init(&workers[i].model, i);
        assert(!pthread_create(&threads[i], NULL, mutex_worker, &workers[i]));
        while (mutex_waiters(&fixture.lock) != i + 1) sched_yield();
    }
    __atomic_store_n(&workers[1].model.pending, 1ULL << 14, __ATOMIC_RELEASE);
    assert(vinix_linuxkpi_task_enqueue(&workers[1].model));
    assert(!pthread_join(threads[1], NULL) && workers[1].result == -EINTR);
    __atomic_store_n(&workers[3].model.pending, 1ULL << 14, __ATOMIC_RELEASE);
    assert(vinix_linuxkpi_task_enqueue(&workers[3].model));
    while (vinix_linuxkpi_task_queued(&workers[3].model)) sched_yield();
    assert(mutex_waiters(&fixture.lock) == 3); /* Ordinary signal was ignored. */
    __atomic_store_n(&workers[3].model.pending, 1ULL << 8, __ATOMIC_RELEASE);
    assert(vinix_linuxkpi_task_enqueue(&workers[3].model));
    assert(!pthread_join(threads[3], NULL) && workers[3].result == -EINTR);
    assert(mutex_waiters(&fixture.lock) == 2);
    mutex_unlock(&fixture.lock);
    for (unsigned int slot = 0; slot < 2; slot++) {
        while (__atomic_load_n(&fixture.acquired, __ATOMIC_ACQUIRE) <= slot) sched_yield();
        assert(fixture.order[slot] == slot * 2 && !mutex_trylock(&fixture.lock));
        __atomic_store_n(&fixture.release[slot * 2], 1, __ATOMIC_RELEASE);
        assert(!pthread_join(threads[slot * 2], NULL) && !workers[slot * 2].result);
    }
    assert(!mutex_is_locked(&fixture.lock) && !mutex_waiters(&fixture.lock));
    for (unsigned int i = 0; i < 4; i++) sync_model_destroy(&workers[i].model);
    mutex_destroy(&fixture.lock);

    /* Publish a pending signal while the task is parked, then perform the
     * lock handoff. When it resumes, ownership must win over cancellation. */
    fixture = (struct mutex_fixture){ .fifo = true, .release = {1} };
    mutex_init(&fixture.lock);
    mutex_lock(&fixture.lock);
    workers[0] = (struct mutex_worker_test){ .fixture = &fixture };
    sync_model_init(&workers[0].model, 0);
    workers[0].model.iteration = 1;
    assert(!pthread_create(&threads[0], NULL, mutex_worker, &workers[0]));
    /* Dequeue alone precedes schedule's signal check. Wait beyond that check
     * so cancellation cannot finish before the controller hands off. */
    while (__atomic_load_n(&workers[0].model.parked, __ATOMIC_ACQUIRE) != 1) sched_yield();
    __atomic_store_n(&workers[0].model.pending, 1ULL << 14, __ATOMIC_RELEASE);
    mutex_unlock(&fixture.lock);
    assert(!pthread_join(threads[0], NULL) && !workers[0].result && fixture.acquired == 1);
    sync_model_destroy(&workers[0].model);
    mutex_destroy(&fixture.lock);
}

struct callback_test {
    struct wait_queue_entry wait;
    unsigned int id, *order, *count;
    void *key;
    int result;
    bool remove;
};
static int record_wake(struct wait_queue_entry *wait, unsigned int mode, int flags, void *key)
{
    struct callback_test *test = container_of(wait, struct callback_test, wait);
    assert(mode == TASK_NORMAL && !flags && key == test->key);
    assert(!interrupts && preempt_depth == 1);
    test->order[(*test->count)++] = test->id;
    if (test->remove) list_del_init(&wait->entry);
    return test->result;
}

static void wait_callback_tests(void)
{
    DECLARE_WAIT_QUEUE_HEAD(head);
    unsigned int order[8] = {0}, count = 0;
    int key;
    struct callback_test tests[5];
    for (unsigned int i = 0; i < 5; i++) {
        tests[i] = (struct callback_test){ .id = i, .order = order, .count = &count,
            .key = &key, .result = 1 };
        init_waitqueue_func_entry(&tests[i].wait, record_wake);
        INIT_LIST_HEAD(&tests[i].wait.entry);
    }
    add_wait_queue_exclusive(&head, &tests[2].wait);
    add_wait_queue_exclusive(&head, &tests[3].wait);
    add_wait_queue(&head, &tests[0].wait);
    add_wait_queue(&head, &tests[1].wait);
    add_wait_queue_priority(&head, &tests[4].wait);
    assert(__wake_up(&head, TASK_NORMAL, 1, &key) == 1 && count == 1 && order[0] == 4);
    remove_wait_queue(&head, &tests[4].wait);
    count = 0;
    tests[1].remove = true;
    tests[2].result = 0;
    assert(__wake_up(&head, TASK_NORMAL, 1, &key) == 1 && count == 4);
    assert(order[0] == 1 && order[1] == 0 && order[2] == 2 && order[3] == 3);
    assert(list_empty(&tests[1].wait.entry));
    count = 0;
    tests[0].result = -1;
    unsigned long flags;
    spin_lock_irqsave(&head.lock, flags);
    __wake_up_locked_key(&head, TASK_NORMAL, &key);
    spin_unlock_irqrestore(&head.lock, flags);
    assert(count == 1 && order[0] == 0);
    tests[0].result = tests[2].result = 1;
    count = 0;
    assert(__wake_up(&head, TASK_NORMAL, 0, &key) == 2 && count == 3);
    for (unsigned int i = 0; i < 5; i++) remove_wait_queue(&head, &tests[i].wait);
    assert(!waitqueue_active(&head));
}

enum sync_wait_kind { SYNC_WAIT, SYNC_SWAIT, SYNC_COMPLETE };
struct event_fixture {
    struct wait_queue_head queue;
    struct swait_queue_head simple;
    struct completion completion;
    unsigned int condition, payload;
};
struct event_worker_test {
    struct native_task_model model;
    struct event_fixture *fixture;
    enum sync_wait_kind kind;
    unsigned int index, state;
    int result;
};

static void *event_worker(void *argument)
{
    struct event_worker_test *test = argument;
    struct event_fixture *fixture = test->fixture;
    native_task = &test->model;
    current_cpu = test->index;
    if (test->kind == SYNC_COMPLETE)
        test->result = wait_for_completion_state(&fixture->completion, test->state);
    else if (test->kind == SYNC_SWAIT) {
        if (test->state == TASK_INTERRUPTIBLE)
            test->result = swait_event_interruptible_exclusive(fixture->simple,
                __atomic_load_n(&fixture->condition, __ATOMIC_ACQUIRE));
        else
            swait_event_exclusive(fixture->simple,
                __atomic_load_n(&fixture->condition, __ATOMIC_ACQUIRE));
    } else if (test->state == TASK_INTERRUPTIBLE)
        test->result = wait_event_interruptible_exclusive(fixture->queue,
            __atomic_load_n(&fixture->condition, __ATOMIC_ACQUIRE));
    else if (test->state == TASK_KILLABLE)
        test->result = wait_event_killable(fixture->queue,
            __atomic_load_n(&fixture->condition, __ATOMIC_ACQUIRE));
    else
        wait_event(fixture->queue, __atomic_load_n(&fixture->condition, __ATOMIC_ACQUIRE));
    if (!test->result) assert(fixture->payload == 0x1234);
    assert(task_is_running(current) && interrupts && !preempt_depth);
    native_task = NULL;
    return NULL;
}

static void event_fixture_init(struct event_fixture *fixture)
{
    *fixture = (struct event_fixture){0};
    init_waitqueue_head(&fixture->queue);
    init_swait_queue_head(&fixture->simple);
    init_completion(&fixture->completion);
}

static void event_fixture_empty(struct event_fixture *fixture)
{
    assert(!waitqueue_active(&fixture->queue) && !swait_active(&fixture->simple));
    assert(!swait_active(&fixture->completion.wait));
}

static bool condition_after_signal(unsigned int *checks)
{
    (*checks)++;
    if (*checks == 2) native_task->pending = 1ULL << 14;
    return *checks >= 3;
}

static void event_tests(void)
{
    struct event_fixture fixture;
    event_fixture_init(&fixture);
    struct event_worker_test workers[4];
    pthread_t threads[4];
    for (unsigned int kind = SYNC_WAIT; kind <= SYNC_COMPLETE; kind++) {
        for (unsigned int early = 0; early < 2; early++) {
            event_fixture_init(&fixture);
            if (early) {
                fixture.payload = 0x1234;
                fixture.condition = 1;
                if (kind == SYNC_COMPLETE) for (unsigned int i = 0; i < 4; i++) complete(&fixture.completion);
            }
            for (unsigned int i = 0; i < 4; i++) {
                workers[i] = (struct event_worker_test){ .fixture = &fixture, .kind = kind,
                    .index = i, .state = i & 1 ? TASK_INTERRUPTIBLE : TASK_UNINTERRUPTIBLE };
                sync_model_init(&workers[i].model, i);
                assert(!pthread_create(&threads[i], NULL, event_worker, &workers[i]));
            }
            if (!early) {
                for (unsigned int i = 0; i < 4; i++)
                    while (vinix_linuxkpi_task_queued(&workers[i].model)) sched_yield();
                if (kind == SYNC_WAIT) assert(queue_waiters(&fixture.queue) == 4);
                fixture.payload = 0x1234;
                __atomic_store_n(&fixture.condition, 1, __ATOMIC_RELEASE);
                if (kind == SYNC_WAIT) wake_up_all(&fixture.queue);
                if (kind == SYNC_SWAIT) swake_up_all(&fixture.simple);
                if (kind == SYNC_COMPLETE) complete_all(&fixture.completion);
            }
            for (unsigned int i = 0; i < 4; i++) {
                assert(!pthread_join(threads[i], NULL) && !workers[i].result);
                sync_model_destroy(&workers[i].model);
            }
            event_fixture_empty(&fixture);
        }
        /* Interrupt a parked stack waiter, then check that no queue retains
         * it after pthread_join makes the worker's stack unavailable. */
        event_fixture_init(&fixture);
        workers[0] = (struct event_worker_test){ .fixture = &fixture, .kind = kind,
            .state = TASK_INTERRUPTIBLE };
        sync_model_init(&workers[0].model, 0);
        assert(!pthread_create(&threads[0], NULL, event_worker, &workers[0]));
        while (vinix_linuxkpi_task_queued(&workers[0].model)) sched_yield();
        __atomic_store_n(&workers[0].model.pending, 1ULL << 14, __ATOMIC_RELEASE);
        assert(vinix_linuxkpi_task_enqueue(&workers[0].model));
        assert(!pthread_join(threads[0], NULL) && workers[0].result == -ERESTARTSYS);
        sync_model_destroy(&workers[0].model);
        event_fixture_empty(&fixture);
        wake_up_all(&fixture.queue);
        swake_up_all(&fixture.simple);
        complete_all(&fixture.completion);
    }
    for (unsigned int kind = SYNC_WAIT; kind <= SYNC_COMPLETE; kind += 2) {
        event_fixture_init(&fixture);
        workers[0] = (struct event_worker_test){ .fixture = &fixture, .kind = kind,
            .state = TASK_KILLABLE };
        sync_model_init(&workers[0].model, 0);
        assert(!pthread_create(&threads[0], NULL, event_worker, &workers[0]));
        while (vinix_linuxkpi_task_queued(&workers[0].model)) sched_yield();
        __atomic_store_n(&workers[0].model.pending, 1ULL << 14, __ATOMIC_RELEASE);
        assert(vinix_linuxkpi_task_enqueue(&workers[0].model));
        while (vinix_linuxkpi_task_queued(&workers[0].model)) sched_yield();
        __atomic_store_n(&workers[0].model.pending, 1ULL << 8, __ATOMIC_RELEASE);
        assert(vinix_linuxkpi_task_enqueue(&workers[0].model));
        assert(!pthread_join(threads[0], NULL) && workers[0].result == -ERESTARTSYS);
        sync_model_destroy(&workers[0].model);
        event_fixture_empty(&fixture);
    }
    event_fixture_init(&fixture);
    unsigned int checks = 0;
    assert(!wait_event_interruptible(fixture.queue, condition_after_signal(&checks)) && checks == 3);
    assert(task_is_running(current) && !waitqueue_active(&fixture.queue));
    native_task->pending = 0;
    checks = 0;
    assert(!swait_event_interruptible_exclusive(fixture.simple, condition_after_signal(&checks)) && checks == 3);
    assert(task_is_running(current) && !swait_active(&fixture.simple));
    native_task->pending = 1ULL << 14;
    assert(wait_event_interruptible(fixture.queue, false) == -ERESTARTSYS);
    assert(swait_event_interruptible_exclusive(fixture.simple, false) == -ERESTARTSYS);
    assert(wait_for_completion_interruptible(&fixture.completion) == -ERESTARTSYS);
    assert(task_is_running(current));
    /* An already satisfied condition/token wins a pending signal. */
    assert(!wait_event_interruptible(fixture.queue, true));
    complete(&fixture.completion);
    assert(!wait_for_completion_interruptible(&fixture.completion));
    native_task->pending = 0;
    event_fixture_empty(&fixture);
    assert(!try_wait_for_completion(&fixture.completion) && !completion_done(&fixture.completion));
    complete(&fixture.completion);
    complete(&fixture.completion);
    assert(completion_done(&fixture.completion));
    wait_for_completion(&fixture.completion);
    assert(try_wait_for_completion(&fixture.completion) && !try_wait_for_completion(&fixture.completion));
    fixture.completion.done = UINT_MAX - 1;
    unsigned long flags = vinix_linuxkpi_irq_save();
    complete(&fixture.completion);
    complete(&fixture.completion);
    assert(completion_done(&fixture.completion) && try_wait_for_completion(&fixture.completion));
    assert(fixture.completion.done == UINT_MAX);
    vinix_linuxkpi_irq_restore(flags);
    reinit_completion(&fixture.completion);
    assert(!completion_done(&fixture.completion));
    complete_all(&fixture.completion);
    for (unsigned int i = 0; i < 10; i++) wait_for_completion(&fixture.completion);
    assert(fixture.completion.done == UINT_MAX);
    reinit_completion(&fixture.completion);
    event_fixture_empty(&fixture);
}

static void sync_tests(void)
{
    struct native_task_model controller;
    sync_model_init(&controller, 20);
    native_task = &controller;
    for (unsigned int i = 0; i < 200; i++) assert(!vinix_linuxkpi_sync_selftest());
    mutex_tests();
    wait_callback_tests();
    event_tests();
    assert(interrupts && !preempt_depth && live_pages == permanent_pages);
    native_task = NULL;
    sync_model_destroy(&controller);
}
