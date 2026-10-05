/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Included after unbound_work_test.h to reuse its controlled task model. */
struct bound_work_case {
    struct work_struct work;
    struct completion gate;
    unsigned int expected_cpu[4], observed_cpu[4];
    unsigned int calls, entered, active, request_sleep;
    unsigned int *freed;
    int expected_nice;
    bool hold_first, spin_first, free_self, check_cpu;
};

static void bound_callback(struct work_struct *work)
{
    struct bound_work_case *test = container_of(work, struct bound_work_case, work);
    assert(current_work() == work && vinix_linuxkpi_may_sleep());
    assert(__atomic_fetch_add(&test->active, 1, __ATOMIC_ACQ_REL) == 0);
    unsigned int call = __atomic_fetch_add(&test->calls, 1, __ATOMIC_ACQ_REL);
    assert(call < ARRAY_SIZE(test->expected_cpu));
    assert(vinix_linuxkpi_worker_nice() == test->expected_nice);
    assert(vinix_linuxkpi_worker_timeslice() == (test->expected_nice < 0 ? 10000u : 5000u));
    test->observed_cpu[call] = vinix_linuxkpi_cpu_id();
    assert(!test->check_cpu || test->observed_cpu[call] == test->expected_cpu[call]);
    sched_yield();
    assert(!test->check_cpu || vinix_linuxkpi_cpu_id() == test->expected_cpu[call]);
    if (!call) {
        __atomic_store_n(&test->entered, 1, __ATOMIC_RELEASE);
        if (test->spin_first)
            while (!__atomic_load_n(&test->request_sleep, __ATOMIC_ACQUIRE)) sched_yield();
        if (test->hold_first) wait_for_completion(&test->gate);
        assert(!test->check_cpu || vinix_linuxkpi_cpu_id() == test->expected_cpu[call]);
        assert(vinix_linuxkpi_worker_nice() == test->expected_nice);
    }
    assert(__atomic_fetch_sub(&test->active, 1, __ATOMIC_ACQ_REL) == 1);
    if (test->free_self) {
        __atomic_fetch_add(test->freed, 1, __ATOMIC_RELEASE);
        kfree(test);
    }
}

static void bound_case_init(struct bound_work_case *test, unsigned int cpu)
{
    *test = (struct bound_work_case){ .check_cpu = true };
    for (unsigned int i = 0; i < ARRAY_SIZE(test->expected_cpu); i++) test->expected_cpu[i] = cpu;
    INIT_WORK_ONSTACK(&test->work, bound_callback);
    init_completion(&test->gate);
}

static void bound_irq_cpu_switch(void) { current_cpu = (current_cpu + 1) % 4; }

static void bound_routing_tests(void)
{
    struct workqueue_struct *wq = alloc_workqueue("bound-route", 0, 1);
    assert(wq);
    for (unsigned int cpu = 0; cpu < 4; cpu++) {
        struct bound_work_case test;
        bound_case_init(&test, cpu);
        current_cpu = (cpu + 1) % 4;
        unsigned long flags = vinix_linuxkpi_irq_save();
        assert(queue_work_on(cpu, wq, &test.work));
        assert(!interrupts && !preempt_depth);
        vinix_linuxkpi_irq_restore(flags);
        flush_workqueue(wq);
        assert(test.calls == 1 && !work_busy(&test.work));
    }

    struct bound_work_case local;
    bound_case_init(&local, 2);
    current_cpu = 2;
    /* Restoring IRQs may migrate the producer after the enqueue boundary. */
    host_irq_restore_hook = bound_irq_cpu_switch;
    assert(queue_work(wq, &local.work));
    assert(current_cpu == 3 && !host_irq_restore_hook);
    flush_workqueue(wq);
    assert(local.calls == 1 && local.observed_cpu[0] == 2);

    bound_case_init(&local, 1);
    current_cpu = 1;
    unsigned long flags = vinix_linuxkpi_irq_save();
    assert(queue_work(wq, &local.work));
    assert(!interrupts && !preempt_depth);
    vinix_linuxkpi_irq_restore(flags);
    flush_workqueue(wq);
    assert(local.calls == 1);

    bound_case_init(&local, 0);
    assert(!queue_work_on(4, wq, &local.work));
    assert(!queue_work_on(-1, wq, &local.work));
    assert(!work_pending(&local.work));
    destroy_workqueue(wq);
}

