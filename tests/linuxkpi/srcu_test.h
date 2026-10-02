/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_SRCU_TEST_H
#define VINIX_SRCU_TEST_H

/* Included after the task, timing and workqueue models. Reader banks and
 * callbacks are observed through the unchanged public Linux interfaces. */
#include <linux/srcu.h>

void vinix_linuxkpi_srcu_static_quiesce_for_test(struct srcu_struct *ssp);
int vinix_linuxkpi_srcu_bootstrap_limit_for_test(unsigned int limit);
void vinix_linuxkpi_srcu_shutdown_for_test(void);
struct workqueue_struct *vinix_linuxkpi_srcu_queue_for_test(void);
DEFINE_STATIC_SRCU(srcu_static_test_domain);

struct srcu_test_clock {
    struct native_task_model model;
    pthread_t thread;
    unsigned int stop;
};

static void *srcu_test_clock_thread(void *argument)
{
    struct srcu_test_clock *clock = argument;
    native_task = &clock->model;
    current_cpu = 3;
    /* Public synchronous APIs may park the controller. An independent clock
     * keeps phased SRCU scans and sleeping readers progressing in that case. */
    while (!__atomic_load_n(&clock->stop, __ATOMIC_ACQUIRE)) {
        advance_delayed(1);
        sched_yield();
    }
    assert(interrupts && !preempt_depth);
    native_task = NULL;
    return NULL;
}

static void srcu_test_pump(void)
{
    advance_delayed(1);
    sched_yield();
}

static void srcu_test_wait(unsigned int *value, unsigned int target)
{
    for (unsigned int spin = 0; spin < 1000000; spin++) {
        if (__atomic_load_n(value, __ATOMIC_ACQUIRE) >= target) return;
        srcu_test_pump();
    }
    assert(!"SRCU operation did not make progress");
}

/* An existing reader prevents this GP from finishing. A different returned
 * token means new readers have moved to the other bank, without inspecting
 * updater-private state or reproducing its grace-period algorithm. */
static int srcu_test_wait_flip(struct srcu_struct *ssp, int old)
{
    for (unsigned int spin = 0; spin < 1000000; spin++) {
        int idx = srcu_read_lock(ssp);
        assert(idx == 0 || idx == 1);
        srcu_read_unlock(ssp, idx);
        if (idx != old) return idx;
        srcu_test_pump();
    }
    assert(!"SRCU reader bank did not change");
    return -1;
}

enum srcu_test_operation { SRCU_TEST_SYNC, SRCU_TEST_EXPEDITED, SRCU_TEST_BARRIER };
struct srcu_test_waiter {
    struct native_task_model model;
    struct srcu_struct *ssp;
    pthread_t thread;
    enum srcu_test_operation operation;
    unsigned int entered, done;
};

static void *srcu_test_waiter_thread(void *argument)
{
    struct srcu_test_waiter *waiter = argument;
    native_task = &waiter->model;
    current_cpu = 1;
    __atomic_store_n(&waiter->entered, 1, __ATOMIC_RELEASE);
    if (waiter->operation == SRCU_TEST_SYNC) synchronize_srcu(waiter->ssp);
    else if (waiter->operation == SRCU_TEST_EXPEDITED) synchronize_srcu_expedited(waiter->ssp);
    else srcu_barrier(waiter->ssp);
    assert(interrupts && !preempt_depth && task_is_running(current));
    __atomic_store_n(&waiter->done, 1, __ATOMIC_RELEASE);
    native_task = NULL;
    return NULL;
}

static void srcu_test_waiter_start(struct srcu_test_waiter *waiter,
                                 struct srcu_struct *ssp, enum srcu_test_operation operation)
{
    *waiter = (struct srcu_test_waiter){ .ssp = ssp, .operation = operation };
    sync_model_init(&waiter->model, 180);
    waiter->model.iteration = 1;
    assert(!pthread_create(&waiter->thread, NULL, srcu_test_waiter_thread, waiter));
    srcu_test_wait(&waiter->entered, 1);
}

