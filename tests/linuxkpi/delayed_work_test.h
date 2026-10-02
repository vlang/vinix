/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Included after workqueue_test.h to use its native worker/task model. */
struct delayed_timer_gate {
    struct timer_list *timer;
    unsigned int entered, release;
};
static struct delayed_timer_gate *delayed_gate;
void vinix_linuxkpi_host_delayed_timer_gate(struct timer_list *timer)
{
    struct delayed_timer_gate *gate = __atomic_load_n(&delayed_gate, __ATOMIC_ACQUIRE);
    if (!gate || gate->timer != timer) return;
    assert(!interrupts && preempt_depth);
    __atomic_store_n(&gate->entered, 1, __ATOMIC_RELEASE);
    while (!__atomic_load_n(&gate->release, __ATOMIC_ACQUIRE)) sched_yield();
}

struct delayed_test {
    struct delayed_work work;
    struct workqueue_struct *wq;
    struct completion entered, gate;
    unsigned int calls, limit, active;
    unsigned int *freed;
    bool hold, free_self, requeue_first;
    unsigned long delay, earliest;
};
static void delayed_callback(struct work_struct *work)
{
    struct delayed_test *test = container_of(to_delayed_work(work), struct delayed_test, work);
    assert(vinix_linuxkpi_may_sleep() && current_work() == work);
    assert(__atomic_fetch_add(&test->active, 1, __ATOMIC_ACQ_REL) == 0);
    assert(time_after_eq(jiffies, test->earliest));
    unsigned int calls = __atomic_add_fetch(&test->calls, 1, __ATOMIC_ACQ_REL);
    if (test->requeue_first && calls == 1)
        assert(queue_delayed_work(test->wq, &test->work, test->delay));
    if (test->hold && calls == 1) {
        complete(&test->entered);
        wait_for_completion(&test->gate);
    }
    if (calls < test->limit && !(test->requeue_first && calls == 1))
        queue_delayed_work(test->wq, &test->work, test->delay);
    sched_yield();
    assert(__atomic_fetch_sub(&test->active, 1, __ATOMIC_ACQ_REL) == 1);
    if (test->free_self) {
        __atomic_fetch_add(test->freed, 1, __ATOMIC_RELEASE);
        kfree(test); /* Timer transfer and worker dispatch must both stop reading it. */
    }
}
static void delayed_init(struct delayed_test *test, struct workqueue_struct *wq)
{
    *test = (struct delayed_test){ .wq = wq, .earliest = jiffies };
    INIT_DELAYED_WORK_ONSTACK(&test->work, delayed_callback);
    init_completion(&test->entered);
    init_completion(&test->gate);
}
static void advance_delayed(unsigned int ticks)
{
    host_time_advance(ticks);
    vinix_linuxkpi_timer_dispatch();
}
static unsigned int static_delayed_calls;
static void static_delayed_callback(struct work_struct *work) { static_delayed_calls++; }
static DECLARE_DELAYED_WORK(static_delayed_work, static_delayed_callback);

enum delayed_operation { DELAYED_MOD, DELAYED_CANCEL, DELAYED_CANCEL_SYNC, DELAYED_FLUSH };
struct delayed_operation_test {
    struct native_task_model model;
    struct delayed_test *test;
    struct workqueue_struct *wq;
    enum delayed_operation operation;
    unsigned long delay;
    unsigned int started, spins, done;
    bool result, irq_off;
    pthread_t thread;
};
static void *delayed_operation_thread(void *argument)
{
    struct delayed_operation_test *operation = argument;
    native_task = &operation->model;
    unsigned long flags = operation->irq_off ? vinix_linuxkpi_irq_save() : 1UL << 9;
    timer_sync_spins = &operation->spins;
    __atomic_store_n(&operation->started, 1, __ATOMIC_RELEASE);
    if (operation->operation == DELAYED_MOD)
        operation->result = mod_delayed_work(operation->wq, &operation->test->work, operation->delay);
    if (operation->operation == DELAYED_CANCEL)
        operation->result = cancel_delayed_work(&operation->test->work);
    if (operation->operation == DELAYED_CANCEL_SYNC)
        operation->result = cancel_delayed_work_sync(&operation->test->work);
    if (operation->operation == DELAYED_FLUSH)
        operation->result = flush_delayed_work(&operation->test->work);
    assert(interrupts == !operation->irq_off && !preempt_depth);
    if (operation->irq_off) vinix_linuxkpi_irq_restore(flags);
    timer_sync_spins = NULL;
    __atomic_store_n(&operation->done, 1, __ATOMIC_RELEASE);
    native_task = NULL;
    return NULL;
}
static void delayed_operation_start(struct delayed_operation_test *operation,
                                    enum delayed_operation mode, struct delayed_test *test,
                                    struct workqueue_struct *wq, unsigned long delay, bool irq_off)
{
    *operation = (struct delayed_operation_test){ .operation = mode, .test = test,
        .wq = wq, .delay = delay, .irq_off = irq_off };
    sync_model_init(&operation->model, 80);
    operation->model.iteration = 1;
    assert(!pthread_create(&operation->thread, NULL, delayed_operation_thread, operation));
    await_counter(&operation->started);
}
static void delayed_operation_join(struct delayed_operation_test *operation)
{
    assert(!pthread_join(operation->thread, NULL) && operation->done);
    sync_model_destroy(&operation->model);
}