static void bound_limit_tests(unsigned int limit)
{
    struct workqueue_struct *wq = alloc_workqueue("bound-limit-%u", 0, limit, limit);
    assert(wq);
    struct bound_work_case held[4][2], extra[4];
    for (unsigned int cpu = 0; cpu < 4; cpu++) {
        for (unsigned int slot = 0; slot < limit; slot++) {
            bound_case_init(&held[cpu][slot], cpu);
            held[cpu][slot].hold_first = true;
            assert(queue_work_on(cpu, wq, &held[cpu][slot].work));
            await_counter(&held[cpu][slot].entered);
        }
        bound_case_init(&extra[cpu], cpu);
        assert(queue_work_on(cpu, wq, &extra[cpu].work));
        assert(work_busy(&extra[cpu].work) == WORK_BUSY_PENDING);
    }
    /* Sleeping callbacks still consume the queue's per-CPU active limit. */
    for (unsigned int cpu = 0; cpu < 4; cpu++) {
        assert(!extra[cpu].calls);
        complete(&held[cpu][0].gate);
        assert(flush_work(&extra[cpu].work) || extra[cpu].calls == 1);
        assert(extra[cpu].calls == 1);
        for (unsigned int other = cpu + 1; other < 4; other++) assert(!extra[other].calls);
        for (unsigned int slot = 1; slot < limit; slot++) {
            assert(work_busy(&held[cpu][slot].work) == WORK_BUSY_RUNNING);
            complete(&held[cpu][slot].gate);
        }
    }
    destroy_workqueue(wq);
}

static void bound_runnable_test(void)
{
    struct workqueue_struct *wq = alloc_workqueue("bound-runnable", 0, 2);
    struct workqueue_struct *other = alloc_workqueue("bound-runnable-other", 0, 2);
    struct workqueue_struct *highpri = alloc_workqueue("bound-runnable-highpri", WQ_HIGHPRI, 2);
    assert(wq && other && highpri);
    struct bound_work_case running, next, cross_owner, priority;
    bound_case_init(&running, 1); running.hold_first = true; running.spin_first = true;
    bound_case_init(&next, 1);
    assert(queue_work_on(1, wq, &running.work)); await_counter(&running.entered);
    assert(queue_work_on(1, wq, &next.work));
    bound_case_init(&cross_owner, 1);
    assert(queue_work_on(1, other, &cross_owner.work));
    bound_case_init(&priority, 1);
    priority.expected_nice = -20;
    assert(queue_work_on(1, highpri, &priority.work));
    assert(flush_work(&priority.work) || priority.calls == 1);
    /* A runnable callback suppresses extra bound workers even though an active
     * slot is free. Host yields here do not park the callback's native task. */
    for (unsigned int i = 0; i < 10000; i++) sched_yield();
    assert(!next.calls && !cross_owner.calls && work_busy(&next.work) == WORK_BUSY_PENDING);
    __atomic_store_n(&running.request_sleep, 1, __ATOMIC_RELEASE);
    await_counter(&next.entered);
    await_counter(&cross_owner.entered);
    assert(flush_work(&next.work) || next.calls == 1);
    assert(flush_work(&cross_owner.work) || cross_owner.calls == 1);
    /* Parking permits a replacement worker without releasing the active slot. */
    assert(work_busy(&running.work) == WORK_BUSY_RUNNING && running.calls == 1);
    complete(&running.gate);
    destroy_workqueue(wq);
    destroy_workqueue(other); destroy_workqueue(highpri);
}