static void srcu_test_waiter_join(struct srcu_test_waiter *waiter)
{
    srcu_test_wait(&waiter->done, 1);
    assert(!pthread_join(waiter->thread, NULL));
    sync_model_destroy(&waiter->model);
}

struct srcu_test_callback {
    struct rcu_head head;
    struct srcu_struct *ssp;
    unsigned int calls, limit, index;
    unsigned int entered, release;
    unsigned int *order, *count, *freed;
    bool gated, free_self;
};

static void srcu_test_callback_run(struct rcu_head *head)
{
    struct srcu_test_callback *test = container_of(head, struct srcu_test_callback, head);
    assert(preempt_depth && !vinix_linuxkpi_may_sleep());
    unsigned int call = __atomic_add_fetch(&test->calls, 1, __ATOMIC_ACQ_REL);
    if (test->count) {
        unsigned int slot = __atomic_fetch_add(test->count, 1, __ATOMIC_ACQ_REL);
        if (test->order) test->order[slot] = test->index;
    }
    if (test->gated) {
        __atomic_store_n(&test->entered, 1, __ATOMIC_RELEASE);
        /* This is a nonblocking spin gate, not a sleeping callback. */
        while (!__atomic_load_n(&test->release, __ATOMIC_ACQUIRE)) sched_yield();
    }
    if (call < test->limit) call_srcu(test->ssp, &test->head, srcu_test_callback_run);
    else if (test->free_self) {
        unsigned int *freed = test->freed;
        kfree(test);
        __atomic_fetch_add(freed, 1, __ATOMIC_RELEASE);
    }
}

static void srcu_test_callback_init(struct srcu_test_callback *test, struct srcu_struct *ssp)
{
    *test = (struct srcu_test_callback){ .ssp = ssp, .limit = 1 };
}

static void srcu_test_grace_periods(struct srcu_struct *ssp)
{
    for (unsigned int expedited = 0; expedited < 2; expedited++) {
        current_cpu = 0;
        int old = srcu_read_lock(ssp);
        int nested = srcu_read_lock(ssp);
        assert(old == nested && interrupts && !preempt_depth);
        struct srcu_test_waiter waiter;
        srcu_test_waiter_start(&waiter, ssp,
            expedited ? SRCU_TEST_EXPEDITED : SRCU_TEST_SYNC);
        int newer_bank = srcu_test_wait_flip(ssp, old);
        current_cpu = 2;
        int late = srcu_read_lock(ssp);
        assert(late == newer_bank);
        /* Nested unlocks can migrate independently; global counts, rather
         * than per-CPU lock/unlock equality, determine reader quiescence. */
        current_cpu = 3;
        srcu_read_unlock(ssp, nested);
        assert(!__atomic_load_n(&waiter.done, __ATOMIC_ACQUIRE));
        srcu_read_unlock(ssp, old);
        srcu_test_waiter_join(&waiter);
        /* The newer reader remains held after the original GP finishes. */
        current_cpu = 1;
        srcu_read_unlock(ssp, late);
    }
}

static void srcu_test_polling(struct srcu_struct *ssp)
{
    current_cpu = 0;
    int old = srcu_read_lock(ssp);
    struct srcu_test_waiter waiter;
    srcu_test_waiter_start(&waiter, ssp, SRCU_TEST_SYNC);
    int bank = srcu_test_wait_flip(ssp, old);
    current_cpu = 2;
    int late = srcu_read_lock(ssp);
    assert(late == bank);
    unsigned long observed = get_state_synchronize_srcu(ssp);
    unsigned long requested = start_poll_synchronize_srcu(ssp);
    assert(!poll_state_synchronize_srcu(ssp, observed));
    assert(!poll_state_synchronize_srcu(ssp, requested));
    current_cpu = 3;
    srcu_read_unlock(ssp, old);
    srcu_test_waiter_join(&waiter);
    /* Completion of the already-running GP does not satisfy either cookie.
     * A full following GP must account for this late-bank reader. */
    assert(!poll_state_synchronize_srcu(ssp, observed));
    assert(!poll_state_synchronize_srcu(ssp, requested));
    current_cpu = 0;
    srcu_read_unlock(ssp, late);
    for (unsigned int spin = 0; spin < 1000000; spin++) {
        if (poll_state_synchronize_srcu(ssp, requested)) break;
        srcu_test_pump();
    }
    assert(poll_state_synchronize_srcu(ssp, requested));
    assert(poll_state_synchronize_srcu(ssp, observed));
}