static void delayed_queue_tests(struct workqueue_struct *a, struct workqueue_struct *b)
{
    struct delayed_test test;
    delayed_init(&test, a);
    assert(!cancel_delayed_work(&test.work) && !cancel_delayed_work_sync(&test.work));
    assert(!flush_delayed_work(&test.work));
    assert(queue_delayed_work(a, &test.work, 10));
    assert(!queue_delayed_work(a, &test.work, 1));
    assert(delayed_work_pending(&test.work) && timer_pending(&test.work.timer));
    assert(work_busy(&test.work.work) == WORK_BUSY_PENDING);
    flush_workqueue(a); drain_workqueue(a); /* Unexpired reservations are excluded. */
    assert(!test.calls && delayed_work_pending(&test.work));
    advance_delayed(9); flush_workqueue(a); assert(!test.calls);
    advance_delayed(1); flush_workqueue(a); assert(test.calls == 1);
    assert(!timer_pending(&test.work.timer) && !work_busy(&test.work.work));

    assert(!mod_delayed_work(a, &test.work, 20)); /* Idle queueing returns false. */
    unsigned long expires = test.work.timer.expires;
    assert(mod_delayed_work(a, &test.work, 40) && test.work.timer.expires == expires + 20);
    assert(mod_delayed_work(b, &test.work, 2) && test.work.wq == b);
    advance_delayed(1); flush_workqueue(b); assert(test.calls == 1);
    advance_delayed(1); flush_workqueue(b); assert(test.calls == 2);
    assert(queue_delayed_work(a, &test.work, 100));
    assert(mod_delayed_work(b, &test.work, 0)); /* Immediate means no timer tick. */
    flush_workqueue(b); assert(test.calls == 3 && !timer_pending(&test.work.timer));

    struct work_test held;
    work_init(&held, a); held.hold = true;
    assert(queue_work(a, &held.work)); await_counter(&held.entered);
    assert(queue_delayed_work(a, &test.work, 0));
    assert(mod_delayed_work(b, &test.work, 10)); /* Executable -> delayed -> migrated. */
    assert(cancel_delayed_work(&test.work) && !cancel_delayed_work(&test.work));
    assert(queue_delayed_work(a, &test.work, 0));
    assert(cancel_delayed_work_sync(&test.work)); /* Cancel an executable copy. */
    complete(&held.gate); drain_workqueue(a);
    assert(test.calls == 3);
    assert(queue_delayed_work(a, &test.work, 1));
    host_time_advance(1); /* Promoted timer, not dispatched yet. */
    assert(cancel_delayed_work(&test.work));
    assert(!vinix_linuxkpi_timer_dispatch() && test.calls == 3);
    assert(queue_delayed_work(a, &static_delayed_work, 1));
    advance_delayed(1); flush_workqueue(a); assert(static_delayed_calls == 1);
    assert(!cancel_delayed_work_sync(&static_delayed_work));

    delayed_init(&test, a);
    int warnings = atomic_read(&time_warnings);
    assert(!queue_delayed_work_on(1, a, &test.work, 1));
    assert(!mod_delayed_work_on(1, a, &test.work, 1));
    assert(atomic_read(&time_warnings) == warnings + 2 && !delayed_work_pending(&test.work));
    unsigned long flags = vinix_linuxkpi_irq_save();
    assert(queue_delayed_work(a, &test.work, 10));
    assert(mod_delayed_work(a, &test.work, 5));
    assert(cancel_delayed_work(&test.work));
    assert(!interrupts && !preempt_depth);
    vinix_linuxkpi_irq_restore(flags);
}

