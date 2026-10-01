/* SPDX-License-Identifier: GPL-2.0-or-later */
/* The host's legacy structs are unrelated to the kernel's timespec64 API. */
#undef CLOCKS_PER_SEC
#undef CLOCK_REALTIME
#undef CLOCK_MONOTONIC
#undef CLOCK_PROCESS_CPUTIME_ID
#undef CLOCK_THREAD_CPUTIME_ID
#undef CLOCK_MONOTONIC_RAW
#undef CLOCK_REALTIME_COARSE
#undef CLOCK_MONOTONIC_COARSE
#undef TIMER_ABSTIME
#define timespec vinix_linux_timespec
#define timeval vinix_linux_timeval
#define itimerspec vinix_linux_itimerspec
#define timezone vinix_linux_timezone
#include <linux/ktime.h>
#include <linux/delay.h>
#undef timespec
#undef timeval
#undef itimerspec
#undef timezone

static void host_time_advance(u64 ticks)
{
    u64 now = __atomic_add_fetch(&host_clock_ns, ticks * TICK_NSEC, __ATOMIC_ACQ_REL);
    vinix_linuxkpi_time_tick(now);
}

static void time_conversion_tests(void)
{
    /* Distinct extern names can be assumed unequal by the C optimizer even
     * when the linker aliases them. Compare their actual runtime addresses. */
    volatile uintptr_t tick_address = (uintptr_t)&jiffies;
    assert(tick_address == (uintptr_t)&jiffies_64 && !(tick_address % 64));
    assert(jiffies == INITIAL_JIFFIES && get_jiffies_64() == INITIAL_JIFFIES);
    host_time_advance(3);
    assert(jiffies == INITIAL_JIFFIES + 3);
    vinix_linuxkpi_time_tick(0); /* A stale tick must not turn time backwards. */
    assert(jiffies == INITIAL_JIFFIES + 3);
    assert(ktime_get_ns() == 3 * TICK_NSEC && ktime_get_raw_ns() == ktime_get_ns());
    assert(ktime_get_coarse_ns() == 3 * TICK_NSEC);
    assert(ktime_get_resolution_ns() == 1000000);
    struct timespec64 ts;
    ktime_get_ts64(&ts);
    assert(ts.tv_sec == 0 && ts.tv_nsec == 3 * TICK_NSEC);
    ktime_get_raw_ts64(&ts);
    assert(timespec64_to_ns(&ts) == (s64)ktime_get_raw_ns());
    const unsigned long values[] = {0, 1, 999, 1000, UINT_MAX, MAX_JIFFY_OFFSET, ULONG_MAX};
    for (unsigned int i = 0; i < ARRAY_SIZE(values); i++) {
        unsigned long value = values[i];
        assert(jiffies_to_msecs(value) == (unsigned int)value);
        assert(jiffies_to_usecs(value) == (unsigned int)(value * 1000));
        assert(jiffies64_to_msecs(value) == value);
        assert(jiffies64_to_nsecs(value) == (u64)value * TICK_NSEC);
        assert(jiffies_to_clock_t(value) == (clock_t)(value / 10));
        assert(jiffies_64_to_clock_t(value) == (u64)value / 10);
        assert(clock_t_to_jiffies(value) == (value >= ULONG_MAX / 10 ? ULONG_MAX : value * 10));
    }
    for (unsigned int value = 0; value < 10000; value++) {
        volatile unsigned int runtime_value = value;
        assert(msecs_to_jiffies(runtime_value) == value);
        assert(usecs_to_jiffies(runtime_value) == (value + 999) / 1000);
        assert(nsecs_to_jiffies64((u64)value * TICK_NSEC + 123) == value);
    }
    assert(msecs_to_jiffies(UINT_MAX) == MAX_JIFFY_OFFSET);
    volatile unsigned int huge = UINT_MAX;
    assert(msecs_to_jiffies(huge) == MAX_JIFFY_OFFSET);
    assert(usecs_to_jiffies(huge) == MAX_JIFFY_OFFSET);
    assert(time_after(1UL, ULONG_MAX) && time_before(ULONG_MAX, 1UL));
    assert(time_after_eq(ULONG_MAX, ULONG_MAX));
    assert(time_in_range(0UL, ULONG_MAX - 1, 1UL));
    assert(time_after64((u64)1, U64_MAX) && time_before64(U64_MAX, (u64)1));
    const s64 nanos[] = {0, 1, -1, NSEC_PER_SEC, -NSEC_PER_SEC - 1, S64_MAX, S64_MIN};
    for (unsigned int i = 0; i < ARRAY_SIZE(nanos); i++) {
        ts = ns_to_timespec64(nanos[i]);
        assert(ts.tv_nsec >= 0 && ts.tv_nsec < NSEC_PER_SEC);
        assert((__int128)ts.tv_sec * NSEC_PER_SEC + ts.tv_nsec == nanos[i]);
    }
    set_normalized_timespec64(&ts, 5, -1);
    assert(ts.tv_sec == 4 && ts.tv_nsec == NSEC_PER_SEC - 1);
    for (unsigned long ticks = 0; ticks < 10000; ticks++) {
        jiffies_to_timespec64(ticks, &ts);
        assert(timespec64_to_ns(&ts) == (s64)ticks * TICK_NSEC);
        assert(timespec64_to_jiffies(&ts) == ticks);
    }
    ts = (struct timespec64){ .tv_nsec = 1 };
    assert(timespec64_to_jiffies(&ts) == 1);
    ts = (struct timespec64){ .tv_sec = S64_MAX };
    assert(timespec64_to_jiffies(&ts) <= MAX_JIFFY_OFFSET);
    assert(ktime_add_safe(KTIME_MAX, 1) == KTIME_MAX && ktime_add_safe(12, 15) == 27);
    assert(ktime_set(KTIME_SEC_MAX, 0) == KTIME_MAX);
    assert(ktime_to_us(12345) == 12 && ktime_to_ms(1234567) == 1);
    assert(ktime_compare(5, 6) < 0 && ktime_compare(5, 5) == 0);
    assert(ktime_us_delta(12000, 5000) == 7 && ktime_before(1, 2));
}