static void bound_priority_tests(void)
{
    assert(vinix_linuxkpi_worker_nice() == 0 && vinix_linuxkpi_worker_timeslice() == 5000);
    for (unsigned int mode = 0; mode < 3; mode++) {
        struct workqueue_struct *wq = mode == 2 ?
            alloc_ordered_workqueue("priority-ordered", WQ_HIGHPRI) :
            alloc_workqueue("priority-%u", WQ_HIGHPRI | (mode ? WQ_UNBOUND : 0), 2, mode);
        assert(wq);
        struct bound_work_case test;
        bound_case_init(&test, 3); test.expected_nice = -20;
        test.check_cpu = mode == 0; test.hold_first = true;
        assert(mode ? queue_work(wq, &test.work) : queue_work_on(3, wq, &test.work));
        await_counter(&test.entered);
        /* Worker priority belongs to that thread; parent/kernel process
         * scheduling parameters must remain independent of its worker. */
        assert(vinix_linuxkpi_worker_nice() == 0 && vinix_linuxkpi_worker_timeslice() == 5000);
        complete(&test.gate); destroy_workqueue(wq);
        assert(test.calls == 1 && vinix_linuxkpi_worker_nice() == 0);
    }
    struct workqueue_struct *normal = alloc_ordered_workqueue("priority-normal", 0);
    assert(normal);
    struct bound_work_case test;
    bound_case_init(&test, 0); test.check_cpu = false;
    assert(queue_work(normal, &test.work)); destroy_workqueue(normal);
    assert(test.calls == 1);
}

static void bound_migration_tests(void)
{
    struct workqueue_struct *a = alloc_workqueue("bound-owner-a", 0, 2);
    struct workqueue_struct *b = alloc_workqueue("bound-owner-b", 0, 2);
    assert(a && b);
    struct bound_work_case shared, independent;
    bound_case_init(&shared, 1); shared.hold_first = true;
    assert(queue_work_on(1, a, &shared.work)); await_counter(&shared.entered);
    current_cpu = 3;
    assert(queue_work_on(3, a, &shared.work));
    assert(work_busy(&shared.work) == (WORK_BUSY_RUNNING | WORK_BUSY_PENDING));
    complete(&shared.gate); drain_workqueue(a);
    /* Requeueing on the same owner stays with its executing pool. */
    assert(shared.calls == 2 && shared.observed_cpu[1] == 1);

    bound_case_init(&shared, 1); shared.expected_cpu[1] = 3; shared.hold_first = true;
    assert(queue_work_on(1, a, &shared.work)); await_counter(&shared.entered);
    assert(queue_work_on(3, b, &shared.work));
    bound_case_init(&independent, 3);
    assert(queue_work_on(3, b, &independent.work));
    assert(flush_work(&independent.work) || independent.calls == 1);
    assert(independent.calls == 1 && shared.calls == 1);
    struct work_operation_test item_flush;
    operation_start(&item_flush, WORK_FLUSH, b, &shared.work);
    assert(!item_flush.done);
    complete(&shared.gate); operation_join(&item_flush);
    assert(item_flush.result && shared.calls == 2 && shared.observed_cpu[1] == 3);
    destroy_workqueue(a); destroy_workqueue(b);
}

