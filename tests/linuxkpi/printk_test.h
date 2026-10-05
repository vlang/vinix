/* SPDX-License-Identifier: GPL-2.0-only */
/* Included after the native task and monotonic-clock host models. */
#include <linux/printk.h>
#include <linux/panic.h>
#include <vinix/printk.h>
#include <vinix/format.h>

static unsigned int host_logger_workers, host_logger_key_attempts;
static bool host_logger_key_available, host_logger_tick_stop;
static pthread_mutex_t host_logger_console_lock = PTHREAD_MUTEX_INITIALIZER;
static unsigned int host_logger_console_bytes;

void vinix_linuxkpi_host_logger_enter(void)
{
    struct native_task_model *model = calloc(1, sizeof(*model));
    assert(model);
    sync_model_init(model, 80);
    model->heap_owned = true;
    native_task = model;
    current_cpu = 0;
    __atomic_add_fetch(&host_logger_workers, 1, __ATOMIC_RELEASE);
}
void vinix_linuxkpi_host_logger_leave(void)
{
    struct native_task_model *model = native_task;
    assert(model && model->pins == 1 && vinix_linuxkpi_may_sleep());
    __atomic_store_n(&model->dead, true, __ATOMIC_RELEASE);
    vinix_linuxkpi_task_dead(model->storage);
    __atomic_sub_fetch(&host_logger_workers, 1, __ATOMIC_RELEASE);
    native_task = NULL;
}
void vinix_linuxkpi_log_write(const char *text, size_t length)
{
    assert(vinix_linuxkpi_may_sleep());
    assert(!pthread_mutex_lock(&host_logger_console_lock));
    assert(length && text[length - 1] == '\n');
    __atomic_add_fetch(&host_logger_console_bytes, (unsigned int)length, __ATOMIC_RELEASE);
    assert(!pthread_mutex_unlock(&host_logger_console_lock));
}
bool vinix_linuxkpi_log_key(u64 key[2])
{
    assert(vinix_linuxkpi_may_sleep());
    __atomic_add_fetch(&host_logger_key_attempts, 1, __ATOMIC_RELAXED);
    if (!__atomic_load_n(&host_logger_key_available, __ATOMIC_ACQUIRE)) return false;
    key[0] = 0x0706050403020100ULL;
    key[1] = 0x0f0e0d0c0b0a0908ULL;
    return true;
}
u64 vinix_linuxkpi_log_caller(void) { return 0; }

static void *host_logger_ticks(void *argument)
{
    while (!__atomic_load_n(&host_logger_tick_stop, __ATOMIC_ACQUIRE)) {
        host_time_advance(1);
        usleep(1000);
    }
    return NULL;
}

struct host_logger_capture {
    struct vinix_linuxkpi_printk_record records[128];
    unsigned int count, hold, entered, release;
    int self_flush, self_shutdown, self_pause;
};
static void host_logger_sink(const struct vinix_linuxkpi_printk_record *record, void *argument)
{
    struct host_logger_capture *capture = argument;
    assert(vinix_linuxkpi_may_sleep() && record->length < VINIX_PRINTK_RECORD_BYTES);
    assert(!record->text[record->length]);
    unsigned int index = capture->count;
    assert(index < ARRAY_SIZE(capture->records));
    capture->records[index] = *record;
    capture->self_flush = vinix_linuxkpi_printk_flush(record->sequence, 0);
    capture->self_shutdown = vinix_linuxkpi_printk_shutdown();
    capture->self_pause = vinix_linuxkpi_printk_test_pause(true, 0);
    if (index < 32 && (__atomic_load_n(&capture->hold, __ATOMIC_ACQUIRE) & (1U << index))) {
        __atomic_fetch_or(&capture->entered, 1U << index, __ATOMIC_RELEASE);
        while (!(__atomic_load_n(&capture->release, __ATOMIC_ACQUIRE) & (1U << index)))
            sched_yield();
    }
    __atomic_store_n(&capture->count, index + 1, __ATOMIC_RELEASE);
}
static void host_logger_install(struct host_logger_capture *capture)
{
    assert(!vinix_linuxkpi_printk_test_pause(true, 2000));
    *capture = (struct host_logger_capture){0};
    assert(!vinix_linuxkpi_printk_test_sink(host_logger_sink, capture));
}
static void host_logger_finish(struct host_logger_capture *capture, unsigned int count)
{
    assert(!vinix_linuxkpi_printk_test_pause(false, 0));
    assert(!vinix_linuxkpi_printk_flush(vinix_linuxkpi_printk_snapshot(), 2000));
    assert(__atomic_load_n(&capture->count, __ATOMIC_ACQUIRE) == count);
    assert(capture->self_flush == -EDEADLK && capture->self_shutdown == -EDEADLK &&
           capture->self_pause == -EDEADLK);
    assert(!vinix_linuxkpi_printk_test_pause(true, 2000));
    assert(!vinix_linuxkpi_printk_test_sink(NULL, NULL));
}

