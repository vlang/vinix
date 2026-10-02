/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <linux/workqueue.h>

static atomic_t host_work_workers = ATOMIC_INIT(0);
void vinix_linuxkpi_host_worker_enter(void)
{
    struct native_task_model *model = calloc(1, sizeof(*model));
    assert(model);
    unsigned int index = atomic_inc_return(&host_work_workers);
    sync_model_init(model, index);
    model->heap_owned = true;
    native_task = model;
    current_cpu = index % 4;
}
void vinix_linuxkpi_host_worker_leave(void)
{
    struct native_task_model *model = native_task;
    assert(model->pins == 1 && vinix_linuxkpi_may_sleep());
    __atomic_store_n(&model->dead, true, __ATOMIC_RELEASE);
    vinix_linuxkpi_task_dead(model->storage);
    atomic_dec(&host_work_workers);
    native_task = NULL;
}

struct work_test {
    struct work_struct work;
    struct workqueue_struct *wq, *other;
    struct completion gate;
    unsigned int calls, entered, active, limit;
    unsigned int *count, *order;
    unsigned int index;
    bool hold, requeue_first, free_self;
};
static unsigned int static_work_calls;
static void static_work_callback(struct work_struct *work)
{
    assert(current_work() == work && vinix_linuxkpi_may_sleep());
    static_work_calls++;
}
static DECLARE_WORK(static_work, static_work_callback);
static void work_callback(struct work_struct *work)
{
    struct work_test *test = container_of(work, struct work_test, work);
    assert(vinix_linuxkpi_may_sleep() && current_work() == work);
    assert(__atomic_fetch_add(&test->active, 1, __ATOMIC_ACQ_REL) == 0);
    unsigned int calls = __atomic_add_fetch(&test->calls, 1, __ATOMIC_ACQ_REL);
    if (test->count) {
        unsigned int slot = __atomic_fetch_add(test->count, 1, __ATOMIC_ACQ_REL);
        if (test->order) test->order[slot] = test->index;
    }
    if (test->requeue_first && calls == 1)
        assert(queue_work(test->other ? test->other : test->wq, work));
    if (test->hold && calls == 1) {
        __atomic_store_n(&test->entered, 1, __ATOMIC_RELEASE);
        wait_for_completion(&test->gate);
    }
    if (calls < test->limit && !(test->requeue_first && calls == 1))
        queue_work(test->wq, work); /* A synchronous canceller can suppress it. */
    sched_yield();
    assert(__atomic_fetch_sub(&test->active, 1, __ATOMIC_ACQ_REL) == 1);
    if (test->free_self) kfree(test);
}
static void work_init(struct work_test *test, struct workqueue_struct *wq)
{
    *test = (struct work_test){ .wq = wq };
    INIT_WORK_ONSTACK(&test->work, work_callback);
    init_completion(&test->gate);
}
static void await_counter(unsigned int *counter)
{
    while (!__atomic_load_n(counter, __ATOMIC_ACQUIRE)) sched_yield();
}

enum work_operation { WORK_FLUSH, QUEUE_FLUSH, WORK_CANCEL, QUEUE_DRAIN, QUEUE_DESTROY };
struct work_operation_test {
    struct native_task_model model;
    struct workqueue_struct *wq;
    struct work_struct *work;
    enum work_operation operation;
    pthread_t thread;
    unsigned int done;
    bool result;
};
static void *work_operation_thread(void *argument)
{
    struct work_operation_test *test = argument;
    native_task = &test->model;
    if (test->operation == WORK_FLUSH) test->result = flush_work(test->work);
    if (test->operation == WORK_CANCEL) test->result = cancel_work_sync(test->work);
    if (test->operation == QUEUE_FLUSH) flush_workqueue(test->wq);
    if (test->operation == QUEUE_DRAIN) drain_workqueue(test->wq);
    if (test->operation == QUEUE_DESTROY) destroy_workqueue(test->wq);
    __atomic_store_n(&test->done, 1, __ATOMIC_RELEASE);
    native_task = NULL;
    return NULL;
}
static void operation_start(struct work_operation_test *test, enum work_operation operation,
                            struct workqueue_struct *wq, struct work_struct *work)
{
    *test = (struct work_operation_test){ .operation = operation, .wq = wq, .work = work };
    sync_model_init(&test->model, 30);
    /* A nonzero iteration makes the model's parked marker observable. */
    test->model.iteration = 1;
    assert(!pthread_create(&test->thread, NULL, work_operation_thread, test));
    while (!__atomic_load_n(&test->model.parked, __ATOMIC_ACQUIRE) &&
           !__atomic_load_n(&test->done, __ATOMIC_ACQUIRE)) sched_yield();
}
static void operation_join(struct work_operation_test *test)
{
    assert(!pthread_join(test->thread, NULL) && test->done);
    sync_model_destroy(&test->model);
}