static void bound_flush_tests(void)
{
    struct workqueue_struct *wq = alloc_workqueue("bound-flush", 0, 2);
    assert(wq);
    struct bound_work_case old[4], later[4];
    for (unsigned int cpu = 0; cpu < 4; cpu++) {
        bound_case_init(&old[cpu], cpu); old[cpu].hold_first = true;
        assert(queue_work_on(cpu, wq, &old[cpu].work)); await_counter(&old[cpu].entered);
    }
    struct work_operation_test first;
    operation_start(&first, QUEUE_FLUSH, wq, NULL);
    assert(!first.done);
    for (unsigned int cpu = 0; cpu < 4; cpu++) {
        bound_case_init(&later[cpu], cpu); later[cpu].hold_first = true;
        assert(queue_work_on(cpu, wq, &later[cpu].work)); await_counter(&later[cpu].entered);
    }
    struct work_operation_test second;
    operation_start(&second, QUEUE_FLUSH, wq, NULL);
    for (unsigned int cpu = 0; cpu < 4; cpu++) complete(&old[cpu].gate);
    /* A public queue flush snapshots every pool at one boundary. Sequential
     * per-CPU flushes incorrectly include later work while visiting new CPUs. */
    operation_join(&first);
    assert(!second.done);
    for (unsigned int cpu = 0; cpu < 4; cpu++) {
        assert(work_busy(&later[cpu].work) == WORK_BUSY_RUNNING);
        complete(&later[cpu].gate);
    }
    operation_join(&second);
    destroy_workqueue(wq);
}

struct bound_delayed_case {
    struct delayed_work work;
    struct completion gate;
    unsigned int expected_cpu[2], observed_cpu[2], calls, entered, active;
    bool hold_first;
};

static void bound_delayed_callback(struct work_struct *work)
{
    struct bound_delayed_case *test = container_of(to_delayed_work(work), struct bound_delayed_case, work);
    assert(vinix_linuxkpi_may_sleep() && current_work() == work);
    assert(__atomic_fetch_add(&test->active, 1, __ATOMIC_ACQ_REL) == 0);
    unsigned int call = __atomic_fetch_add(&test->calls, 1, __ATOMIC_ACQ_REL);
    assert(call < ARRAY_SIZE(test->expected_cpu));
    test->observed_cpu[call] = vinix_linuxkpi_cpu_id();
    assert(test->observed_cpu[call] == test->expected_cpu[call]);
    if (!call) {
        __atomic_store_n(&test->entered, 1, __ATOMIC_RELEASE);
        if (test->hold_first) wait_for_completion(&test->gate);
    }
    assert(vinix_linuxkpi_cpu_id() == test->expected_cpu[call]);
    assert(__atomic_fetch_sub(&test->active, 1, __ATOMIC_ACQ_REL) == 1);
}

static void bound_delayed_init(struct bound_delayed_case *test, unsigned int cpu)
{
    *test = (struct bound_delayed_case){ .expected_cpu = { cpu, cpu } };
    INIT_DELAYED_WORK_ONSTACK(&test->work, bound_delayed_callback);
    init_completion(&test->gate);
}

static void bound_delayed_tests(void)
{
    struct workqueue_struct *wq = alloc_workqueue("bound-delayed", 0, 2);
    assert(wq);
    struct bound_delayed_case test;
    bound_delayed_init(&test, 3);
    current_cpu = 0;
    unsigned long flags = vinix_linuxkpi_irq_save();
    assert(queue_delayed_work_on(3, wq, &test.work, 5));
    assert(!interrupts && !preempt_depth);
    vinix_linuxkpi_irq_restore(flags);
    current_cpu = 1; advance_delayed(5); flush_workqueue(wq);
    assert(test.calls == 1 && test.observed_cpu[0] == 3);

    bound_delayed_init(&test, 2);
    assert(queue_delayed_work_on(0, wq, &test.work, 10));
    flags = vinix_linuxkpi_irq_save();
    assert(mod_delayed_work_on(2, wq, &test.work, 2));
    assert(!interrupts && !preempt_depth);
    vinix_linuxkpi_irq_restore(flags);
    current_cpu = 3; advance_delayed(2); flush_workqueue(wq);
    assert(test.calls == 1 && test.observed_cpu[0] == 2);

    bound_delayed_init(&test, 1); test.expected_cpu[1] = 3; test.hold_first = true;
    assert(queue_delayed_work_on(1, wq, &test.work, 0)); await_counter(&test.entered);
    assert(queue_delayed_work_on(3, wq, &test.work, 5));
    complete(&test.gate); flush_workqueue(wq);
    assert(test.calls == 1 && timer_pending(&test.work.timer));
    /* A nonzero reservation keeps the requested CPU. If the previous callback
     * finishes before timer transfer, it no longer redirects execution. */
    advance_delayed(5); flush_workqueue(wq);
    assert(test.calls == 2 && test.observed_cpu[1] == 3);

    bound_delayed_init(&test, 0);
    assert(!queue_delayed_work_on(4, wq, &test.work, 1));
    assert(!mod_delayed_work_on(-1, wq, &test.work, 1));
    assert(!delayed_work_pending(&test.work) && !timer_pending(&test.work.timer));
    current_cpu = 0;
    delayed_cancel_tests(wq);
    destroy_workqueue(wq);
}

