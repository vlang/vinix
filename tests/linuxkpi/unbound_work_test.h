/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Included after ordered/delayed tests for their controlled task model. */
void vinix_linuxkpi_workqueue_shutdown_for_test(void);
bool vinix_linuxkpi_host_workqueue_stopped(struct workqueue_struct *wq);
struct pool_publish_gate {
    struct workqueue_struct *wq;
    unsigned int cpu;
    unsigned int entered, release;
};
static struct pool_publish_gate *publish_gate;
void vinix_linuxkpi_host_pool_publish_gate(struct workqueue_struct *wq, unsigned int cpu)
{
    struct pool_publish_gate *gate = __atomic_load_n(&publish_gate, __ATOMIC_ACQUIRE);
    if (!gate || gate->wq != wq || gate->cpu != cpu) return;
    __atomic_store_n(&gate->entered, 1, __ATOMIC_RELEASE);
    while (!__atomic_load_n(&gate->release, __ATOMIC_ACQUIRE)) sched_yield();
}

static void unbound_publish_destroy_test(void)
{
    struct workqueue_struct *wq = alloc_workqueue("publish-destroy", WQ_UNBOUND, 2);
    assert(wq);
    struct work_test held, extra;
    work_init(&held, wq); held.hold = true;
    work_init(&extra, wq);
    assert(queue_work(wq, &held.work)); await_counter(&held.entered);
    struct pool_publish_gate gate = { .wq = wq };
    __atomic_store_n(&publish_gate, &gate, __ATOMIC_RELEASE);
    assert(queue_work(wq, &extra.work)); await_counter(&gate.entered);
    await_counter(&extra.calls);
    while (work_busy(&extra.work)) sched_yield();
    struct work_operation_test destroy;
    operation_start(&destroy, QUEUE_DESTROY, wq, NULL);
    complete(&held.gate);
    while (!vinix_linuxkpi_host_workqueue_stopped(wq)) sched_yield();
    assert(!destroy.done); /* Teardown must join the manager's publication. */
    __atomic_store_n(&gate.release, 1, __ATOMIC_RELEASE);
    operation_join(&destroy);
    __atomic_store_n(&publish_gate, NULL, __ATOMIC_RELEASE);
    assert(extra.calls == 1 && held.calls == 1 && !atomic_read(&host_work_workers));
}

static void unbound_limit_tests(unsigned int limit)
{
    struct workqueue_struct *wq = alloc_workqueue("limit-%u", WQ_UNBOUND, limit, limit);
    assert(wq);
    struct work_test held[4], extra;
    for (unsigned int i = 0; i < limit; i++) {
        work_init(&held[i], wq); held[i].hold = true;
        assert(queue_work(wq, &held[i].work));
    }
    for (unsigned int i = 0; i < limit; i++) await_counter(&held[i].entered);
    work_init(&extra, wq);
    assert(queue_work(wq, &extra.work));
    assert(work_busy(&extra.work) == WORK_BUSY_PENDING);
    assert((unsigned int)atomic_read(&host_work_workers) == limit + (limit > 1));
    complete(&held[0].gate);
    assert(flush_work(&extra.work) || extra.calls == 1);
    assert(extra.calls == 1 && !extra.active);
    /* An item flush must not wait for unrelated sleeping callbacks. */
    for (unsigned int i = 1; i < limit; i++) {
        assert(work_busy(&held[i].work) == WORK_BUSY_RUNNING);
        complete(&held[i].gate);
    }
    destroy_workqueue(wq);
}

static void unbound_flush_tests(struct workqueue_struct *wq)
{
    struct work_test old[2], later;
    for (unsigned int i = 0; i < ARRAY_SIZE(old); i++) {
        work_init(&old[i], wq); old[i].hold = true;
        assert(queue_work(wq, &old[i].work)); await_counter(&old[i].entered);
    }
    struct work_operation_test flush;
    operation_start(&flush, QUEUE_FLUSH, wq, NULL);
    assert(!flush.done);
    work_init(&later, wq); later.hold = true;
    assert(queue_work(wq, &later.work)); await_counter(&later.entered);
    complete(&old[0].gate);
    assert(flush_work(&old[0].work) || old[0].calls == 1);
    assert(!flush.done); /* A fast later callback must not hide an older one. */
    complete(&old[1].gate);
    operation_join(&flush);
    assert(work_busy(&later.work) == WORK_BUSY_RUNNING);
    complete(&later.gate); drain_workqueue(wq);

    /* Both concurrent flushers must retain their own queueing boundary. */
    work_init(&old[0], wq); old[0].hold = true;
    work_init(&old[1], wq); old[1].hold = true;
    work_init(&later, wq); later.hold = true;
    assert(queue_work(wq, &old[0].work)); await_counter(&old[0].entered);
    operation_start(&flush, QUEUE_FLUSH, wq, NULL);
    assert(queue_work(wq, &old[1].work)); await_counter(&old[1].entered);
    struct work_operation_test second;
    operation_start(&second, QUEUE_FLUSH, wq, NULL);
    assert(queue_work(wq, &later.work)); await_counter(&later.entered);
    complete(&old[0].gate);
    operation_join(&flush);
    assert(!second.done);
    complete(&old[1].gate);
    operation_join(&second);
    assert(work_busy(&later.work) == WORK_BUSY_RUNNING);
    complete(&later.gate);
    drain_workqueue(wq);
}