static void work_order_tests(struct workqueue_struct *wq)
{
    struct work_test tests[32], hold;
    unsigned int order[32], count = 0;
    work_init(&hold, wq);
    hold.hold = true;
    assert(queue_work(wq, &hold.work));
    await_counter(&hold.entered);
    assert(work_busy(&hold.work) == WORK_BUSY_RUNNING);
    for (unsigned int i = 0; i < ARRAY_SIZE(tests); i++) {
        work_init(&tests[i], wq);
        tests[i].count = &count;
        tests[i].order = order;
        tests[i].index = i;
        assert(queue_work(wq, &tests[i].work));
        assert(!queue_work(wq, &tests[i].work));
        assert(work_pending(&tests[i].work));
    }
    assert(cancel_work(&tests[7].work) && !cancel_work(&tests[7].work));
    complete(&hold.gate);
    flush_workqueue(wq);
    assert(count == 31 && tests[7].calls == 0);
    for (unsigned int i = 0; i < count; i++) assert(order[i] == i + (i >= 7));
    assert(!flush_work(&hold.work) && !current_work());
    work_init(&hold, wq);
    hold.limit = 100;
    assert(queue_work(wq, &hold.work));
    drain_workqueue(wq); /* Must follow callback chaining through all requeues. */
    assert(hold.calls == 100 && !work_busy(&hold.work));
}

static void work_flush_tests(struct workqueue_struct *wq)
{
    for (unsigned int mode = 0; mode < 3; mode++) {
        struct work_test first, target, later;
        work_init(&first, wq); first.hold = true;
        work_init(&target, wq);
        work_init(&later, wq); later.hold = true;
        assert(queue_work(wq, &first.work)); await_counter(&first.entered);
        assert(queue_work(wq, &target.work));
        struct work_operation_test operation;
        operation_start(&operation, mode == 1 ? QUEUE_FLUSH : WORK_FLUSH, wq, &target.work);
        assert(!operation.done);
        if (mode == 2) assert(cancel_work(&target.work)); /* Its barrier survives cancellation. */
        assert(queue_work(wq, &later.work));
        complete(&first.gate);
        await_counter(&later.entered);
        operation_join(&operation); /* Later work is still sleeping. */
        assert(target.calls == (mode != 2) && (mode == 1 || operation.result));
        complete(&later.gate);
        drain_workqueue(wq);
    }
    struct work_test test;
    work_init(&test, wq); test.hold = true;
    assert(queue_work(wq, &test.work)); await_counter(&test.entered);
    struct work_operation_test operation;
    operation_start(&operation, WORK_FLUSH, wq, &test.work);
    assert(!operation.done);
    complete(&test.gate);
    operation_join(&operation);
    assert(operation.result);
}

static void work_cancel_tests(struct workqueue_struct *wq)
{
    for (unsigned int requeue = 0; requeue < 2; requeue++) {
        struct work_test test;
        work_init(&test, wq);
        test.hold = true; test.limit = 10; test.requeue_first = requeue;
        assert(queue_work(wq, &test.work)); await_counter(&test.entered);
        struct work_operation_test operation;
        operation_start(&operation, WORK_CANCEL, wq, &test.work);
        assert(!operation.done && !queue_work(wq, &test.work));
        complete(&test.gate);
        operation_join(&operation);
        assert(operation.result == !!requeue && test.calls == 1 && !work_busy(&test.work));
        assert(queue_work(wq, &test.work));
        drain_workqueue(wq);
        assert(test.calls == 10);
    }
}

struct work_producer {
    struct native_task_model model;
    struct work_test *test;
    struct workqueue_struct *wq;
    unsigned int accepted, canceled;
};
static void *work_producer_thread(void *argument)
{
    struct work_producer *producer = argument;
    native_task = &producer->model;
    for (unsigned int i = 0; i < 1000; i++) {
        producer->accepted += queue_work(producer->wq, &producer->test->work);
        producer->canceled += cancel_work(&producer->test->work);
        sched_yield();
    }
    native_task = NULL;
    return NULL;
}