static void srcu_test_late_callback(struct srcu_struct *ssp)
{
    struct srcu_test_callback first, late;
    srcu_test_callback_init(&first, ssp);
    srcu_test_callback_init(&late, ssp);
    current_cpu = 0;
    int old = srcu_read_lock(ssp);
    call_srcu(ssp, &first.head, srcu_test_callback_run);
    int bank = srcu_test_wait_flip(ssp, old);
    current_cpu = 2;
    int held = srcu_read_lock(ssp);
    assert(held == bank);
    call_srcu(ssp, &late.head, srcu_test_callback_run);
    current_cpu = 3;
    srcu_read_unlock(ssp, old);
    srcu_test_wait(&first.calls, 1);
    assert(!__atomic_load_n(&late.calls, __ATOMIC_ACQUIRE));
    current_cpu = 1;
    srcu_read_unlock(ssp, held);
    srcu_test_wait(&late.calls, 1);
    srcu_barrier(ssp);
}

static void srcu_test_barrier_boundary(struct srcu_struct *ssp)
{
    struct srcu_test_callback first, late;
    srcu_test_callback_init(&first, ssp); first.gated = true;
    srcu_test_callback_init(&late, ssp);
    call_srcu(ssp, &first.head, srcu_test_callback_run);
    srcu_test_wait(&first.entered, 1);
    /* A grace period is distinct from callback completion. This synchronous
     * GP must return even while the detached callback is still running. */
    struct srcu_test_waiter sync, barriers[20];
    srcu_test_waiter_start(&sync, ssp, SRCU_TEST_SYNC);
    srcu_test_waiter_join(&sync);
    for (unsigned int i = 0; i < ARRAY_SIZE(barriers); i++) {
        srcu_test_waiter_start(&barriers[i], ssp, SRCU_TEST_BARRIER);
        srcu_test_wait(&barriers[i].model.parked, 1);
        assert(!__atomic_load_n(&barriers[i].done, __ATOMIC_ACQUIRE));
    }
    int reader = srcu_read_lock(ssp);
    call_srcu(ssp, &late.head, srcu_test_callback_run);
    __atomic_store_n(&first.release, 1, __ATOMIC_RELEASE);
    /* Every caller captures its boundary before any serialization mutex.
     * Otherwise later waiters would accidentally include this late callback. */
    for (unsigned int i = 0; i < ARRAY_SIZE(barriers); i++) srcu_test_waiter_join(&barriers[i]);
    assert(!__atomic_load_n(&late.calls, __ATOMIC_ACQUIRE));
    srcu_read_unlock(ssp, reader);
    srcu_test_wait(&late.calls, 1);
    srcu_barrier(ssp);
}