struct unbound_nested {
    struct work_struct work;
    struct workqueue_struct *wq;
    struct work_test target;
    struct completion done;
};
static void unbound_nested_callback(struct work_struct *work)
{
    struct unbound_nested *nested = container_of(work, struct unbound_nested, work);
    assert(queue_work(nested->wq, &nested->target.work));
    assert(flush_work(&nested->target.work) || nested->target.calls == 1);
    assert(nested->target.calls == 1 && !nested->target.active);
    complete(&nested->done);
}
static void unbound_item_tests(struct workqueue_struct *wq, struct workqueue_struct *other)
{
    struct unbound_nested nested = { .wq = wq };
    INIT_WORK_ONSTACK(&nested.work, unbound_nested_callback);
    work_init(&nested.target, wq); init_completion(&nested.done);
    assert(queue_work(wq, &nested.work)); wait_for_completion(&nested.done);
    flush_workqueue(wq);

    /* A blocked migrated requeue must not block independent work behind it. */
    struct work_test shared, independent;
    work_init(&shared, other); shared.hold = true;
    shared.other = wq; shared.requeue_first = true;
    assert(queue_work(other, &shared.work)); await_counter(&shared.entered);
    work_init(&independent, wq);
    assert(queue_work(wq, &independent.work));
    assert(flush_work(&independent.work) || independent.calls == 1);
    assert(shared.calls == 1 && independent.calls == 1);
    struct work_operation_test item_flush;
    operation_start(&item_flush, WORK_FLUSH, wq, &shared.work);
    assert(!item_flush.done);
    complete(&shared.gate);
    operation_join(&item_flush);
    assert(item_flush.result && shared.calls == 2 && !shared.active);
    drain_workqueue(other); drain_workqueue(wq);
}

static void unbound_generation_tests(struct workqueue_struct *wq, struct workqueue_struct *other)
{
    struct work_test shared, later;
    work_init(&shared, other); shared.hold = true;
    shared.requeue_first = true; shared.other = wq;
    assert(queue_work(other, &shared.work)); await_counter(&shared.entered);
    struct work_operation_test flush;
    operation_start(&flush, QUEUE_FLUSH, wq, NULL);
    work_init(&later, wq); later.hold = true;
    assert(queue_work(wq, &later.work)); await_counter(&later.entered);
    assert(!flush.done && shared.calls == 1);
    /* The old queued copy starts after later work, but belongs to the older
     * generation because it was queued before the snapshot. */
    complete(&shared.gate);
    operation_join(&flush);
    assert(shared.calls == 2 && !shared.active);
    assert(work_busy(&later.work) == WORK_BUSY_RUNNING);
    complete(&later.gate); drain_workqueue(wq); drain_workqueue(other);

    struct work_test held;
    work_init(&held, wq); held.hold = true;
    assert(queue_work(wq, &held.work)); await_counter(&held.entered);
    struct work_operation_test flushes[20];
    for (unsigned int i = 0; i < ARRAY_SIZE(flushes); i++)
        operation_start(&flushes[i], QUEUE_FLUSH, wq, NULL);
    work_init(&later, wq); later.hold = true;
    assert(queue_work(wq, &later.work)); await_counter(&later.entered);
    complete(&held.gate);
    for (unsigned int i = 0; i < ARRAY_SIZE(flushes); i++) operation_join(&flushes[i]);
    assert(work_busy(&later.work) == WORK_BUSY_RUNNING);
    complete(&later.gate); drain_workqueue(wq);
}

static void unbound_work_tests(void)
{
    struct native_task_model parent;
    sync_model_init(&parent, 120); native_task = &parent;
    size_t before = live_pages;
    unbound_limit_tests(1); unbound_limit_tests(2); unbound_limit_tests(4);
    unbound_publish_destroy_test();
    struct workqueue_struct *wq = alloc_workqueue("parallel", WQ_UNBOUND, 4);
    struct workqueue_struct *other = alloc_ordered_workqueue("other", 0);
    assert(wq && other);
    unbound_flush_tests(wq); unbound_item_tests(wq, other);
    unbound_generation_tests(wq, other);
    work_cancel_tests(wq); delayed_cancel_tests(wq);
    delayed_race_tests(wq, other);
    unsigned int freed = 0;
    for (unsigned int i = 0; i < 200; i++) {
        struct work_test *test = kzalloc(sizeof(*test), GFP_KERNEL);
        assert(test); work_init(test, wq);
        test->free_self = true; test->count = &freed;
        assert(queue_work(wq, &test->work));
    }
    flush_workqueue(wq); assert(freed == 200);
    destroy_workqueue(wq); destroy_workqueue(other);
    assert(live_pages == before && !atomic_read(&host_work_workers));

    fail_allocation = true;
    assert(vinix_linuxkpi_workqueue_bootstrap() == -ENOMEM && !system_unbound_wq);
    fail_allocation = false;
    assert(!vinix_linuxkpi_workqueue_bootstrap() && system_unbound_wq);
    struct workqueue_struct *system = system_unbound_wq;
    assert(!vinix_linuxkpi_workqueue_bootstrap() && system_unbound_wq == system);
    unbound_flush_tests(system);
    struct delayed_test delayed;
    delayed_init(&delayed, system);
    assert(queue_delayed_work(system, &delayed.work, 10000));
    assert(flush_delayed_work(&delayed.work) && delayed.calls == 1);
    assert(!cancel_delayed_work_sync(&delayed.work));
    vinix_linuxkpi_workqueue_shutdown_for_test();
    assert(!system_unbound_wq && live_pages == before && !atomic_read(&host_work_workers));
    native_task = NULL; sync_model_destroy(&parent);
}