enum timed_wait_kind { TIMED_TASK, TIMED_QUEUE, TIMED_SIMPLE, TIMED_COMPLETION, TIMED_MSLEEP };
struct timed_wait_test {
    struct native_task_model model;
    struct wait_queue_head queue;
    struct swait_queue_head simple;
    struct completion completion;
    unsigned int condition, payload;
    unsigned int state, armed, proceed;
    enum timed_wait_kind kind;
    long timeout, result;
    bool delay_before_arm, expire_before_park, complete_at_expiry, signal_at_expiry;
};

static _Thread_local struct timed_wait_test *expiry_test;
static void expire_before_park(void)
{
    struct timed_wait_test *test = expiry_test;
    if (!vinix_linuxkpi_time_waiters()) {
        host_irq_restore_hook = expire_before_park;
        return;
    }
    /* Run a tick immediately after schedule_timeout publishes its deadline
     * and releases the IRQ lock, before it can dequeue or park the task. */
    host_time_advance(test->timeout);
    if (test->signal_at_expiry)
        __atomic_store_n(&test->model.pending, 1ULL << 14, __ATOMIC_RELEASE);
    if (test->complete_at_expiry) {
        test->payload = 0x1234;
        complete(&test->completion);
    }
    expiry_test = NULL;
}

static void *timed_wait_worker(void *argument)
{
    struct timed_wait_test *test = argument;
    native_task = &test->model;
    if (test->expire_before_park) {
        expiry_test = test;
        host_irq_restore_hook = expire_before_park;
    }
    struct task_struct *task = current;
    if (test->kind == TIMED_TASK) {
        set_current_state(test->state);
        __atomic_store_n(&test->armed, 1, __ATOMIC_RELEASE);
        if (test->delay_before_arm)
            while (!__atomic_load_n(&test->proceed, __ATOMIC_ACQUIRE)) sched_yield();
        test->result = schedule_timeout(test->timeout);
    } else if (test->kind == TIMED_QUEUE) {
        if (test->state == TASK_INTERRUPTIBLE)
            test->result = wait_event_interruptible_timeout(test->queue,
                __atomic_load_n(&test->condition, __ATOMIC_ACQUIRE), test->timeout);
        else
            test->result = wait_event_timeout(test->queue,
                __atomic_load_n(&test->condition, __ATOMIC_ACQUIRE), test->timeout);
    } else if (test->kind == TIMED_SIMPLE) {
        if (test->state == TASK_INTERRUPTIBLE)
            test->result = swait_event_interruptible_timeout_exclusive(test->simple,
                __atomic_load_n(&test->condition, __ATOMIC_ACQUIRE), test->timeout);
        else
            test->result = swait_event_timeout_exclusive(test->simple,
                __atomic_load_n(&test->condition, __ATOMIC_ACQUIRE), test->timeout);
    } else if (test->kind == TIMED_MSLEEP) {
        if (test->state == TASK_INTERRUPTIBLE) test->result = msleep_interruptible(test->timeout);
        else msleep(test->timeout);
    } else if (test->state == TASK_INTERRUPTIBLE)
        test->result = wait_for_completion_interruptible_timeout(&test->completion, test->timeout);
    else if (test->state == TASK_KILLABLE)
        test->result = wait_for_completion_killable_timeout(&test->completion, test->timeout);
    else
        test->result = wait_for_completion_timeout(&test->completion, test->timeout);
    if (test->kind != TIMED_TASK && test->kind != TIMED_MSLEEP && test->result > 0)
        assert(test->payload == 0x1234);
    assert(task_is_running(task) && interrupts && !preempt_depth);
    assert(!host_irq_restore_hook && !expiry_test);
    native_task = NULL;
    return NULL;
}

