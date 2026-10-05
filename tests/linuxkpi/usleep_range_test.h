/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Included after time_test.h; uses its real task/clock bridge model. */
enum usleep_host_call { USLEEP_HOST_DIRECT, USLEEP_HOST_ORDINARY, USLEEP_HOST_IDLE };
struct usleep_host_test {
    struct native_task_model model;
    unsigned long min, max;
    unsigned int state, sampled, done;
    enum usleep_host_call call;
    u64 begin, end;
    bool expire_before_arm, expire_before_park;
};
static _Thread_local struct usleep_host_test *usleep_host_current;

static void usleep_host_advance(u64 nanoseconds)
{
    u64 now = __atomic_add_fetch(&host_clock_ns, nanoseconds, __ATOMIC_ACQ_REL);
    vinix_linuxkpi_time_tick(now);
}

static void usleep_host_first_sample(void)
{
    struct usleep_host_test *test = usleep_host_current;
    /* The bridge already sampled the clock. Moving it without a tick models
     * preemption before the actual absolute reservation is published. */
    if (test->expire_before_arm)
        __atomic_fetch_add(&host_clock_ns, test->min * NSEC_PER_USEC + TICK_NSEC,
                           __ATOMIC_ACQ_REL);
    __atomic_store_n(&test->sampled, 1, __ATOMIC_RELEASE);
}

static void usleep_host_expire_before_park(void)
{
    struct usleep_host_test *test = usleep_host_current;
    if (!vinix_linuxkpi_time_waiters()) {
        host_irq_restore_hook = usleep_host_expire_before_park;
        return;
    }
    usleep_host_advance(test->min * NSEC_PER_USEC);
}

static void *usleep_host_worker(void *argument)
{
    struct usleep_host_test *test = argument;
    native_task = &test->model;
    current_cpu = 3;
    struct task_struct *task = current;
    unsigned long flags = vinix_linuxkpi_irq_flags();
    unsigned int depth = preempt_depth;
    test->begin = vinix_linuxkpi_clock_ns();
    usleep_host_current = test;
    host_clock_read_hook = usleep_host_first_sample;
    if (test->expire_before_park)
        host_irq_restore_hook = usleep_host_expire_before_park;
    if (test->call == USLEEP_HOST_ORDINARY) usleep_range(test->min, test->max);
    else if (test->call == USLEEP_HOST_IDLE) usleep_idle_range(test->min, test->max);
    else usleep_range_state(test->min, test->max, test->state);
    test->end = vinix_linuxkpi_clock_ns();
    assert(test->end - test->begin >= test->min * NSEC_PER_USEC);
    assert(current == task && task_is_running(task) && current_cpu == 3);
    assert(vinix_linuxkpi_irq_flags() == flags && preempt_depth == depth);
    assert(!host_clock_read_hook && !host_irq_restore_hook);
    usleep_host_current = NULL;
    __atomic_store_n(&test->done, 1, __ATOMIC_RELEASE);
    native_task = NULL;
    return NULL;
}

static void usleep_host_init(struct usleep_host_test *test, unsigned long min,
                             unsigned long max, unsigned int state)
{
    *test = (struct usleep_host_test){ .min = min, .max = max, .state = state };
    sync_model_init(&test->model, 71);
    test->model.iteration = 1;
}

static void usleep_host_sampled(struct usleep_host_test *test)
{
    for (unsigned int spin = 0; spin < 10000000; spin++) {
        if (__atomic_load_n(&test->sampled, __ATOMIC_ACQUIRE)) return;
        sched_yield();
    }
    assert(!"usleep worker did not sample its initial clock");
}

static void usleep_host_dequeued(struct usleep_host_test *test)
{
    for (unsigned int spin = 0; spin < 10000000; spin++) {
        if (__atomic_load_n(&test->model.dequeued, __ATOMIC_ACQUIRE) == 1) return;
        sched_yield();
    }
    assert(!"usleep worker did not evaluate its pending accepted signal");
}