static void srcu_test_callbacks(struct srcu_struct *ssp)
{
    unsigned int order[200], count = 0, freed = 0;
    int reader = srcu_read_lock(ssp);
    for (unsigned int i = 0; i < ARRAY_SIZE(order); i++) {
        struct srcu_test_callback *test = kzalloc(sizeof(*test), GFP_KERNEL);
        assert(test); srcu_test_callback_init(test, ssp);
        test->index = i; test->order = order; test->count = &count;
        test->free_self = true; test->freed = &freed;
        call_srcu(ssp, &test->head, srcu_test_callback_run);
    }
    srcu_read_unlock(ssp, reader);
    srcu_test_wait(&freed, ARRAY_SIZE(order));
    srcu_barrier(ssp);
    assert(count == ARRAY_SIZE(order));
    for (unsigned int i = 0; i < ARRAY_SIZE(order); i++) assert(order[i] == i);

    struct srcu_test_callback *requeue = kzalloc(sizeof(*requeue), GFP_KERNEL);
    assert(requeue); srcu_test_callback_init(requeue, ssp);
    requeue->limit = 20; requeue->count = &count;
    requeue->free_self = true; requeue->freed = &freed;
    call_srcu(ssp, &requeue->head, srcu_test_callback_run);
    srcu_test_wait(&freed, ARRAY_SIZE(order) + 1);
    srcu_barrier(ssp);
    assert(count == ARRAY_SIZE(order) + 20);

    struct srcu_test_callback atomic_call;
    srcu_test_callback_init(&atomic_call, ssp);
    size_t before = live_pages;
    fail_allocation = true;
    unsigned long flags = vinix_linuxkpi_irq_save();
    call_srcu(ssp, &atomic_call.head, srcu_test_callback_run);
    assert(!interrupts);
    vinix_linuxkpi_irq_restore(flags);
    fail_allocation = false;
    srcu_test_wait(&atomic_call.calls, 1);
    srcu_barrier(ssp);
    vinix_linuxkpi_srcu_static_quiesce_for_test(ssp);
    assert(live_pages == before);
}

struct srcu_test_payload { unsigned long magic; };
#define SRCU_TEST_MAGIC 0xc001facedeadbeefUL
struct srcu_test_stress {
    struct srcu_struct *ssp;
    struct srcu_test_payload *payload;
    unsigned int ready, go, done;
};
struct srcu_test_stress_worker {
    struct native_task_model model;
    struct srcu_test_stress *test;
    bool writer;
    unsigned int index;
};

static void *srcu_test_stress_thread(void *argument)
{
    struct srcu_test_stress_worker *worker = argument;
    struct srcu_test_stress *test = worker->test;
    native_task = &worker->model;
    current_cpu = worker->index % 4;
    __atomic_fetch_add(&test->ready, 1, __ATOMIC_RELEASE);
    while (!__atomic_load_n(&test->go, __ATOMIC_ACQUIRE)) sched_yield();
    for (unsigned int round = 0; round < (worker->writer ? 40U : 200U); round++) {
        if (worker->writer) {
            struct srcu_test_payload *next = kzalloc(sizeof(*next), GFP_KERNEL);
            assert(next); next->magic = SRCU_TEST_MAGIC;
            struct srcu_test_payload *old = __atomic_exchange_n(&test->payload, next, __ATOMIC_ACQ_REL);
            if (round & 1) synchronize_srcu_expedited(test->ssp);
            else synchronize_srcu(test->ssp);
            kfree(old);
        } else {
            int outer = srcu_read_lock(test->ssp);
            int inner = srcu_read_lock(test->ssp);
            struct srcu_test_payload *payload = srcu_dereference(test->payload, test->ssp);
            assert(payload && payload->magic == SRCU_TEST_MAGIC);
            if (!(round % 4)) msleep(1);
            else sched_yield();
            /* This dereference after a real sleep detects premature reclaim. */
            assert(payload->magic == SRCU_TEST_MAGIC);
            current_cpu = (current_cpu + 1) % 4;
            srcu_read_unlock(test->ssp, inner);
            current_cpu = (current_cpu + 1) % 4;
            srcu_read_unlock(test->ssp, outer);
        }
    }
    assert(interrupts && !preempt_depth);
    __atomic_fetch_add(&test->done, 1, __ATOMIC_RELEASE);
    native_task = NULL;
    return NULL;
}

