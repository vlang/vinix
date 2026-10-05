/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <linux/timer.h>

enum timer_test_mode { TIMER_COUNT, TIMER_REARM, TIMER_HOLD, TIMER_FREE, TIMER_STOP };
struct timer_test {
    struct timer_list timer;
    unsigned int calls, entered, release;
    bool irq_safe, rearm_held;
    enum timer_test_mode mode;
    unsigned long rearm_delay;
    unsigned int *free_count;
};

static void timer_test_callback(struct timer_list *timer)
{
    struct timer_test *test = from_timer(test, timer, timer);
    assert(!vinix_linuxkpi_may_sleep() && preempt_count());
    assert(!!(vinix_linuxkpi_irq_flags() & (1UL << 9)) != test->irq_safe);
    assert(!timer_pending(timer) && time_after_eq(jiffies, timer->expires));
    __atomic_fetch_add(&test->calls, 1, __ATOMIC_RELEASE);
    assert(try_to_del_timer_sync(timer) == -1); /* Nonblocking self-query. */
    if (test->mode == TIMER_REARM) assert(!mod_timer(timer, jiffies));
    if (test->mode == TIMER_HOLD) {
        if (test->rearm_held) assert(!mod_timer(timer, jiffies + test->rearm_delay));
        __atomic_store_n(&test->entered, 1, __ATOMIC_RELEASE);
        /* Host-only gate models a callback running on another CPU. */
        while (!__atomic_load_n(&test->release, __ATOMIC_ACQUIRE)) sched_yield();
    }
    if (test->mode == TIMER_STOP) {
        assert(!timer_shutdown(timer));
        assert(!mod_timer(timer, jiffies));
    }
    if (test->mode == TIMER_FREE) {
        __atomic_fetch_add(test->free_count, 1, __ATOMIC_RELEASE);
        kfree(test); /* Dispatch must never dereference this timer again. */
    }
}

static void timer_test_init(struct timer_test *test, enum timer_test_mode mode, bool irq_safe)
{
    *test = (struct timer_test){ .mode = mode, .irq_safe = irq_safe };
    timer_setup_on_stack(&test->timer, timer_test_callback, irq_safe ? TIMER_IRQSAFE : 0);
}

static unsigned int static_timer_calls;
static void static_timer_callback(struct timer_list *timer) { static_timer_calls++; }
static DEFINE_TIMER(static_timer, static_timer_callback);

static void timer_queue_tests(void)
{
    struct timer_test test;
    timer_test_init(&test, TIMER_COUNT, false);
    assert(!vinix_linuxkpi_timer_selftest());
    assert(!timer_pending(&test.timer) && !mod_timer_pending(&test.timer, jiffies));
    unsigned long expires = jiffies + 10;
    assert(!mod_timer(&test.timer, expires) && timer_pending(&test.timer));
    assert(mod_timer(&test.timer, expires) == 1);
    int warnings = atomic_read(&time_warnings);
    add_timer(&test.timer);
    add_timer(&test.timer);
    assert(test.timer.expires == expires && atomic_read(&time_warnings) == warnings + 1);
    assert(timer_reduce(&test.timer, expires + 2) == 1 && test.timer.expires == expires);
    assert(timer_reduce(&test.timer, expires - 1) == 1 && test.timer.expires == expires - 1);
    assert(mod_timer_pending(&test.timer, expires) == 1 && test.timer.expires == expires);
    host_time_advance(9);
    assert(!vinix_linuxkpi_timer_dispatch() && !test.calls);
    host_time_advance(1);
    /* The timer is still pending after expiry promotion, until dispatch. */
    assert(timer_pending(&test.timer) && vinix_linuxkpi_timer_active() == 1);
    assert(vinix_linuxkpi_timer_dispatch() == 1 && test.calls == 1);
    assert(!timer_pending(&test.timer) && !timer_delete(&test.timer));

    test.timer.expires = jiffies - 3;
    add_timer(&test.timer);
    assert(!vinix_linuxkpi_timer_dispatch()); /* Past deadlines wait for a tick. */
    host_time_advance(1);
    assert(vinix_linuxkpi_timer_dispatch() == 1 && test.calls == 2);
    assert(!mod_timer(&test.timer, jiffies + 2));
    host_time_advance(2);
    assert(timer_delete(&test.timer) == 1); /* Cancel promoted, uncalled timer. */
    assert(!vinix_linuxkpi_timer_dispatch());
    assert(!timer_reduce(&test.timer, jiffies + 2));
    assert(timer_shutdown_sync(&test.timer) == 1 && !test.timer.function);
    assert(!mod_timer(&test.timer, jiffies) && !mod_timer_pending(&test.timer, jiffies));
    test.timer.expires = jiffies;
    add_timer(&test.timer);
    assert(!timer_pending(&test.timer));
    timer_setup(&test.timer, timer_test_callback, 0); /* Reinitialize after shutdown. */
    assert(!mod_timer(&test.timer, jiffies + 1));
    assert(timer_delete_sync(&test.timer) == 1 && test.timer.function);
    destroy_timer_on_stack(&test.timer);

    static_timer.expires = jiffies + 1;
    add_timer(&static_timer);
    host_time_advance(1);
    assert(vinix_linuxkpi_timer_dispatch() == 1 && static_timer_calls == 1);
    assert(!timer_shutdown_sync(&static_timer));
    for (unsigned int safe = 0; safe < 2; safe++) {
        timer_test_init(&test, TIMER_REARM, safe);
        assert(!mod_timer(&test.timer, jiffies));
        for (unsigned int i = 1; i <= 20; i++) {
            host_time_advance(1);
            assert(vinix_linuxkpi_timer_dispatch() == 1 && test.calls == i);
            assert(!vinix_linuxkpi_timer_dispatch() && timer_pending(&test.timer));
        }
        assert(timer_shutdown_sync(&test.timer) == 1);
        assert(interrupts && !preempt_depth);
    }
    timer_test_init(&test, TIMER_STOP, false);
    assert(!mod_timer(&test.timer, jiffies));
    host_time_advance(1);
    assert(vinix_linuxkpi_timer_dispatch() == 1 && !test.timer.function);
    timer_test_init(&test, TIMER_COUNT, true);
    assert(!mod_timer(&test.timer, jiffies + 10));
    unsigned long flags = vinix_linuxkpi_irq_save();
    assert(timer_delete_sync(&test.timer) == 1 && !interrupts && !preempt_depth);
    assert(!timer_shutdown_sync(&test.timer) && !interrupts && !preempt_depth);
    vinix_linuxkpi_irq_restore(flags);
    assert(interrupts && !preempt_depth);
    assert(!vinix_linuxkpi_timer_active());
}

