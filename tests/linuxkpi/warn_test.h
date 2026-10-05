/* SPDX-License-Identifier: GPL-2.0-only */
/* Included after printk_test.h: exercise public warning macros against the
 * real owned-record logger, rather than substituting warning observations. */
#include <linux/bug.h>
#include <linux/panic.h>

static unsigned int host_warn_conditions, host_warn_arguments, host_warn_formats;

static int host_warn_condition(int value)
{
    __atomic_add_fetch(&host_warn_conditions, 1, __ATOMIC_RELAXED);
    return value;
}
static unsigned int host_warn_argument(unsigned int value)
{
    __atomic_add_fetch(&host_warn_arguments, 1, __ATOMIC_RELAXED);
    return value;
}
static const char *host_warn_owned_format(void)
{
    __atomic_add_fetch(&host_warn_formats, 1, __ATOMIC_RELAXED);
    return "owned warning=%s value=%u\n";
}
static const char *host_warn_once_format(void)
{
    __atomic_add_fetch(&host_warn_formats, 1, __ATOMIC_RELAXED);
    return "parallel owned %u\n";
}
/* All four producers use exactly these callsites, including their first false
 * calls. A false condition must leave the callsite available for a winner. */
static bool host_warn_once_call(int condition, unsigned int index)
{
    return WARN_ONCE(host_warn_condition(condition), host_warn_once_format(),
                     host_warn_argument(index));
}
static bool host_warn_on_once_call(int condition)
{
    return WARN_ON_ONCE(host_warn_condition(condition));
}

struct host_warn_producer {
    unsigned int index;
    unsigned int *ready, *go;
    bool taints;
};
static void *host_warn_produce(void *argument)
{
    const struct host_warn_producer *producer = argument;
    current_cpu = producer->index;
    assert(interrupts && !preempt_depth);
    __atomic_add_fetch(producer->ready, 1, __ATOMIC_RELEASE);
    while (!__atomic_load_n(producer->go, __ATOMIC_ACQUIRE)) sched_yield();
    if (!producer->taints) {
        for (unsigned int i = 0; i < 64; i++) {
            int condition = (i & 1) ? -7 : 0;
            assert(host_warn_once_call(condition, producer->index) == !!condition);
            assert(host_warn_on_once_call(condition) == !!condition);
        }
    } else {
        for (unsigned int i = 0; i < 1024; i++) {
            unsigned long flags = vinix_linuxkpi_irq_save();
            vinix_linuxkpi_preempt_disable();
            vinix_linuxkpi_preempt_disable();
            for (unsigned int bit = producer->index; bit < TAINT_FLAGS_COUNT; bit += 4) {
                add_taint(bit, (i & 1) ? LOCKDEP_NOW_UNRELIABLE : LOCKDEP_STILL_OK);
                assert(test_taint(bit) == 1);
            }
            assert(!interrupts && preempt_depth == 2);
            vinix_linuxkpi_preempt_enable_no_resched();
            vinix_linuxkpi_preempt_enable_no_resched();
            vinix_linuxkpi_irq_restore(flags);
            assert(interrupts && !preempt_depth);
        }
    }
    return NULL;
}
static void host_warn_parallel(bool taints)
{
    unsigned int ready = 0, go = 0;
    struct host_warn_producer producers[4];
    pthread_t threads[4];
    for (unsigned int i = 0; i < ARRAY_SIZE(producers); i++) {
        producers[i] = (struct host_warn_producer){
            .index = i, .ready = &ready, .go = &go, .taints = taints,
        };
        assert(!pthread_create(&threads[i], NULL, host_warn_produce, &producers[i]));
    }
    while (__atomic_load_n(&ready, __ATOMIC_ACQUIRE) != ARRAY_SIZE(producers)) sched_yield();
    __atomic_store_n(&go, 1, __ATOMIC_RELEASE);
    for (unsigned int i = 0; i < ARRAY_SIZE(producers); i++)
        assert(!pthread_join(threads[i], NULL));
}
static void host_warn_record(const struct vinix_linuxkpi_printk_record *record)
{
    assert(record->level == LOGLEVEL_WARNING && record->caller == 0);
    assert(record->format_status == 0 && record->flags == VINIX_PRINTK_NEWLINE);
    assert(record->length == strlen(record->text));
    assert(!strncmp(record->text, "linuxkpi: warning at ", 20));
}

/* Run before any other warning fixture or allocation test. Refcount failure
 * is a WARN event in the pinned caller and must be the first sticky taint. */