static void bound_failure_tests(void)
{
    size_t before = live_pages;
    unsigned int failures = 0, successes = 0;
    for (int allocation = 0; allocation < 24; allocation++) {
        allocation_failure_after = allocation;
        struct workqueue_struct *wq = alloc_workqueue("bound-partial-oom", 0, 2);
        allocation_failure_after = -1;
        if (wq) { successes++; destroy_workqueue(wq); }
        else failures++;
        assert(live_pages == before && !atomic_read(&host_work_workers));
    }
    assert(failures && successes);
    worker_bind_failure_after = 0;
    assert(!alloc_workqueue("bound-constructor-bind-failure", 0, 2));
    worker_bind_failure_after = -1;
    assert(live_pages == before && !atomic_read(&host_work_workers));

    struct workqueue_struct *wq = alloc_workqueue("bound-bind-failure", 0, 2);
    assert(wq);
    struct bound_work_case test;
    bound_case_init(&test, 2);
    unsigned int failed = __atomic_load_n(&worker_bind_failures, __ATOMIC_ACQUIRE);
    worker_bind_failure_after = 0;
    assert(queue_work_on(2, wq, &test.work));
    while (__atomic_load_n(&worker_bind_failures, __ATOMIC_ACQUIRE) == failed) sched_yield();
    worker_bind_failure_after = -1;
    /* Failed worker creation must release its retained task and permit retry. */
    while (!__atomic_load_n(&test.entered, __ATOMIC_ACQUIRE)) {
        advance_delayed(1);
        sched_yield();
    }
    flush_workqueue(wq);
    assert(test.calls == 1);
    destroy_workqueue(wq);
    assert(live_pages == before && !atomic_read(&host_work_workers));
}

static void bound_publish_destroy_test(void)
{
    struct workqueue_struct *wq = alloc_workqueue("bound-publish-destroy", 0, 2);
    assert(wq);
    struct bound_work_case held, extra;
    bound_case_init(&held, 2); held.hold_first = true;
    bound_case_init(&extra, 3);
    assert(queue_work_on(2, wq, &held.work)); await_counter(&held.entered);
    // The held callback can start before its lazy worker is published.
    // Gate only CPU 3 so that CPU 2's publication cannot trap the manager.
    struct pool_publish_gate gate = { .wq = wq, .cpu = 3 };
    __atomic_store_n(&publish_gate, &gate, __ATOMIC_RELEASE);
    assert(queue_work_on(3, wq, &extra.work)); await_counter(&gate.entered);
    await_counter(&extra.entered);
    while (work_busy(&extra.work)) sched_yield();
    struct work_operation_test destroy;
    operation_start(&destroy, QUEUE_DESTROY, wq, NULL);
    complete(&held.gate);
    while (!vinix_linuxkpi_host_workqueue_stopped(wq)) sched_yield();
    assert(!destroy.done);
    __atomic_store_n(&gate.release, 1, __ATOMIC_RELEASE);
    operation_join(&destroy);
    __atomic_store_n(&publish_gate, NULL, __ATOMIC_RELEASE);
    assert(held.calls == 1 && extra.calls == 1 && !atomic_read(&host_work_workers));
}