static void delayed_flush_tests(struct workqueue_struct *wq)
{
    struct delayed_test test;
    delayed_init(&test, wq);
    test.hold = true; test.limit = 2; test.delay = 100;
    assert(queue_delayed_work(wq, &test.work, 10000));
    struct delayed_operation_test operation;
    delayed_operation_start(&operation, DELAYED_FLUSH, &test, wq, 0, false);
    wait_for_completion(&test.entered);
    assert(!operation.done && !timer_pending(&test.work.timer));
    complete(&test.gate);
    delayed_operation_join(&operation);
    assert(operation.result && test.calls == 1);
    /* Flushing the captured instance must not cancel its later self-rearm. */
    assert(timer_pending(&test.work.timer) && delayed_work_pending(&test.work));
    assert(cancel_delayed_work_sync(&test.work));
}

static void delayed_cancel_tests(struct workqueue_struct *wq)
{
    for (unsigned int requeue = 0; requeue < 2; requeue++) {
        struct delayed_test test;
        delayed_init(&test, wq);
        test.hold = true; test.limit = 2; test.delay = 100; test.requeue_first = requeue;
        assert(queue_delayed_work(wq, &test.work, 0));
        wait_for_completion(&test.entered);
        struct delayed_operation_test operation;
        delayed_operation_start(&operation, DELAYED_CANCEL_SYNC, &test, wq, 0, false);
        while (!__atomic_load_n(&operation.model.parked, __ATOMIC_ACQUIRE)) sched_yield();
        assert(!operation.done && !queue_delayed_work(wq, &test.work, 1));
        assert(mod_delayed_work(wq, &test.work, 1)); /* Suppressed, returns canceling=true. */
        complete(&test.gate);
        delayed_operation_join(&operation);
        assert(operation.result == !!requeue && test.calls == 1 && !work_busy(&test.work.work));
        assert(!timer_pending(&test.work.timer) && !vinix_linuxkpi_timer_active());
        assert(queue_delayed_work(wq, &test.work, 1));
        advance_delayed(1); flush_workqueue(wq);
        assert(test.calls == 2 && !cancel_delayed_work_sync(&test.work));
    }
}

static void delayed_transfer_tests(struct workqueue_struct *a, struct workqueue_struct *b)
{
    for (unsigned int mode = 0; mode < 4; mode++) {
        struct delayed_test test;
        delayed_init(&test, a);
        struct work_test held;
        work_init(&held, a); held.hold = true;
        assert(queue_work(a, &held.work)); await_counter(&held.entered);
        assert(queue_delayed_work(a, &test.work, 1));
        host_time_advance(1);
        struct delayed_timer_gate gate = { .timer = &test.work.timer };
        __atomic_store_n(&delayed_gate, &gate, __ATOMIC_RELEASE);
        struct timer_thread_test dispatch = {0};
        sync_model_init(&dispatch.model, 90);
        pthread_t timer_thread;
        assert(!pthread_create(&timer_thread, NULL, timer_dispatch_thread, &dispatch));
        await_counter(&gate.entered);
        struct delayed_operation_test operation;
        delayed_operation_start(&operation, mode == 0 ? DELAYED_MOD :
            mode == 1 ? DELAYED_CANCEL : mode == 2 ? DELAYED_CANCEL_SYNC : DELAYED_FLUSH,
            &test, b, 10, mode < 2);
        await_counter(&operation.spins);
        assert(!operation.done); /* Transfer owns the pending item until its lock handoff. */
        __atomic_store_n(&gate.release, 1, __ATOMIC_RELEASE);
        assert(!pthread_join(timer_thread, NULL) && dispatch.result == 1);
        __atomic_store_n(&delayed_gate, NULL, __ATOMIC_RELEASE);
        sync_model_destroy(&dispatch.model);
        if (mode == 3) {
            while (!__atomic_load_n(&operation.model.parked, __ATOMIC_ACQUIRE)) sched_yield();
            assert(!operation.done && !test.calls);
            complete(&held.gate);
        }
        delayed_operation_join(&operation);
        assert(operation.result && test.calls == (mode == 3));
        if (mode == 0) {
            assert(test.work.wq == b && timer_pending(&test.work.timer));
            advance_delayed(9); flush_workqueue(b); assert(!test.calls);
            advance_delayed(1); flush_workqueue(b); assert(test.calls == 1);
        } else assert(!delayed_work_pending(&test.work) && !vinix_linuxkpi_timer_active());
        if (mode != 3) complete(&held.gate);
        drain_workqueue(a);
        assert(!cancel_delayed_work_sync(&test.work));
    }
}