static int host_logger_emit(int facility, int level, const struct dev_printk_info *info,
                            const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    int result = vprintk_emit(facility, level, info, fmt, args);
    va_end(args);
    return result;
}
static int host_logger_nested(const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    struct va_format nested = { .fmt = fmt, .va = &args };
    int result = _printk(KERN_WARNING "nested:%pV", &nested);
    va_end(args);
    return result;
}
struct host_logger_producer {
    unsigned int index;
};
static void *host_logger_produce(void *argument)
{
    struct host_logger_producer *producer = argument;
    current_cpu = producer->index;
    for (unsigned int i = 0; i < 16; i++) {
        unsigned long flags = vinix_linuxkpi_irq_save();
        vinix_linuxkpi_preempt_disable();
        unsigned int depth = preempt_depth;
        assert(_printk(KERN_NOTICE "producer %u:%u\n", producer->index, i) >= 12);
        assert(!interrupts && preempt_depth == depth);
        vinix_linuxkpi_preempt_enable_no_resched();
        vinix_linuxkpi_irq_restore(flags);
        assert(interrupts && !preempt_depth);
    }
    return NULL;
}
struct host_logger_flusher {
    struct native_task_model model;
    u64 snapshot;
    unsigned int entered, done;
    int result;
};
static void *host_logger_flush_thread(void *argument)
{
    struct host_logger_flusher *test = argument;
    native_task = &test->model;
    __atomic_store_n(&test->entered, 1, __ATOMIC_RELEASE);
    test->result = vinix_linuxkpi_printk_flush(test->snapshot, 2000);
    __atomic_store_n(&test->done, 1, __ATOMIC_RELEASE);
    native_task = NULL;
    return NULL;
}