static void taint_initial_tests(void)
{
    assert(!native_task && interrupts && !preempt_depth);
    assert(get_taint() == 0 && test_taint(TAINT_WARN) == 0);
    size_t pages = live_pages;
    struct vinix_linuxkpi_printk_state before, state;
    vinix_linuxkpi_printk_get_state(&before);
    assert(!before.worker_live && !before.in_flight);
    assert(!pthread_mutex_lock(&host_logger_console_lock));
    bool allocation_before = fail_allocation;
    fail_allocation = true;
    unsigned long flags = vinix_linuxkpi_irq_save();
    vinix_linuxkpi_preempt_disable();
    vinix_linuxkpi_preempt_disable();
    vinix_linuxkpi_refcount_warning(REFCOUNT_DEC_LEAK);
    assert(get_taint() == (1UL << TAINT_WARN) && test_taint(TAINT_WARN) == 1);
    vinix_linuxkpi_printk_get_state(&state);
    assert(state.submitted == before.submitted + 1 && state.queued == before.queued + 1);
    assert(state.dropped == before.dropped && !state.worker_live && !state.in_flight);
    assert(!interrupts && preempt_depth == 2 && live_pages == pages);
    vinix_linuxkpi_preempt_enable_no_resched();
    vinix_linuxkpi_preempt_enable_no_resched();
    vinix_linuxkpi_irq_restore(flags);
    fail_allocation = allocation_before;
    assert(!pthread_mutex_unlock(&host_logger_console_lock));
    assert(interrupts && !preempt_depth && live_pages == pages);
}