static void timed_wait_init(struct timed_wait_test *test, enum timed_wait_kind kind, unsigned int state)
{
    *test = (struct timed_wait_test){ .kind = kind, .state = state, .timeout = 10 };
    sync_model_init(&test->model, 0);
    test->model.iteration = 1;
    init_waitqueue_head(&test->queue);
    init_swait_queue_head(&test->simple);
    init_completion(&test->completion);
}

static void timed_wait_cleanup(struct timed_wait_test *test, pthread_t worker)
{
    assert(!pthread_join(worker, NULL));
    assert(!vinix_linuxkpi_time_waiters());
    assert(!waitqueue_active(&test->queue) && !swait_active(&test->simple));
    assert(!swait_active(&test->completion.wait));
    sync_model_destroy(&test->model);
}

static void timed_wait_parked(struct timed_wait_test *test)
{
    while (__atomic_load_n(&test->model.parked, __ATOMIC_ACQUIRE) != 1) sched_yield();
    assert(vinix_linuxkpi_time_waiters() == 1);
}

static void timed_wait_tests(void)
{
    struct timed_wait_test test;
    pthread_t worker;
    /* The same stack node is reused across 240 timed wait/cancellation cases. */
    for (unsigned int round = 0; round < 10; round++) {
        for (unsigned int kind = TIMED_TASK; kind <= TIMED_COMPLETION; kind++) {
            for (unsigned int mode = 0; mode < 2; mode++) {
                for (unsigned int outcome = 0; outcome < 3; outcome++) {
                    timed_wait_init(&test, kind, mode ? TASK_INTERRUPTIBLE : TASK_UNINTERRUPTIBLE);
                    assert(!pthread_create(&worker, NULL, timed_wait_worker, &test));
                    timed_wait_parked(&test);
                    host_time_advance(3);
                    if (outcome == 0) host_time_advance(7);
                    else if (outcome == 1) {
                        test.payload = 0x1234;
                        __atomic_store_n(&test.condition, 1, __ATOMIC_RELEASE);
                        if (kind == TIMED_TASK) assert(wake_up_process((void *)test.model.storage));
                        if (kind == TIMED_QUEUE) wake_up_all(&test.queue);
                        if (kind == TIMED_SIMPLE) swake_up_all(&test.simple);
                        if (kind == TIMED_COMPLETION) complete(&test.completion);
                    } else {
                        __atomic_store_n(&test.model.pending, 1ULL << 14, __ATOMIC_RELEASE);
                        assert(vinix_linuxkpi_task_enqueue(&test.model));
                        if (!mode) {
                            /* An ordinary signal must not cancel this deadline. */
                            while (vinix_linuxkpi_task_queued(&test.model)) sched_yield();
                            host_time_advance(7);
                        }
                    }
                    timed_wait_cleanup(&test, worker);
                    long expected = outcome == 0 || (outcome == 2 && !mode) ? 0 :
                                    outcome == 2 && kind != TIMED_TASK ? -ERESTARTSYS : 7;
                    assert(test.result == expected);
                    /* Advance long after the stack frame is gone: stale deadline
                     * pointers or callbacks would be detected by ASan. */
                    host_time_advance(20);
                }
            }
        }
    }
    /* Linux wake before arming must return the remaining ticks, not re-sleep. */
    timed_wait_init(&test, TIMED_TASK, TASK_UNINTERRUPTIBLE);
    test.delay_before_arm = true;
    assert(!pthread_create(&worker, NULL, timed_wait_worker, &test));
    while (!__atomic_load_n(&test.armed, __ATOMIC_ACQUIRE)) sched_yield();
    assert(wake_up_process((void *)test.model.storage));
    __atomic_store_n(&test.proceed, 1, __ATOMIC_RELEASE);
    timed_wait_cleanup(&test, worker);
    assert(test.result == 10);
    for (unsigned int kind = TIMED_TASK; kind <= TIMED_COMPLETION; kind++) {
        timed_wait_init(&test, kind, TASK_UNINTERRUPTIBLE);
        test.expire_before_park = true;
        assert(!pthread_create(&worker, NULL, timed_wait_worker, &test));
        timed_wait_cleanup(&test, worker);
        assert(test.result == 0 && !test.model.dequeued && !test.model.parked);
    }
    timed_wait_init(&test, TIMED_COMPLETION, TASK_INTERRUPTIBLE);
    test.expire_before_park = test.signal_at_expiry = true;
    assert(!pthread_create(&worker, NULL, timed_wait_worker, &test));
    timed_wait_cleanup(&test, worker);
    assert(test.result == 0); /* A signal arriving at expiry cannot cancel it. */
    timed_wait_init(&test, TIMED_COMPLETION, TASK_INTERRUPTIBLE);
    test.expire_before_park = test.complete_at_expiry = test.signal_at_expiry = true;
    assert(!pthread_create(&worker, NULL, timed_wait_worker, &test));
    timed_wait_cleanup(&test, worker);
    assert(test.result == 1 && !completion_done(&test.completion));
    for (unsigned int fatal = 0; fatal < 2; fatal++) {
        timed_wait_init(&test, TIMED_COMPLETION, TASK_KILLABLE);
        assert(!pthread_create(&worker, NULL, timed_wait_worker, &test));
        timed_wait_parked(&test);
        __atomic_store_n(&test.model.pending, 1ULL << (fatal ? 8 : 14), __ATOMIC_RELEASE);
        assert(vinix_linuxkpi_task_enqueue(&test.model));
        if (!fatal) {
            while (vinix_linuxkpi_task_queued(&test.model)) sched_yield();
            host_time_advance(10);
        }
        timed_wait_cleanup(&test, worker);
        assert(test.result == (fatal ? -ERESTARTSYS : 0));
    }
    timed_wait_init(&test, TIMED_TASK, TASK_UNINTERRUPTIBLE);
    test.timeout = MAX_SCHEDULE_TIMEOUT;
    assert(!pthread_create(&worker, NULL, timed_wait_worker, &test));
    while (__atomic_load_n(&test.model.parked, __ATOMIC_ACQUIRE) != 1) sched_yield();
    assert(!vinix_linuxkpi_time_waiters());
    host_time_advance(100);
    assert(wake_up_process((void *)test.model.storage));
    timed_wait_cleanup(&test, worker);
    assert(test.result == MAX_SCHEDULE_TIMEOUT);

    timed_wait_init(&test, TIMED_MSLEEP, TASK_UNINTERRUPTIBLE);
    assert(!pthread_create(&worker, NULL, timed_wait_worker, &test));
    timed_wait_parked(&test);
    host_time_advance(3);
    assert(wake_up_process((void *)test.model.storage));
    /* Wait for msleep to rearm the remaining eight ticks after the early wake. */
    while (vinix_linuxkpi_task_queued(&test.model)) sched_yield();
    host_time_advance(8);
    timed_wait_cleanup(&test, worker);
    timed_wait_init(&test, TIMED_MSLEEP, TASK_INTERRUPTIBLE);
    assert(!pthread_create(&worker, NULL, timed_wait_worker, &test));
    timed_wait_parked(&test);
    host_time_advance(3);
    __atomic_store_n(&test.model.pending, 1ULL << 14, __ATOMIC_RELEASE);
    assert(vinix_linuxkpi_task_enqueue(&test.model));
    timed_wait_cleanup(&test, worker);
    assert(test.result == 8);
}

static void time_tests(void)
{
    struct native_task_model controller;
    sync_model_init(&controller, 20);
    native_task = &controller;
    time_conversion_tests();
    assert(!vinix_linuxkpi_time_selftest());
    DECLARE_WAIT_QUEUE_HEAD(queue);
    assert(wait_event_timeout(queue, true, 0) == 1);
    assert(wait_event_timeout(queue, false, 0) == 0);
    set_current_state(TASK_INTERRUPTIBLE);
    assert(schedule_timeout(-1) == 0 && task_is_running(current));
    assert(atomic_read(&time_warnings) == 1);
    set_current_state(TASK_UNINTERRUPTIBLE);
    assert(schedule_timeout(0) == 0 && task_is_running(current));
    DECLARE_COMPLETION_ONSTACK(completion);
    assert(!wait_for_completion_timeout(&completion, 0));
    complete(&completion);
    assert(wait_for_completion_timeout(&completion, 0) == 1 && !completion_done(&completion));
    timed_wait_tests();
    assert(!vinix_linuxkpi_time_waiters() && live_pages == permanent_pages);
    native_task = NULL;
    sync_model_destroy(&controller);
}