static void usleep_host_parked(struct usleep_host_test *test, size_t total)
{
    for (unsigned int spin = 0; spin < 10000000; spin++) {
        if (__atomic_load_n(&test->model.parked, __ATOMIC_ACQUIRE) == 1 &&
            !vinix_linuxkpi_task_queued(&test->model) &&
            vinix_linuxkpi_time_waiters() == total) {
            assert(__atomic_load_n(&((struct task_struct *)test->model.storage)->__state,
                                   __ATOMIC_ACQUIRE) == test->state);
            return;
        }
        sched_yield();
    }
    assert(!"usleep worker did not park with its real deadline");
}

static void usleep_host_join(struct usleep_host_test *test, pthread_t worker,
                             size_t remaining)
{
    /* A restarted relative timeout must fail at the original boundary,
     * rather than hanging the suite waiting for unadvanced simulated time. */
    for (unsigned int spin = 0; spin < 10000000; spin++) {
        if (__atomic_load_n(&test->done, __ATOMIC_ACQUIRE)) break;
        sched_yield();
    }
    assert(__atomic_load_n(&test->done, __ATOMIC_ACQUIRE));
    assert(!pthread_join(worker, NULL));
    assert(vinix_linuxkpi_time_waiters() == remaining);
    sync_model_destroy(&test->model);
}