static void printk_tests(void)
{
    size_t pages = live_pages;
    struct native_task_model controller;
    sync_model_init(&controller, 81);
    native_task = &controller;
    struct vinix_linuxkpi_printk_state before, state;
    vinix_linuxkpi_printk_get_state(&before);
    assert(!before.worker_live);
    assert(_printk(KERN_INFO "preboot\n") == 7);
    u64 preboot = vinix_linuxkpi_printk_snapshot();
    assert(vinix_linuxkpi_printk_flush(preboot, 0) == -ENODEV);
    vinix_linuxkpi_printk_test_fail_create(true);
    assert(vinix_linuxkpi_printk_bootstrap() == -ENOMEM && !host_logger_workers);
    vinix_linuxkpi_printk_get_state(&state);
    unsigned int preboot_queued = before.queued < VINIX_PRINTK_RECORD_COUNT ? before.queued + 1 : before.queued;
    assert(!state.worker_live && state.submitted == preboot && state.queued == preboot_queued);
    pthread_t ticker;
    host_logger_tick_stop = false;
    assert(!pthread_create(&ticker, NULL, host_logger_ticks, NULL));
    assert(!vinix_linuxkpi_printk_bootstrap());
    assert(!vinix_linuxkpi_printk_bootstrap() && host_logger_workers == 1);
    assert(!vinix_linuxkpi_printk_flush(preboot, 2000));
    assert(host_logger_console_bytes >= 8);
    assert(vinix_linuxkpi_printk_flush(preboot + 1, 0) == -EINVAL);
    vinix_linuxkpi_printk_get_state(&before);

    struct host_logger_capture capture;
    host_logger_install(&capture);
    /* Capture while both native-style console and caller queue locks are held.
     * Any producer console or scheduler call would deadlock this fixture. */
    assert(!pthread_mutex_lock(&host_logger_console_lock));
    assert(!pthread_mutex_lock(&controller.queue_lock));
    bool allocation_before = fail_allocation;
    fail_allocation = true;
    unsigned long flags = vinix_linuxkpi_irq_save();
    vinix_linuxkpi_preempt_disable();
    assert(_printk("%s%sowned %d\n", KERN_NOTICE, KERN_CONT, 7) == 7);
    assert(!interrupts && preempt_depth == 1 && live_pages == pages);
    assert(vinix_linuxkpi_printk_flush(vinix_linuxkpi_printk_snapshot(), 0) == -EWOULDBLOCK);
    vinix_linuxkpi_preempt_enable_no_resched();
    vinix_linuxkpi_irq_restore(flags);
    fail_allocation = allocation_before;
    assert(!pthread_mutex_unlock(&controller.queue_lock));
    assert(!pthread_mutex_unlock(&host_logger_console_lock));
    char *borrowed = malloc(16);
    assert(borrowed);
    memcpy(borrowed, "short-lived", 12);
    assert(_printk(KERN_INFO "%s\n", borrowed) == 11);
    memset(borrowed, 'X', 12);
    free(borrowed);
    assert(host_logger_nested("%s %d\n", "args", -9) == 14);
    assert(host_logger_emit(0, LOGLEVEL_ERR, NULL, KERN_DEBUG "explicit\n") == 8);
    assert(_printk_deferred("deferred\n") == 8);
    char large[VINIX_PRINTK_RECORD_BYTES + 100];
    memset(large, 'a', sizeof(large) - 1);
    large[sizeof(large) - 1] = 0;
    assert(_printk("%s", large) == VINIX_PRINTK_RECORD_BYTES - 1);
    volatile int untouched = 1234;
    const char *invalid = "before%nnever";
    assert(_printk(invalid, &untouched) == 6 && untouched == 1234);
    suppress_printk = 1;
    assert(!_printk("suppressed %s", (char *)1));
    suppress_printk = 0;
    assert(host_logger_emit(1, LOGLEVEL_DEFAULT, NULL, "facility") == -EOPNOTSUPP);
    assert(host_logger_emit(0, LOGLEVEL_DEFAULT, (void *)1, "device") == -EOPNOTSUPP);
    assert(host_logger_emit(0, 8, NULL, "level") == -EINVAL);
    vinix_linuxkpi_printk_get_state(&state);
    assert(state.queued == 7 && state.truncated == before.truncated + 1 &&
           state.format_errors == before.format_errors + 1);
    assert(vinix_linuxkpi_printk_flush(state.submitted, 0) == -ETIMEDOUT);
    host_logger_finish(&capture, 7);
    assert(!strcmp(capture.records[0].text, "owned 7") && capture.records[0].level == 5);
    assert(capture.records[0].flags == (VINIX_PRINTK_CONT | VINIX_PRINTK_NEWLINE));
    assert(!strcmp(capture.records[1].text, "short-lived"));
    assert(!strcmp(capture.records[2].text, "nested:args -9"));
    assert(capture.records[3].level == LOGLEVEL_ERR && capture.records[4].level == 4);
    assert(capture.records[5].flags & VINIX_PRINTK_TRUNCATED);
    assert(capture.records[6].format_status & VINIX_FORMAT_INVALID);

    host_logger_install(&capture);
    vinix_linuxkpi_warn_format("fixture.c", 17, NULL);
    vinix_linuxkpi_warn_format("fixture.c", 18, "owned warning %d\n", -12);
    assert(test_taint(TAINT_WARN));
    host_logger_finish(&capture, 2);
    assert(!strcmp(capture.records[0].text, "linuxkpi: warning at fixture.c:17"));
    assert(!strcmp(capture.records[1].text,
                   "linuxkpi: warning at fixture.c:18: owned warning -12"));
    assert(capture.records[0].level == LOGLEVEL_WARNING &&
           capture.records[1].level == LOGLEVEL_WARNING);

    /* Independent producers retain state through nested IRQ/preemption pins. */
    host_logger_install(&capture);
    struct host_logger_producer producers[4];
    pthread_t producer_threads[4];
    for (unsigned int i = 0; i < 4; i++) {
        producers[i].index = i;
        assert(!pthread_create(&producer_threads[i], NULL, host_logger_produce, &producers[i]));
    }
    for (unsigned int i = 0; i < 4; i++) assert(!pthread_join(producer_threads[i], NULL));
    host_logger_finish(&capture, 64);
    unsigned int seen[4] = {0};
    for (unsigned int i = 0; i < capture.count; i++) {
        unsigned int index, value;
        assert(sscanf(capture.records[i].text, "producer %u:%u", &index, &value) == 2);
        assert(index < 4 && value < 16 && !(seen[index] & (1U << value)));
        seen[index] |= 1U << value;
        if (i) assert(capture.records[i].sequence == capture.records[i - 1].sequence + 1);
    }
    for (unsigned int i = 0; i < 4; i++) assert(seen[i] == 0xffff);

    /* Overflow cannot retire a lower in-flight record whose sink is held. */
    host_logger_install(&capture);
    capture.hold = 1;
    assert(_printk("held") == 4);
    u64 held = vinix_linuxkpi_printk_snapshot();
    assert(!vinix_linuxkpi_printk_test_pause(false, 0));
    while (!__atomic_load_n(&capture.entered, __ATOMIC_ACQUIRE)) sched_yield();
    for (unsigned int i = 0; i < 80; i++) assert(_printk("overflow %u", i) >= 10);
    u64 overflow = vinix_linuxkpi_printk_snapshot();
    vinix_linuxkpi_printk_get_state(&state);
    assert(state.in_flight && state.retired == held - 1 && state.dropped == before.dropped + 16);
    assert(state.queued == 64 && vinix_linuxkpi_printk_flush(held, 0) == -ETIMEDOUT);
    __atomic_store_n(&capture.release, 1, __ATOMIC_RELEASE);
    assert(!vinix_linuxkpi_printk_flush(overflow, 2000));
    assert(capture.count == 65 && !strcmp(capture.records[1].text, "overflow 16"));
    assert(!strcmp(capture.records[64].text, "overflow 79"));
    host_logger_finish(&capture, 65);

    /* A flush snapshot is satisfied while a later record's sink is blocked. */
    host_logger_install(&capture);
    capture.hold = 3;
    assert(_printk("old") == 3);
    struct host_logger_flusher flusher = { .snapshot = vinix_linuxkpi_printk_snapshot() };
    sync_model_init(&flusher.model, 82);
    assert(!vinix_linuxkpi_printk_test_pause(false, 0));
    while (!__atomic_load_n(&capture.entered, __ATOMIC_ACQUIRE)) sched_yield();
    pthread_t flush_thread;
    assert(!pthread_create(&flush_thread, NULL, host_logger_flush_thread, &flusher));
    while (!__atomic_load_n(&flusher.entered, __ATOMIC_ACQUIRE)) sched_yield();
    assert(!__atomic_load_n(&flusher.done, __ATOMIC_ACQUIRE));
    assert(_printk("late") == 4);
    __atomic_fetch_or(&capture.release, 1, __ATOMIC_RELEASE);
    while (!(__atomic_load_n(&capture.entered, __ATOMIC_ACQUIRE) & 2)) sched_yield();
    assert(!pthread_join(flush_thread, NULL) && !flusher.result);
    sync_model_destroy(&flusher.model);
    vinix_linuxkpi_printk_get_state(&state);
    assert(state.in_flight && state.retired == flusher.snapshot && capture.count == 1);
    __atomic_fetch_or(&capture.release, 2, __ATOMIC_RELEASE);
    assert(!vinix_linuxkpi_printk_flush(vinix_linuxkpi_printk_snapshot(), 2000));
    host_logger_finish(&capture, 2);

    __atomic_store_n(&host_logger_key_available, true, __ATOMIC_RELEASE);
    for (;;) {
        vinix_linuxkpi_printk_get_state(&state);
        if (state.key_ready) break;
        sched_yield();
    }
    assert(__atomic_load_n(&host_logger_key_attempts, __ATOMIC_ACQUIRE));
    assert(!vinix_linuxkpi_printk_test_pause(false, 0));
    assert(!vinix_linuxkpi_printk_shutdown() && !host_logger_workers);
    assert(!vinix_linuxkpi_printk_shutdown());
    vinix_linuxkpi_printk_get_state(&state);
    assert(!state.worker_live && !state.in_flight && !state.queued &&
           state.retired == state.submitted && state.dropped == before.dropped + 16);
    /* Constructor reuse owns a new pthread and task and releases both. */
    assert(!vinix_linuxkpi_printk_bootstrap() && host_logger_workers == 1);
    assert(_printk(KERN_INFO "reuse\n") == 5);
    assert(!vinix_linuxkpi_printk_flush(vinix_linuxkpi_printk_snapshot(), 2000));
    assert(!vinix_linuxkpi_printk_shutdown() && !host_logger_workers);
    __atomic_store_n(&host_logger_tick_stop, true, __ATOMIC_RELEASE);
    assert(!pthread_join(ticker, NULL));
    assert(!vinix_linuxkpi_time_waiters() && live_pages == pages);
    sync_model_destroy(&controller);
    native_task = NULL;
}