static void warn_tests(void)
{
    size_t pages = live_pages;
    struct native_task_model controller;
    sync_model_init(&controller, 84);
    native_task = &controller;
    assert(interrupts && !preempt_depth);
    assert(TAINT_FLAGS_COUNT == 19 && TAINT_FLAGS_MAX == 0x7ffffUL);
    assert(!__atomic_load_n(&host_logger_workers, __ATOMIC_ACQUIRE));
    __atomic_store_n(&host_logger_tick_stop, false, __ATOMIC_RELEASE);
    pthread_t ticker;
    assert(!pthread_create(&ticker, NULL, host_logger_ticks, NULL));
    assert(!vinix_linuxkpi_printk_bootstrap());
    assert(!vinix_linuxkpi_printk_flush(vinix_linuxkpi_printk_snapshot(), 2000));

    struct host_logger_capture capture;
    struct vinix_linuxkpi_printk_state before, state;
    host_logger_install(&capture);
    vinix_linuxkpi_printk_get_state(&before);
    unsigned long taint_before = get_taint();
    host_warn_conditions = host_warn_arguments = host_warn_formats = 0;
    assert(WARN(host_warn_condition(0), host_warn_owned_format(), (char *)1,
                host_warn_argument(0)) == 0);
    assert(host_warn_conditions == 1 && !host_warn_arguments && !host_warn_formats);
    assert(get_taint() == taint_before);
    assert(vinix_linuxkpi_printk_snapshot() == before.submitted);

    char *borrowed = malloc(16);
    assert(borrowed);
    memcpy(borrowed, "short-lived", 12);
    assert(WARN(host_warn_condition(7), host_warn_owned_format(), borrowed,
                host_warn_argument(12)) == 1);
    memset(borrowed, 'X', 16);
    free(borrowed);
    assert(WARN_ON(host_warn_condition(-8)) == 1);
    assert(WARN_ON(host_warn_condition(0)) == 0);

    /* Both unrelated native-style locks remain held through warning capture.
     * Any console write or scheduler wake on the producer path would deadlock. */
    assert(!pthread_mutex_lock(&host_logger_console_lock));
    assert(!pthread_mutex_lock(&controller.queue_lock));
    bool allocation_before = fail_allocation;
    fail_allocation = true;
    unsigned long flags = vinix_linuxkpi_irq_save();
    vinix_linuxkpi_preempt_disable();
    vinix_linuxkpi_preempt_disable();
    assert(WARN(host_warn_condition(5), "atomic warning value=%u\n",
                host_warn_argument(5)) == 1);
    assert(WARN_ON(host_warn_condition(3)) == 1);
    assert(!interrupts && preempt_depth == 2 && live_pages == pages);
    assert(test_taint(TAINT_WARN) == 1);
    assert(get_taint() == (taint_before | (1UL << TAINT_WARN)));
    assert(vinix_linuxkpi_printk_flush(vinix_linuxkpi_printk_snapshot(), 0) == -EWOULDBLOCK);
    vinix_linuxkpi_preempt_enable_no_resched();
    vinix_linuxkpi_preempt_enable_no_resched();
    vinix_linuxkpi_irq_restore(flags);
    fail_allocation = allocation_before;
    assert(!pthread_mutex_unlock(&controller.queue_lock));
    assert(!pthread_mutex_unlock(&host_logger_console_lock));
    vinix_linuxkpi_refcount_warning(REFCOUNT_DEC_LEAK);
    assert(host_warn_conditions == 6 && host_warn_arguments == 2 && host_warn_formats == 1);
    vinix_linuxkpi_printk_get_state(&state);
    assert(state.submitted == before.submitted + 5 && state.dropped == before.dropped);
    host_logger_finish(&capture, 5);
    for (unsigned int i = 0; i < 4; i++) host_warn_record(&capture.records[i]);
    assert(strstr(capture.records[0].text, ": owned warning=short-lived value=12"));
    assert(strstr(capture.records[2].text, ": atomic warning value=5"));
    assert(!strcmp(capture.records[4].text,
        "linuxkpi: refcount saturated after invalid operation 4; retaining object"));
    assert(capture.records[4].level == LOGLEVEL_WARNING);

    host_logger_install(&capture);
    vinix_linuxkpi_printk_get_state(&before);
    host_warn_conditions = host_warn_arguments = host_warn_formats = 0;
    assert(!host_warn_once_call(0, 99));
    assert(!host_warn_on_once_call(0));
    assert(!host_warn_arguments && !host_warn_formats);
    assert(vinix_linuxkpi_printk_snapshot() == before.submitted);
    host_warn_parallel(false);
    assert(host_warn_conditions == 2 + 4 * 64 * 2);
    assert(host_warn_arguments == 1 && host_warn_formats == 1);
    vinix_linuxkpi_printk_get_state(&state);
    assert(state.submitted == before.submitted + 2 && state.dropped == before.dropped);
    host_logger_finish(&capture, 2);
    unsigned int formatted = 0;
    for (unsigned int i = 0; i < capture.count; i++) {
        host_warn_record(&capture.records[i]);
        const char *body = strstr(capture.records[i].text, ": parallel owned ");
        if (body) {
            body += sizeof(": parallel owned ") - 1;
            assert(body[0] >= '0' && body[0] <= '3' && !body[1]);
            formatted++;
        }
    }
    assert(formatted == 1);

    /* A preexisting bit remains sticky while four concurrent writers cover
     * every actual Linux 6.6 taint bit. No test resets the production mask. */
    assert(!pthread_mutex_lock(&host_logger_console_lock));
    assert(!pthread_mutex_lock(&controller.queue_lock));
    allocation_before = fail_allocation;
    fail_allocation = true;
    flags = vinix_linuxkpi_irq_save();
    vinix_linuxkpi_preempt_disable();
    vinix_linuxkpi_preempt_disable();
    add_taint(TAINT_TEST, LOCKDEP_NOW_UNRELIABLE);
    assert(test_taint(TAINT_TEST) == 1);
    taint_before = get_taint();
    assert(!interrupts && preempt_depth == 2 && live_pages == pages);
    vinix_linuxkpi_preempt_enable_no_resched();
    vinix_linuxkpi_preempt_enable_no_resched();
    vinix_linuxkpi_irq_restore(flags);
    fail_allocation = allocation_before;
    assert(!pthread_mutex_unlock(&controller.queue_lock));
    assert(!pthread_mutex_unlock(&host_logger_console_lock));
    u64 no_log = vinix_linuxkpi_printk_snapshot();
    host_warn_parallel(true);
    assert(get_taint() == (taint_before | TAINT_FLAGS_MAX));
    for (unsigned int bit = 0; bit < TAINT_FLAGS_COUNT; bit++) assert(test_taint(bit) == 1);
    assert(vinix_linuxkpi_printk_snapshot() == no_log && live_pages == pages);

    assert(!vinix_linuxkpi_printk_test_pause(false, 0));
    assert(!vinix_linuxkpi_printk_shutdown());
    __atomic_store_n(&host_logger_tick_stop, true, __ATOMIC_RELEASE);
    assert(!pthread_join(ticker, NULL));
    vinix_linuxkpi_printk_get_state(&state);
    assert(!state.worker_live && !state.in_flight && !state.queued && state.retired == state.submitted);
    assert(!__atomic_load_n(&host_logger_workers, __ATOMIC_ACQUIRE));
    assert(!vinix_linuxkpi_time_waiters() && live_pages == pages);
    sync_model_destroy(&controller);
    native_task = NULL;
}