static void bound_system_tests(void)
{
    size_t before = live_pages;
    unsigned int failures = 0, successes = 0;
    assert(!system_wq && !system_highpri_wq && !system_unbound_wq);
    for (int allocation = 0; allocation < 32; allocation++) {
        allocation_failure_after = allocation;
        int result = vinix_linuxkpi_workqueue_bootstrap();
        allocation_failure_after = -1;
        if (result) {
            failures++;
            assert(result == -ENOMEM && !system_wq && !system_highpri_wq && !system_unbound_wq);
        } else {
            successes++;
            assert(system_wq && system_highpri_wq && system_unbound_wq);
            vinix_linuxkpi_workqueue_shutdown_for_test();
        }
        assert(live_pages == before && !atomic_read(&host_work_workers));
    }
    assert(failures && successes);
    assert(!vinix_linuxkpi_workqueue_bootstrap());
    struct workqueue_struct *normal = system_wq, *highpri = system_highpri_wq, *unbound = system_unbound_wq;
    assert(!vinix_linuxkpi_workqueue_bootstrap());
    assert(system_wq == normal && system_highpri_wq == highpri && system_unbound_wq == unbound);

    struct bound_work_case local, remote, priority, generic;
    current_cpu = 2;
    bound_case_init(&local, 2); assert(schedule_work(&local.work));
    bound_case_init(&remote, 3); assert(schedule_work_on(3, &remote.work));
    bound_case_init(&priority, 1); priority.expected_nice = -20;
    assert(queue_work_on(1, system_highpri_wq, &priority.work));
    bound_case_init(&generic, 0); generic.check_cpu = false;
    assert(queue_work(system_unbound_wq, &generic.work));
    assert(flush_work(&local.work) || local.calls == 1);
    assert(flush_work(&remote.work) || remote.calls == 1);
    assert(flush_work(&priority.work) || priority.calls == 1);
    assert(flush_work(&generic.work) || generic.calls == 1);
    assert(local.calls == 1 && remote.calls == 1 && priority.calls == 1 && generic.calls == 1);
    assert(vinix_linuxkpi_worker_nice() == 0);
    vinix_linuxkpi_workqueue_shutdown_for_test();
    assert(!system_wq && !system_highpri_wq && !system_unbound_wq);
    assert(live_pages == before && !atomic_read(&host_work_workers));
}

static void bound_work_tests(void)
{
    struct native_task_model parent;
    sync_model_init(&parent, 130); native_task = &parent;
    unsigned int previous_cpu = current_cpu;
    size_t before = live_pages;
    bound_routing_tests(); bound_limit_tests(1); bound_limit_tests(2);
    bound_runnable_test(); bound_priority_tests(); bound_migration_tests(); bound_flush_tests();
    bound_delayed_tests(); bound_failure_tests(); bound_publish_destroy_test();
    bound_system_tests();

    struct workqueue_struct *wq = alloc_workqueue("bound-free", 0, 1);
    assert(wq);
    unsigned int freed = 0;
    for (unsigned int i = 0; i < 200; i++) {
        struct bound_work_case *test = kzalloc(sizeof(*test), GFP_KERNEL);
        assert(test); bound_case_init(test, i % 4);
        test->free_self = true; test->freed = &freed;
        assert(queue_work_on(i % 4, wq, &test->work));
    }
    flush_workqueue(wq); assert(freed == 200);
    current_cpu = 0;
    work_order_tests(wq); work_cancel_tests(wq);
    destroy_workqueue(wq);
    assert(live_pages == before && !atomic_read(&host_work_workers));
    current_cpu = previous_cpu;
    native_task = NULL; sync_model_destroy(&parent);
}