static void srcu_test_concurrency(struct srcu_struct *ssp)
{
    size_t before = live_pages;
    struct srcu_test_stress test = { .ssp = ssp };
    test.payload = kzalloc(sizeof(*test.payload), GFP_KERNEL);
    assert(test.payload); test.payload->magic = SRCU_TEST_MAGIC;
    struct srcu_test_stress_worker workers[8]; pthread_t threads[8];
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++) {
        workers[i] = (struct srcu_test_stress_worker){ .test = &test, .index = i, .writer = i >= 4 };
        sync_model_init(&workers[i].model, 190 + i);
        assert(!pthread_create(&threads[i], NULL, srcu_test_stress_thread, &workers[i]));
    }
    srcu_test_wait(&test.ready, ARRAY_SIZE(workers));
    __atomic_store_n(&test.go, 1, __ATOMIC_RELEASE);
    srcu_test_wait(&test.done, ARRAY_SIZE(workers));
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++) {
        assert(!pthread_join(threads[i], NULL));
        sync_model_destroy(&workers[i].model);
    }
    kfree(test.payload);
    assert(live_pages == before);
}

static void srcu_test_dynamic_lifetimes(void)
{
    size_t before = live_pages;
    unsigned int failures = 0, successes = 0;
    for (int stage = 0; stage < 8; stage++) {
        struct srcu_struct domain = {0};
        allocation_failure_after = stage;
        int result = init_srcu_struct(&domain);
        allocation_failure_after = -1;
        if (result) {
            assert(result == -ENOMEM && live_pages == before);
            failures++;
            /* A failed construction must leave the same storage reusable. */
            assert(!init_srcu_struct(&domain));
        } else successes++;
        int idx = srcu_read_lock(&domain);
        current_cpu = (current_cpu + 1) % 4;
        srcu_read_unlock(&domain, idx);
        cleanup_srcu_struct(&domain);
        assert(live_pages == before);
    }
    assert(failures && successes);
    for (unsigned int round = 0; round < 200; round++) {
        struct srcu_struct domain = {0};
        assert(!init_srcu_struct(&domain));
        int outer = srcu_read_lock(&domain), inner = srcu_read_lock(&domain);
        current_cpu = (current_cpu + 1) % 4;
        srcu_read_unlock(&domain, inner);
        current_cpu = (current_cpu + 1) % 4;
        srcu_read_unlock(&domain, outer);
        struct srcu_test_callback callback;
        srcu_test_callback_init(&callback, &domain);
        call_srcu(&domain, &callback.head, srcu_test_callback_run);
        srcu_test_wait(&callback.calls, 1);
        srcu_barrier(&domain);
        if (round & 1) synchronize_srcu_expedited(&domain);
        else synchronize_srcu(&domain);
        cleanup_srcu_struct(&domain);
        assert(live_pages == before);
    }
}

static void srcu_test_waiting_domains(void)
{
    /* The private test pool has two active slots. Three reader-blocked GPs
     * must return their worker slots between scans, allowing a ready domain
     * to advance independently instead of exhausting the whole service. */
    struct srcu_struct blocked[3] = {0}, ready = {0};
    struct srcu_test_callback callbacks[3], independent;
    int readers[3];
    size_t before = live_pages;
    for (unsigned int i = 0; i < ARRAY_SIZE(blocked); i++) {
        assert(!init_srcu_struct(&blocked[i]));
        readers[i] = srcu_read_lock(&blocked[i]);
        srcu_test_callback_init(&callbacks[i], &blocked[i]);
        call_srcu(&blocked[i], &callbacks[i].head, srcu_test_callback_run);
        srcu_test_wait_flip(&blocked[i], readers[i]);
    }
    assert(!init_srcu_struct(&ready));
    srcu_test_callback_init(&independent, &ready);
    call_srcu(&ready, &independent.head, srcu_test_callback_run);
    srcu_test_wait(&independent.calls, 1);
    cleanup_srcu_struct(&ready);
    for (unsigned int i = 0; i < ARRAY_SIZE(blocked); i++) {
        assert(!__atomic_load_n(&callbacks[i].calls, __ATOMIC_ACQUIRE));
        current_cpu = (current_cpu + 1) % 4;
        srcu_read_unlock(&blocked[i], readers[i]);
    }
    for (unsigned int i = 0; i < ARRAY_SIZE(blocked); i++) {
        srcu_test_wait(&callbacks[i].calls, 1);
        cleanup_srcu_struct(&blocked[i]);
    }
    assert(live_pages == before);
}