static void usleep_range_tests(void)
{
    assert(!native_task && !vinix_linuxkpi_time_waiters());
    size_t pages = live_pages;
    fail_allocation = true;
    struct usleep_host_test test;
    pthread_t worker;
    static const unsigned int states[] = {
        TASK_UNINTERRUPTIBLE, TASK_IDLE, TASK_INTERRUPTIBLE, TASK_KILLABLE,
    };
    /* Literal production i915 ranges include sub-tick minima. The tick just
     * before the absolute minimum must leave the task and record asleep. */
    static const unsigned long ranges[][2] = {
        {0, 0}, {0, 500}, {1, 1}, {6, 60}, {10, 30}, {25, 50}, {100, 250},
        {400, 500}, {518, 1000}, {1000, 1500}, {2000, 3000}, {10000, 15000},
    };
    for (unsigned int mode = 0; mode < ARRAY_SIZE(states); mode++) {
        for (unsigned int i = 0; i < ARRAY_SIZE(ranges); i++) {
            usleep_host_init(&test, ranges[i][0], ranges[i][1], states[mode]);
            if (mode == 0) test.call = USLEEP_HOST_ORDINARY;
            if (mode == 1) test.call = USLEEP_HOST_IDLE;
            assert(!pthread_create(&worker, NULL, usleep_host_worker, &test));
            if (test.min) {
                usleep_host_parked(&test, 1);
                usleep_host_advance(test.min * NSEC_PER_USEC - 1);
                assert(!__atomic_load_n(&test.done, __ATOMIC_ACQUIRE));
                assert(!vinix_linuxkpi_task_queued(&test.model));
                assert(vinix_linuxkpi_time_waiters() == 1);
                usleep_host_advance(1);
            }
            usleep_host_join(&test, worker, 0);
            assert(test.end - test.begin == test.min * NSEC_PER_USEC);
            if (!test.min) assert(!test.model.dequeued && !test.model.parked);
            usleep_host_advance(TICK_NSEC); /* No pointer to an expired frame. */
        }
    }

    for (unsigned int mode = 0; mode < ARRAY_SIZE(states); mode++) {
        usleep_host_init(&test, 10000, 10000, states[mode]);
        assert(!pthread_create(&worker, NULL, usleep_host_worker, &test));
        usleep_host_parked(&test, 1);
        for (unsigned int wake = 0; wake < 8; wake++) {
            usleep_host_advance(TICK_NSEC);
            assert(wake_up_process((void *)test.model.storage));
            usleep_host_parked(&test, 1);
            assert(!__atomic_load_n(&test.done, __ATOMIC_ACQUIRE));
        }
        usleep_host_advance(2 * TICK_NSEC - 1);
        assert(!__atomic_load_n(&test.done, __ATOMIC_ACQUIRE));
        usleep_host_advance(1);
        usleep_host_join(&test, worker, 0);
        assert(test.end - test.begin == 10 * TICK_NSEC);
    }

    /* Signals accepted by the selected state remain pending through retries;
     * they cannot shorten this API's minimum, nor make it extend the expiry. */
    for (unsigned int mode = 0; mode < ARRAY_SIZE(states) + 1; mode++) {
        unsigned int state = mode == ARRAY_SIZE(states) ? TASK_RUNNING : states[mode];
        usleep_host_init(&test, 1000, 1000, state);
        test.model.pending = 1ULL << (state == TASK_KILLABLE ? 8 : 14);
        assert(!pthread_create(&worker, NULL, usleep_host_worker, &test));
        if (state == TASK_UNINTERRUPTIBLE || state == TASK_IDLE)
            usleep_host_parked(&test, 1);
        else if (state == TASK_RUNNING) usleep_host_sampled(&test);
        else usleep_host_dequeued(&test);
        usleep_host_advance(TICK_NSEC - 1);
        assert(!__atomic_load_n(&test.done, __ATOMIC_ACQUIRE));
        usleep_host_advance(1);
        usleep_host_join(&test, worker, 0);
        assert(test.model.pending == (1ULL << (state == TASK_KILLABLE ? 8 : 14)));
        if (state == TASK_INTERRUPTIBLE || state == TASK_KILLABLE || state == TASK_RUNNING)
            assert(!test.model.parked);
    }

    usleep_host_init(&test, 1000, 1000, TASK_KILLABLE);
    test.model.pending = 1ULL << 14; /* Ordinary signals do not interrupt this state. */
    assert(!pthread_create(&worker, NULL, usleep_host_worker, &test));
    usleep_host_parked(&test, 1);
    usleep_host_advance(TICK_NSEC - 1);
    assert(!__atomic_load_n(&test.done, __ATOMIC_ACQUIRE));
    usleep_host_advance(1);
    usleep_host_join(&test, worker, 0);
    assert(test.model.pending == (1ULL << 14));

    for (unsigned int point = 0; point < 2; point++) {
        usleep_host_init(&test, 1000, 2000, TASK_UNINTERRUPTIBLE);
        test.expire_before_arm = !point;
        test.expire_before_park = !!point;
        assert(!pthread_create(&worker, NULL, usleep_host_worker, &test));
        usleep_host_join(&test, worker, 0);
        assert(!test.model.dequeued && !test.model.parked);
        vinix_linuxkpi_time_tick(vinix_linuxkpi_clock_ns());
    }

    /* Two simultaneous records expire independently; the first task's stack
     * can retire while a later absolute reservation remains live. */
    struct usleep_host_test second;
    pthread_t second_worker;
    usleep_host_init(&test, 100, 200, TASK_UNINTERRUPTIBLE);
    usleep_host_init(&second, 400, 500, TASK_IDLE);
    assert(!pthread_create(&worker, NULL, usleep_host_worker, &test));
    usleep_host_parked(&test, 1);
    assert(!pthread_create(&second_worker, NULL, usleep_host_worker, &second));
    usleep_host_parked(&second, 2);
    usleep_host_advance(100 * NSEC_PER_USEC);
    usleep_host_join(&test, worker, 1);
    assert(!__atomic_load_n(&second.done, __ATOMIC_ACQUIRE));
    usleep_host_advance(300 * NSEC_PER_USEC);
    usleep_host_join(&second, second_worker, 0);
    usleep_host_advance(100 * TICK_NSEC);
    fail_allocation = false;
    assert(live_pages == pages && !native_task && interrupts && !preempt_depth);
}