static void workqueue_tests(void)
{
    struct native_task_model parent;
    sync_model_init(&parent, 20);
    native_task = &parent;
    size_t before = live_pages;
    assert(!alloc_workqueue("concurrent", 0, 0));
    assert(!alloc_workqueue("unbound", WQ_UNBOUND, 8));
    assert(!alloc_ordered_workqueue("reclaim", WQ_MEM_RECLAIM));
    assert(!alloc_ordered_workqueue("priority", WQ_HIGHPRI));
    assert(!alloc_ordered_workqueue("freezer", WQ_FREEZABLE));
    fail_allocation = true;
    assert(!alloc_ordered_workqueue("oom-%u", 0, 1));
    fail_allocation = false;
    struct workqueue_struct *a = alloc_ordered_workqueue("test-%u", 0, 1);
    struct workqueue_struct *b = alloc_ordered_workqueue("test-%u", 0, 2);
    assert(a && b);
    int warnings = atomic_read(&time_warnings);
    assert(!queue_work_on(1, a, &static_work) && !work_pending(&static_work));
    assert(atomic_read(&time_warnings) == warnings + 1);
    unsigned long irq_flags = vinix_linuxkpi_irq_save();
    assert(queue_work(a, &static_work) && !interrupts && !preempt_depth);
    vinix_linuxkpi_irq_restore(irq_flags);
    flush_workqueue(a);
    assert(static_work_calls == 1 && !work_busy(&static_work));
    work_order_tests(a);
    work_flush_tests(a);
    work_cancel_tests(a);

    for (unsigned int destroy = 0; destroy < 2; destroy++) {
        struct workqueue_struct *wq = destroy ? alloc_ordered_workqueue("destroy-held", 0) : a;
        assert(wq);
        struct work_test held, extra;
        work_init(&held, wq); held.hold = true; held.limit = 8;
        work_init(&extra, wq);
        assert(queue_work(wq, &held.work)); await_counter(&held.entered);
        struct work_operation_test operation;
        operation_start(&operation, destroy ? QUEUE_DESTROY : QUEUE_DRAIN, wq, NULL);
        assert(!operation.done && !queue_work(wq, &extra.work));
        complete(&held.gate);
        operation_join(&operation);
        assert(held.calls == 8 && !work_busy(&held.work));
        if (!destroy) {
            assert(queue_work(wq, &extra.work));
            flush_workqueue(wq);
            assert(extra.calls == 1);
        }
    }

    struct work_test cross;
    work_init(&cross, a); cross.other = b; cross.requeue_first = true; cross.hold = true;
    assert(queue_work(a, &cross.work)); await_counter(&cross.entered);
    struct work_operation_test flush;
    operation_start(&flush, WORK_FLUSH, b, &cross.work);
    assert(!flush.done && cross.calls == 1);
    complete(&cross.gate);
    operation_join(&flush);
    assert(flush.result && cross.calls == 2 && !cross.active);

    work_init(&cross, a); cross.other = b; cross.requeue_first = true; cross.hold = true;
    assert(queue_work(a, &cross.work)); await_counter(&cross.entered);
    operation_start(&flush, WORK_FLUSH, b, &cross.work);
    assert(!flush.done);
    /* The queued barrier can complete while the canceled work's old
     * callback is still running. The flush must retain that callback too. */
    flush.model.iteration = 2;
    assert(cancel_work(&cross.work));
    flush_workqueue(b);
    while (__atomic_load_n(&flush.model.parked, __ATOMIC_ACQUIRE) != 2 &&
           !__atomic_load_n(&flush.done, __ATOMIC_ACQUIRE)) sched_yield();
    assert(!flush.done && work_busy(&cross.work) == WORK_BUSY_RUNNING);
    complete(&cross.gate);
    operation_join(&flush);
    assert(flush.result && cross.calls == 1 && !work_busy(&cross.work));

    unsigned int freed = 0;
    for (unsigned int i = 0; i < 200; i++) {
        struct work_test *test = kzalloc(sizeof(*test), GFP_KERNEL);
        assert(test); work_init(test, a); test->free_self = true; test->count = &freed;
        assert(queue_work(a, &test->work));
    }
    flush_workqueue(a);
    assert(freed == 200);

    struct work_test shared;
    work_init(&shared, a);
    struct work_producer producers[4]; pthread_t threads[4];
    for (unsigned int i = 0; i < 4; i++) {
        producers[i] = (struct work_producer){ .test = &shared, .wq = i & 1 ? a : b };
        sync_model_init(&producers[i].model, i + 40);
        assert(!pthread_create(&threads[i], NULL, work_producer_thread, &producers[i]));
    }
    unsigned int accepted = 0, canceled = 0;
    for (unsigned int i = 0; i < 4; i++) {
        assert(!pthread_join(threads[i], NULL));
        accepted += producers[i].accepted; canceled += producers[i].canceled;
        sync_model_destroy(&producers[i].model);
    }
    canceled += cancel_work_sync(&shared.work);
    assert(accepted == canceled + shared.calls && !work_busy(&shared.work));
    destroy_workqueue(a); destroy_workqueue(b);

    for (unsigned int i = 0; i < 50; i++) {
        struct workqueue_struct *wq = alloc_ordered_workqueue("lifetime-%u", 0, i);
        assert(wq); struct work_test test; work_init(&test, wq);
        test.limit = 10; assert(queue_work(wq, &test.work));
        destroy_workqueue(wq); /* Includes chained work and worker exit. */
        assert(test.calls == 10 && live_pages == before && !atomic_read(&host_work_workers));
    }
    assert(live_pages == before && !parent.pins);
    native_task = NULL;
    sync_model_destroy(&parent);
}