struct srcu_test_system_waiter {
    struct work_struct work;
    struct srcu_struct *ssp;
    unsigned int *entered, *done;
};
static void srcu_test_system_wait(struct work_struct *work)
{
    struct srcu_test_system_waiter *waiter = container_of(work, struct srcu_test_system_waiter, work);
    assert(vinix_linuxkpi_may_sleep());
    __atomic_fetch_add(waiter->entered, 1, __ATOMIC_RELEASE);
    synchronize_srcu(waiter->ssp);
    __atomic_fetch_add(waiter->done, 1, __ATOMIC_RELEASE);
}

static void srcu_test_system_saturation(void)
{
    /* All default system_unbound active slots wait for SRCU while its old
     * reader is held. SRCU must run on its own service queue; sharing the
     * saturated system pool would prevent even unrelated SRCU progress. */
    struct srcu_struct domain = {0}, ready = {0};
    assert(!init_srcu_struct(&domain) && !init_srcu_struct(&ready));
    int reader = srcu_read_lock(&domain);
    struct srcu_test_system_waiter waiters[WQ_DFL_ACTIVE];
    unsigned int entered = 0, done = 0;
    for (unsigned int i = 0; i < ARRAY_SIZE(waiters); i++) {
        waiters[i] = (struct srcu_test_system_waiter){ .ssp = &domain,
            .entered = &entered, .done = &done };
        INIT_WORK_ONSTACK(&waiters[i].work, srcu_test_system_wait);
        assert(queue_work(system_unbound_wq, &waiters[i].work));
    }
    srcu_test_wait(&entered, ARRAY_SIZE(waiters));
    assert(!__atomic_load_n(&done, __ATOMIC_ACQUIRE));
    struct srcu_test_callback independent;
    srcu_test_callback_init(&independent, &ready);
    call_srcu(&ready, &independent.head, srcu_test_callback_run);
    srcu_test_wait(&independent.calls, 1);
    cleanup_srcu_struct(&ready);
    srcu_read_unlock(&domain, reader);
    srcu_test_wait(&done, ARRAY_SIZE(waiters));
    for (unsigned int i = 0; i < ARRAY_SIZE(waiters); i++)
        assert(flush_work(&waiters[i].work) || done == ARRAY_SIZE(waiters));
    cleanup_srcu_struct(&domain);
}