struct timer_thread_test {
    struct native_task_model model;
    struct timer_test *test;
    unsigned int spins, finished;
    bool shutdown;
    int result;
};
static void *timer_dispatch_thread(void *argument)
{
    struct timer_thread_test *test = argument;
    native_task = &test->model;
    test->result = vinix_linuxkpi_timer_dispatch();
    native_task = NULL;
    return NULL;
}
static void *timer_delete_thread(void *argument)
{
    struct timer_thread_test *test = argument;
    native_task = &test->model;
    timer_sync_spins = &test->spins;
    test->result = test->shutdown ? timer_shutdown_sync(&test->test->timer) : timer_delete_sync(&test->test->timer);
    timer_sync_spins = NULL;
    __atomic_store_n(&test->finished, 1, __ATOMIC_RELEASE);
    native_task = NULL;
    return NULL;
}

static void timer_running_tests(void)
{
    for (unsigned int shutdown = 0; shutdown < 2; shutdown++) {
        for (unsigned int rearm = 0; rearm < 2; rearm++) {
            struct timer_test test;
            timer_test_init(&test, TIMER_HOLD, shutdown);
            test.rearm_held = rearm;
            if (shutdown) test.rearm_delay = 100;
            struct timer_thread_test dispatch = { .test = &test }, deletion = { .test = &test, .shutdown = shutdown };
            sync_model_init(&dispatch.model, 1);
            sync_model_init(&deletion.model, 2);
            assert(!mod_timer(&test.timer, jiffies));
            host_time_advance(1);
            pthread_t caller, deleter;
            assert(!pthread_create(&caller, NULL, timer_dispatch_thread, &dispatch));
            while (!__atomic_load_n(&test.entered, __ATOMIC_ACQUIRE)) sched_yield();
            assert(try_to_del_timer_sync(&test.timer) == -1);
            host_time_advance(1);
            assert(!vinix_linuxkpi_timer_dispatch()); /* A rearmed callback cannot overlap itself. */
            assert(!pthread_create(&deleter, NULL, timer_delete_thread, &deletion));
            while (!__atomic_load_n(&deletion.spins, __ATOMIC_ACQUIRE)) sched_yield();
            assert(!__atomic_load_n(&deletion.finished, __ATOMIC_ACQUIRE));
            /* Async deletion removes the rearm while the callback runs.
             * Sync shutdown must remove it itself after the callback exits. */
            if (!shutdown) assert(timer_delete(&test.timer) == (int)rearm);
            __atomic_store_n(&test.release, 1, __ATOMIC_RELEASE);
            assert(!pthread_join(caller, NULL) && !pthread_join(deleter, NULL));
            assert(dispatch.result == 1 && deletion.result == (int)(shutdown && rearm) && test.calls == 1);
            assert(!timer_pending(&test.timer) && !!test.timer.function != !!shutdown);
            sync_model_destroy(&dispatch.model);
            sync_model_destroy(&deletion.model);
            host_time_advance(20);
            assert(!vinix_linuxkpi_timer_dispatch() && !vinix_linuxkpi_timer_active());
        }
    }
    /* Async shutdown must disable an in-flight callback's further rearming. */
    struct timer_test test;
    timer_test_init(&test, TIMER_HOLD, false);
    struct timer_thread_test dispatch = { .test = &test };
    sync_model_init(&dispatch.model, 1);
    assert(!mod_timer(&test.timer, jiffies));
    host_time_advance(1);
    pthread_t caller;
    assert(!pthread_create(&caller, NULL, timer_dispatch_thread, &dispatch));
    while (!__atomic_load_n(&test.entered, __ATOMIC_ACQUIRE)) sched_yield();
    assert(!timer_shutdown(&test.timer) && !mod_timer(&test.timer, jiffies));
    __atomic_store_n(&test.release, 1, __ATOMIC_RELEASE);
    assert(!pthread_join(caller, NULL) && !timer_shutdown_sync(&test.timer));
    sync_model_destroy(&dispatch.model);
}