/* Existing runtime tests continue to emit real warnings after the isolated
 * fixture has joined its logger. Drain those boot-lifetime ring records before
 * retiring the final host controller and checking global allocation recovery. */
static void printk_cleanup_tests(void)
{
    size_t pages = live_pages;
    struct native_task_model controller;
    sync_model_init(&controller, 83);
    native_task = &controller;
    assert(!__atomic_load_n(&host_logger_workers, __ATOMIC_ACQUIRE));
    __atomic_store_n(&host_logger_tick_stop, false, __ATOMIC_RELEASE);
    pthread_t ticker;
    assert(!pthread_create(&ticker, NULL, host_logger_ticks, NULL));
    assert(!vinix_linuxkpi_printk_bootstrap());
    u64 snapshot = vinix_linuxkpi_printk_snapshot();
    assert(!vinix_linuxkpi_printk_flush(snapshot, 2000));
    assert(!vinix_linuxkpi_printk_shutdown());
    __atomic_store_n(&host_logger_tick_stop, true, __ATOMIC_RELEASE);
    assert(!pthread_join(ticker, NULL));
    struct vinix_linuxkpi_printk_state state;
    vinix_linuxkpi_printk_get_state(&state);
    assert(!state.worker_live && !state.in_flight && !state.queued &&
           state.retired == state.submitted);
    assert(!__atomic_load_n(&host_logger_workers, __ATOMIC_ACQUIRE));
    assert(!vinix_linuxkpi_time_waiters() && live_pages == pages);
    sync_model_destroy(&controller);
    native_task = NULL;
}