static void srcu_tests(void)
{
    struct native_task_model parent;
    sync_model_init(&parent, 170); native_task = &parent;
    unsigned int saved_cpu = current_cpu;
    size_t before = live_pages;
    assert(!system_unbound_wq && !system_wq && !system_highpri_wq);
    assert(!vinix_linuxkpi_workqueue_bootstrap());
    size_t system_pages = live_pages;
    int system_workers = atomic_read(&host_work_workers);
    fail_allocation = true;
    assert(vinix_linuxkpi_srcu_bootstrap_limit_for_test(2) == -ENOMEM);
    fail_allocation = false;
    assert(live_pages == system_pages && atomic_read(&host_work_workers) == system_workers);
    unsigned int bootstrap_failures = 0, bootstrap_successes = 0;
    for (int stage = 0; stage < 8; stage++) {
        allocation_failure_after = stage;
        int result = vinix_linuxkpi_srcu_bootstrap_limit_for_test(2);
        allocation_failure_after = -1;
        if (result) {
            assert(result == -ENOMEM);
            bootstrap_failures++;
            assert(!vinix_linuxkpi_srcu_bootstrap_limit_for_test(2));
        } else bootstrap_successes++;
        struct workqueue_struct *initialized = vinix_linuxkpi_srcu_queue_for_test();
        assert(!vinix_linuxkpi_srcu_bootstrap_limit_for_test(2));
        assert(vinix_linuxkpi_srcu_queue_for_test() == initialized);
        vinix_linuxkpi_srcu_shutdown_for_test();
        assert(live_pages == system_pages && atomic_read(&host_work_workers) == system_workers);
    }
    assert(bootstrap_failures && bootstrap_successes);
    assert(!vinix_linuxkpi_srcu_bootstrap_limit_for_test(2));
    srcu_init();
    struct srcu_test_clock clock = {0};
    sync_model_init(&clock.model, 179);
    assert(!pthread_create(&clock.thread, NULL, srcu_test_clock_thread, &clock));
    /* Warm all worker allocations before checking per-domain retained pages. */
    struct workqueue_struct *queue = vinix_linuxkpi_srcu_queue_for_test();
    assert(queue && queue != system_unbound_wq);
    struct work_test warm[2];
    for (unsigned int i = 0; i < ARRAY_SIZE(warm); i++) {
        work_init(&warm[i], queue); warm[i].hold = true;
        assert(queue_work(queue, &warm[i].work));
    }
    for (unsigned int i = 0; i < ARRAY_SIZE(warm); i++) srcu_test_wait(&warm[i].entered, 1);
    for (unsigned int i = 0; i < ARRAY_SIZE(warm); i++) complete(&warm[i].gate);
    for (unsigned int i = 0; i < ARRAY_SIZE(warm); i++)
        assert(flush_work(&warm[i].work) || warm[i].calls == 1);
    /* Saturation itself warms the system queue's full retained worker peak. */
    srcu_test_system_saturation();
    size_t warmed = live_pages;

    srcu_test_waiting_domains();

    /* The original static per-CPU storage already admits readers before any
     * lazy updater initialization. Existing locks must survive that init. */
    current_cpu = 0;
    fail_allocation = true;
    int static_reader = srcu_read_lock(&srcu_static_test_domain);
    assert(live_pages == warmed);
    fail_allocation = false;
    struct srcu_test_waiter static_waiter;
    srcu_test_waiter_start(&static_waiter, &srcu_static_test_domain, SRCU_TEST_SYNC);
    srcu_test_wait_flip(&srcu_static_test_domain, static_reader);
    assert(!__atomic_load_n(&static_waiter.done, __ATOMIC_ACQUIRE));
    current_cpu = 3;
    srcu_read_unlock(&srcu_static_test_domain, static_reader);
    srcu_test_waiter_join(&static_waiter);
    srcu_test_grace_periods(&srcu_static_test_domain);
    srcu_test_polling(&srcu_static_test_domain);
    srcu_test_late_callback(&srcu_static_test_domain);
    srcu_test_barrier_boundary(&srcu_static_test_domain);
    srcu_test_callbacks(&srcu_static_test_domain);
    srcu_test_concurrency(&srcu_static_test_domain);
    assert(live_pages == warmed);
    srcu_test_dynamic_lifetimes();
    assert(live_pages == warmed);
    vinix_linuxkpi_srcu_static_quiesce_for_test(&srcu_static_test_domain);
    vinix_linuxkpi_srcu_shutdown_for_test();
    vinix_linuxkpi_workqueue_shutdown_for_test();
    __atomic_store_n(&clock.stop, 1, __ATOMIC_RELEASE);
    assert(!pthread_join(clock.thread, NULL));
    sync_model_destroy(&clock.model);
    assert(live_pages == before && !atomic_read(&host_work_workers));
    current_cpu = saved_cpu;
    native_task = NULL; sync_model_destroy(&parent);
}

#endif