struct delayed_producer {
    struct native_task_model model;
    struct delayed_test *test;
    struct workqueue_struct *wq;
    unsigned int done;
};
static void *delayed_producer_thread(void *argument)
{
    struct delayed_producer *producer = argument;
    native_task = &producer->model;
    for (unsigned int i = 0; i < 500; i++) {
        unsigned long flags = i & 1 ? vinix_linuxkpi_irq_save() : 1UL << 9;
        if (i % 3 == 0) queue_delayed_work(producer->wq, &producer->test->work, i & 3);
        if (i % 3 == 1) mod_delayed_work(producer->wq, &producer->test->work, i & 3);
        if (i % 3 == 2) cancel_delayed_work(&producer->test->work);
        assert(interrupts == !(i & 1) && !preempt_depth);
        if (i & 1) vinix_linuxkpi_irq_restore(flags);
        sched_yield();
    }
    __atomic_store_n(&producer->done, 1, __ATOMIC_RELEASE);
    native_task = NULL;
    return NULL;
}
static void delayed_race_tests(struct workqueue_struct *a, struct workqueue_struct *b)
{
    struct delayed_test shared;
    delayed_init(&shared, a);
    struct delayed_producer producers[4];
    pthread_t threads[4];
    for (unsigned int i = 0; i < ARRAY_SIZE(producers); i++) {
        producers[i] = (struct delayed_producer){ .test = &shared, .wq = i & 1 ? a : b };
        sync_model_init(&producers[i].model, i + 100);
        assert(!pthread_create(&threads[i], NULL, delayed_producer_thread, &producers[i]));
    }
    unsigned int finished;
    do {
        advance_delayed(1);
        finished = 0;
        for (unsigned int i = 0; i < ARRAY_SIZE(producers); i++)
            finished += __atomic_load_n(&producers[i].done, __ATOMIC_ACQUIRE);
        sched_yield();
    } while (finished != ARRAY_SIZE(producers));
    for (unsigned int i = 0; i < ARRAY_SIZE(producers); i++) {
        assert(!pthread_join(threads[i], NULL));
        sync_model_destroy(&producers[i].model);
    }
    cancel_delayed_work_sync(&shared.work);
    flush_workqueue(a); flush_workqueue(b);
    assert(!work_busy(&shared.work.work) && !shared.active && !vinix_linuxkpi_timer_active());
    unsigned int calls = shared.calls;
    assert(queue_delayed_work(b, &shared.work, 1));
    advance_delayed(1); flush_workqueue(b);
    assert(shared.calls == calls + 1 && !cancel_delayed_work_sync(&shared.work));
}

static void delayed_work_tests(void)
{
    struct native_task_model parent;
    sync_model_init(&parent, 70); native_task = &parent;
    size_t before = live_pages;
    struct workqueue_struct *a = alloc_ordered_workqueue("delayed-a", 0);
    struct workqueue_struct *b = alloc_ordered_workqueue("delayed-b", 0);
    assert(a && b);
    delayed_queue_tests(a, b);
    delayed_flush_tests(a);
    delayed_cancel_tests(a);
    delayed_transfer_tests(a, b);
    delayed_race_tests(a, b);
    unsigned int freed = 0;
    for (unsigned int i = 0; i < 200; i++) {
        struct delayed_test *test = kzalloc(sizeof(*test), GFP_KERNEL);
        assert(test); delayed_init(test, a);
        test->free_self = true; test->freed = &freed;
        assert(queue_delayed_work(a, &test->work, 1));
        advance_delayed(1); flush_workqueue(a);
        assert(!vinix_linuxkpi_timer_active());
    }
    assert(freed == 200);
    destroy_workqueue(a); destroy_workqueue(b);
    assert(live_pages == before && !atomic_read(&host_work_workers));
    native_task = NULL; sync_model_destroy(&parent);
}