struct timer_race_worker {
    struct native_task_model model;
    struct timer_list *timer;
    unsigned int done;
};
static void timer_race_callback(struct timer_list *timer)
{
    assert(!vinix_linuxkpi_may_sleep() && interrupts);
}
static void *timer_race_thread(void *argument)
{
    struct timer_race_worker *worker = argument;
    native_task = &worker->model;
    for (unsigned int i = 0; i < 500; i++) {
        mod_timer(worker->timer, jiffies + (i % 5));
        timer_reduce(worker->timer, jiffies + 1);
        mod_timer_pending(worker->timer, jiffies + 2);
        if (i % 3) timer_delete(worker->timer);
        else timer_delete_sync(worker->timer);
    }
    __atomic_store_n(&worker->done, 1, __ATOMIC_RELEASE);
    native_task = NULL;
    return NULL;
}
static void timer_race_tests(void)
{
    struct timer_list shared;
    timer_setup_on_stack(&shared, timer_race_callback, 0);
    struct timer_race_worker workers[4];
    pthread_t threads[4];
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++) {
        workers[i] = (struct timer_race_worker){ .timer = &shared };
        sync_model_init(&workers[i].model, i);
        assert(!pthread_create(&threads[i], NULL, timer_race_thread, &workers[i]));
    }
    unsigned int finished;
    do {
        host_time_advance(1);
        vinix_linuxkpi_timer_dispatch();
        finished = 0;
        for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++)
            finished += __atomic_load_n(&workers[i].done, __ATOMIC_ACQUIRE);
        sched_yield();
    } while (finished != ARRAY_SIZE(workers));
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++) {
        assert(!pthread_join(threads[i], NULL));
        sync_model_destroy(&workers[i].model);
    }
    timer_shutdown_sync(&shared);
    destroy_timer_on_stack(&shared);
    assert(!vinix_linuxkpi_timer_active());
}

static void timer_tests(void)
{
    struct native_task_model controller;
    sync_model_init(&controller, 20);
    native_task = &controller;
    timer_queue_tests();
    timer_running_tests();
    unsigned int freed = 0;
    for (unsigned int i = 0; i < 200; i++) {
        struct timer_test *test = kmalloc(sizeof(*test), GFP_KERNEL);
        assert(test);
        timer_test_init(test, TIMER_FREE, i & 1);
        test->free_count = &freed;
        assert(!mod_timer(&test->timer, jiffies));
        host_time_advance(1);
        assert(vinix_linuxkpi_timer_dispatch() == 1);
        host_time_advance(20);
        assert(!vinix_linuxkpi_timer_dispatch() && !vinix_linuxkpi_timer_active());
        assert(live_pages == permanent_pages);
    }
    assert(freed == 200);
    for (unsigned int cpu = 0; cpu < 4; cpu++) {
        current_cpu = cpu;
        for (unsigned long offset = 0; offset < 2000; offset++) {
            unsigned long requested = jiffies + offset, rounded = round_jiffies_up(requested);
            assert(time_after_eq(rounded, requested));
            assert((rounded + cpu * 3) % HZ == 0 || rounded == requested);
            assert(round_jiffies_up_relative(offset) == rounded - jiffies);
            rounded = round_jiffies(requested);
            assert((rounded + cpu * 3) % HZ == 0 || rounded == requested);
            assert(round_jiffies_relative(offset) == rounded - jiffies);
            assert(__round_jiffies_up(jiffies - 2000, cpu) == jiffies - 2000);
        }
    }
    current_cpu = 0;
    timer_race_tests();
    assert(interrupts && !preempt_depth && live_pages == permanent_pages);
    native_task = NULL;
    sync_model_destroy(&controller);
}
