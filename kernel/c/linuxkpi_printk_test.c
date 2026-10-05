/* SPDX-License-Identifier: GPL-2.0-only */
#if defined(VINIX_LINUXKPI) && !defined(VINIX_LINUXKPI_HOST_TEST)
#include <linux/printk.h>
#include <linux/panic.h>
#include <linux/completion.h>
#include <linux/delay.h>
#include <linux/errno.h>
#include <linux/err.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <vinix/runtime.h>
#include <vinix/format.h>
#include <vinix/printk.h>
#include <pthread.h>

/* The fixture checks owned scalar/byte snapshots, not NMI safety, pointer
 * reclamation, panic output or same-caller continuation merging. Caller 0
 * remains unknown. Root warms the permanent drain worker before page counts. */
#define NATIVE_PRINTK_EXPECT(condition) do { \
    if (!(condition) && !result) result = -(int)__LINE__; \
} while (0)
extern int kprintf(const char *, ...) __attribute__((format(printf, 1, 2)));
int vinix_linuxkpi_test_printk_locks(void);

static bool native_printk_irqs_enabled(void)
{
    return !!(vinix_linuxkpi_irq_flags() & (1UL << 9));
}

/* Called with actual native scheduler/console locks held. Never ask for a
 * task, allocate, flush or wake here: any producer console/wake would hang. */
int vinix_linuxkpi_printk_locked_probe(void)
{
    int result = 0;
    unsigned int pinned = vinix_linuxkpi_preempt_count();
    bool irqs = native_printk_irqs_enabled();
    NATIVE_PRINTK_EXPECT(_printk(KERN_INFO "native held-lock probe\n") == 22);
    NATIVE_PRINTK_EXPECT(vinix_linuxkpi_preempt_count() == pinned &&
                         native_printk_irqs_enabled() == irqs);
    return result;
}

int vinix_linuxkpi_printk_bootstrap_native_selftest(void)
{
    int result = 0;
    struct vinix_linuxkpi_printk_state state;
    vinix_linuxkpi_printk_get_state(&state);
    if (state.worker_live) return -EALREADY;
    NATIVE_PRINTK_EXPECT(_printk(KERN_INFO "native logging preboot\n") == 22);
    u64 before = vinix_linuxkpi_printk_snapshot();
    NATIVE_PRINTK_EXPECT(vinix_linuxkpi_printk_flush(before, 0) == -ENODEV);
    vinix_linuxkpi_printk_test_fail_create(true);
    int error = vinix_linuxkpi_printk_bootstrap();
    vinix_linuxkpi_printk_test_fail_create(false);
    NATIVE_PRINTK_EXPECT(error == -ENOMEM);
    vinix_linuxkpi_printk_get_state(&state);
    NATIVE_PRINTK_EXPECT(!state.worker_live && state.submitted == before);
    if (state.worker_live) {
        BUG_ON(vinix_linuxkpi_printk_shutdown());
        return result ? result : -EIO;
    }
    for (int stage = 1; stage <= 4; stage++) {
        vinix_linuxkpi_test_worker_oom(stage);
        error = vinix_linuxkpi_printk_bootstrap();
        vinix_linuxkpi_test_worker_oom(0);
        NATIVE_PRINTK_EXPECT(error == -ENOMEM);
        vinix_linuxkpi_printk_get_state(&state);
        NATIVE_PRINTK_EXPECT(!state.worker_live && state.submitted == before);
        if (state.worker_live) {
            BUG_ON(vinix_linuxkpi_printk_shutdown());
            return result ? result : -EIO;
        }
    }
    if (result) return result;
    error = vinix_linuxkpi_printk_bootstrap();
    if (error) return error;
    NATIVE_PRINTK_EXPECT(!vinix_linuxkpi_printk_bootstrap());
    NATIVE_PRINTK_EXPECT(!vinix_linuxkpi_printk_flush(before, 2000));
    vinix_linuxkpi_printk_get_state(&state);
    NATIVE_PRINTK_EXPECT(state.worker_live && state.retired == state.submitted &&
                         !state.queued && !state.in_flight);
    return result;
}

static int native_printk_nested_format(const char *format, ...)
{
    int result = 0;
    va_list args;
    va_start(args, format);
    struct va_format nested = { .fmt = format, .va = &args };
    char text[96];
    static const char expected[] = "[CRTC:7:eDP-1] mismatch in pipe mode=1920/ok\n";
    NATIVE_PRINTK_EXPECT(snprintf(text, sizeof(text),
        "[CRTC:%d:%s] mismatch in %s %pV\n", 7, "eDP-1", "pipe", &nested) ==
        sizeof(expected) - 1 && !strcmp(text, expected));
    /* %pV must va_copy rather than consuming its producer's arguments. */
    NATIVE_PRINTK_EXPECT(vsnprintf(text, sizeof(text), format, args) == 12 &&
                         !strcmp(text, "mode=1920/ok"));
    va_end(args);
    return result;
}

static int native_printk_formats(void)
{
    int result = native_printk_nested_format("mode=%u/%s", 1920U, "ok");
    char text[96];
    phys_addr_t physical = 0x1234;
    u32 fourcc = 0x3231564e;
    unsigned char bytes[] = {0xc0, 0xff, 0xee};
    unsigned long bitmap = 0xa28ac;
    NATIVE_PRINTK_EXPECT(snprintf(text, sizeof(text), "%pa", &physical) == 18 &&
                         !strcmp(text, "0x0000000000001234"));
    NATIVE_PRINTK_EXPECT(snprintf(text, sizeof(text), "%p4cc", &fourcc) == 31 &&
                         !strcmp(text, "NV12 little-endian (0x3231564e)"));
    NATIVE_PRINTK_EXPECT(snprintf(text, sizeof(text), "%3ph", bytes) == 8 &&
                         !strcmp(text, "c0 ff ee"));
    static const char ranges[] = "2-3,5,7,11,13,17,19";
    NATIVE_PRINTK_EXPECT(snprintf(text, sizeof(text), "%20pbl", &bitmap) ==
                         sizeof(ranges) - 1 && !strcmp(text, ranges));
    NATIVE_PRINTK_EXPECT(snprintf(text, sizeof(text), "%pe", ERR_PTR(-1234)) == 5 &&
                         !strcmp(text, "-1234"));
    memset(text, 'x', sizeof(text));
    NATIVE_PRINTK_EXPECT(snprintf(text, 5, "%s", "abcdef") == 6 &&
                         !strcmp(text, "abcd") && text[5] == 'x');
    NATIVE_PRINTK_EXPECT(snprintf(text, 0, "%s", "abcdef") == 6 && text[0] == 'a');
    NATIVE_PRINTK_EXPECT(scnprintf(text, 5, "%s", "abcdef") == 4 && !strcmp(text, "abcd"));
    int untouched = 37;
    const char *invalid = "before%nnever";
    NATIVE_PRINTK_EXPECT(snprintf(text, sizeof(text), invalid, &untouched) == 6 &&
                         !strcmp(text, "before") && untouched == 37);
    return result;
}

enum native_printk_phase { NATIVE_PRINTK_BASIC, NATIVE_PRINTK_PRODUCERS,
                          NATIVE_PRINTK_OVERFLOW, NATIVE_PRINTK_SNAPSHOT };
struct native_printk_capture {
    struct vinix_linuxkpi_printk_record records[16];
    struct completion first_entered, first_release, late_entered, late_release;
    enum native_printk_phase phase;
    u64 last_sequence, seen[4];
    unsigned int count;
    bool hold_first, hold_late;
    int result;
};

static void native_printk_sink(const struct vinix_linuxkpi_printk_record *record,
                               void *argument)
{
    struct native_printk_capture *capture = argument;
    int result = capture->result;
    unsigned int index = capture->count;
    NATIVE_PRINTK_EXPECT(vinix_linuxkpi_may_sleep() && native_printk_irqs_enabled() &&
                         !vinix_linuxkpi_preempt_count());
    NATIVE_PRINTK_EXPECT(record->length < VINIX_PRINTK_RECORD_BYTES &&
                         !record->text[record->length] && !record->caller &&
                         record->sequence > capture->last_sequence);
    capture->last_sequence = record->sequence;
    if (record->length >= VINIX_PRINTK_RECORD_BYTES || record->text[record->length])
        goto publish;
    if (!index) {
        NATIVE_PRINTK_EXPECT(vinix_linuxkpi_printk_flush(record->sequence, 0) == -EDEADLK);
        NATIVE_PRINTK_EXPECT(vinix_linuxkpi_printk_test_pause(true, 0) == -EDEADLK);
        NATIVE_PRINTK_EXPECT(vinix_linuxkpi_printk_shutdown() == -EDEADLK);
    }
    if (capture->phase == NATIVE_PRINTK_PRODUCERS) {
        static const char original[] = "native id=0 round=00 str=stable bytes=c0 ff ee";
        unsigned int id = (unsigned char)record->text[sizeof("native id=") - 1] - '0';
        unsigned int tens = (unsigned char)record->text[sizeof("native id=0 round=") - 1] - '0';
        unsigned int units = (unsigned char)record->text[sizeof("native id=0 round=")] - '0';
        unsigned int round = tens * 10 + units;
        NATIVE_PRINTK_EXPECT(record->length == sizeof(original) - 1 && id < 4 &&
                             tens < 10 && units < 10 && round < 64 &&
                             record->level == 6 && record->flags == VINIX_PRINTK_NEWLINE &&
                             !record->format_status);
        if (id < 4 && round < 64 && tens < 10 && units < 10) {
            char expected[sizeof(original)];
            memcpy(expected, original, sizeof(expected));
            expected[sizeof("native id=") - 1] = '0' + id;
            expected[sizeof("native id=0 round=") - 1] = '0' + round / 10;
            expected[sizeof("native id=0 round=")] = '0' + round % 10;
            NATIVE_PRINTK_EXPECT(!strcmp(record->text, expected) &&
                                 !(capture->seen[id] & (1ULL << round)));
            capture->seen[id] |= 1ULL << round;
        }
    } else if (capture->phase == NATIVE_PRINTK_OVERFLOW) {
        if (!index) NATIVE_PRINTK_EXPECT(!strcmp(record->text, "held"));
        else {
            char expected[] = "overflow=00";
            unsigned int value = index + 15;
            expected[sizeof("overflow=") - 1] = '0' + value / 10;
            expected[sizeof("overflow=")] = '0' + value % 10;
            NATIVE_PRINTK_EXPECT(index <= 64 && !strcmp(record->text, expected));
        }
    } else {
        NATIVE_PRINTK_EXPECT(index < ARRAY_SIZE(capture->records));
        if (index < ARRAY_SIZE(capture->records)) capture->records[index] = *record;
    }
publish:
    capture->result = result;
    if (!index && capture->hold_first) {
        complete(&capture->first_entered);
        wait_for_completion(&capture->first_release);
    }
    if (index == 1 && capture->hold_late) {
        complete(&capture->late_entered);
        wait_for_completion(&capture->late_release);
    }
    capture->count = index + 1;
}

static int native_printk_attach(struct native_printk_capture *capture,
                                enum native_printk_phase phase)
{
    if (vinix_linuxkpi_printk_flush(vinix_linuxkpi_printk_snapshot(), 2000)) return -EIO;
    if (vinix_linuxkpi_printk_test_pause(true, 2000)) return -EIO;
    *capture = (struct native_printk_capture){ .phase = phase };
    init_completion(&capture->first_entered); init_completion(&capture->first_release);
    init_completion(&capture->late_entered); init_completion(&capture->late_release);
    int result = vinix_linuxkpi_printk_test_sink(native_printk_sink, capture);
    if (result) BUG_ON(vinix_linuxkpi_printk_test_pause(false, 0));
    return result;
}

static int native_printk_detach(struct native_printk_capture *capture)
{
    int result = 0;
    complete_all(&capture->first_release); complete_all(&capture->late_release);
    BUG_ON(vinix_linuxkpi_printk_test_pause(false, 0));
    NATIVE_PRINTK_EXPECT(!vinix_linuxkpi_printk_flush(vinix_linuxkpi_printk_snapshot(), 2000));
    /* Never retire a sink's stack argument without quiescing every callback,
     * even when an earlier bounded assertion failed. */
    BUG_ON(vinix_linuxkpi_printk_test_pause(true, 2000));
    BUG_ON(vinix_linuxkpi_printk_test_sink(NULL, NULL));
    BUG_ON(vinix_linuxkpi_printk_test_pause(false, 0));
    return result ? result : capture->result;
}

static int native_printk_nested_emit(const char *format, ...)
{
    va_list args;
    va_start(args, format);
    struct va_format nested = { .fmt = format, .va = &args };
    int result = _printk(KERN_WARNING "nested:%pV\n", &nested);
    va_end(args);
    return result;
}

static int native_printk_basic(void)
{
    struct native_printk_capture capture;
    int result = native_printk_attach(&capture, NATIVE_PRINTK_BASIC);
    if (result) return result;
    struct vinix_linuxkpi_printk_state before, after;
    vinix_linuxkpi_printk_get_state(&before);
    struct { char text[16]; unsigned char bytes[3]; } *owned = kmalloc(sizeof(*owned), GFP_KERNEL);
    if (!owned) { result = -ENOMEM; goto out; }
    strcpy(owned->text, "short-lived");
    owned->bytes[0] = 0xc0; owned->bytes[1] = 0xff; owned->bytes[2] = 0xee;
    NATIVE_PRINTK_EXPECT(_printk(KERN_INFO "owned=%s bytes=%3ph\n", owned->text,
                                 owned->bytes) == 32);
    memset(owned, 'X', sizeof(*owned));
    kfree(owned); /* All formatting happened while these addresses were live. */
    char nested[] = "stable";
    NATIVE_PRINTK_EXPECT(native_printk_nested_emit("%s/%d", nested, -9) == 16);
    memset(nested, 'x', sizeof(nested));
    NATIVE_PRINTK_EXPECT(_printk("%s%sowned %d\n", KERN_NOTICE, KERN_CONT, 7) == 7);
    NATIVE_PRINTK_EXPECT(_printk(KERN_CONT "tail") == 4);
    NATIVE_PRINTK_EXPECT(_printk(KERN_INFO "new\n") == 3);
    NATIVE_PRINTK_EXPECT(!vinix_linuxkpi_test_printk_locks());
    vinix_linuxkpi_test_alloc_oom(0);
    unsigned long flags = vinix_linuxkpi_irq_save();
    vinix_linuxkpi_preempt_disable(); vinix_linuxkpi_preempt_disable();
    NATIVE_PRINTK_EXPECT(_printk(KERN_WARNING "atomic producer\n") == 15);
    NATIVE_PRINTK_EXPECT(!native_printk_irqs_enabled() && vinix_linuxkpi_preempt_count() == 2);
    NATIVE_PRINTK_EXPECT(vinix_linuxkpi_printk_flush(vinix_linuxkpi_printk_snapshot(), 0) == -EWOULDBLOCK);
    vinix_linuxkpi_preempt_enable_no_resched(); vinix_linuxkpi_preempt_enable_no_resched();
    vinix_linuxkpi_irq_restore(flags);
    void *probe = kmalloc(17, GFP_KERNEL);
    vinix_linuxkpi_test_alloc_oom(-1);
    NATIVE_PRINTK_EXPECT(!probe);
    kfree(probe);
    char large[VINIX_PRINTK_RECORD_BYTES + 100];
    memset(large, 'a', sizeof(large) - 1); large[sizeof(large) - 1] = 0;
    NATIVE_PRINTK_EXPECT(_printk("%s", large) == VINIX_PRINTK_RECORD_BYTES - 1);
    int untouched = 37;
    const char *invalid = "before%nnever";
    NATIVE_PRINTK_EXPECT(_printk(invalid, &untouched) == 6 && untouched == 37);
out:
    {
        int cleanup = native_printk_detach(&capture);
        if (!result) result = cleanup;
    }
    if (result) return result;
    vinix_linuxkpi_printk_get_state(&after);
    NATIVE_PRINTK_EXPECT(capture.count == 10 && native_printk_irqs_enabled() &&
                         !vinix_linuxkpi_preempt_count());
    NATIVE_PRINTK_EXPECT(after.truncated == before.truncated + 1 &&
                         after.format_errors == before.format_errors + 1);
    NATIVE_PRINTK_EXPECT(!strcmp(capture.records[0].text, "owned=short-lived bytes=c0 ff ee"));
    NATIVE_PRINTK_EXPECT(!strcmp(capture.records[1].text, "nested:stable/-9"));
    NATIVE_PRINTK_EXPECT(!strcmp(capture.records[2].text, "owned 7") &&
                         capture.records[2].level == 5 &&
                         capture.records[2].flags == (VINIX_PRINTK_CONT | VINIX_PRINTK_NEWLINE));
    NATIVE_PRINTK_EXPECT(!strcmp(capture.records[3].text, "tail") &&
                         capture.records[3].flags == VINIX_PRINTK_CONT &&
                         !strcmp(capture.records[4].text, "new") &&
                         capture.records[4].flags == VINIX_PRINTK_NEWLINE);
    NATIVE_PRINTK_EXPECT(!strcmp(capture.records[5].text, "native held-lock probe") &&
                         !strcmp(capture.records[6].text, "native held-lock probe") &&
                         !strcmp(capture.records[7].text, "atomic producer"));
    NATIVE_PRINTK_EXPECT(capture.records[8].length == VINIX_PRINTK_RECORD_BYTES - 1 &&
                         capture.records[8].flags == VINIX_PRINTK_TRUNCATED &&
                         capture.records[8].format_status == VINIX_FORMAT_TRUNCATED &&
                         !memchr_inv(capture.records[8].text, 'a', VINIX_PRINTK_RECORD_BYTES - 1));
    NATIVE_PRINTK_EXPECT(!strcmp(capture.records[9].text, "before") &&
                         capture.records[9].format_status == VINIX_FORMAT_INVALID);
    return result;
}

struct native_printk_producer {
    pthread_t thread;
    struct completion entered, go, done;
    unsigned int index, cpu, cancel;
    bool initialized, started;
    int result;
};
static void *native_printk_produce(void *argument)
{
    struct native_printk_producer *test = argument;
    int result = vinix_linuxkpi_worker_bind(test->cpu);
    complete(&test->entered);
    wait_for_completion(&test->go);
    for (unsigned int round = 0; !result && round < 64 &&
         !__atomic_load_n(&test->cancel, __ATOMIC_ACQUIRE); round++) {
        char borrowed[] = "stable";
        unsigned char bytes[] = {0xc0, 0xff, 0xee};
        unsigned int pins = (round & 2) ? 2 : 0;
        unsigned long flags = 0;
        if (round & 1) flags = vinix_linuxkpi_irq_save();
        for (unsigned int i = 0; i < pins; i++) vinix_linuxkpi_preempt_disable();
        NATIVE_PRINTK_EXPECT(_printk(KERN_INFO "native id=%u round=%02u str=%s bytes=%3ph\n",
                                     test->index, round, borrowed, bytes) == 46);
        add_taint(test->index, LOCKDEP_STILL_OK);
        NATIVE_PRINTK_EXPECT(test_taint(test->index));
        NATIVE_PRINTK_EXPECT(vinix_linuxkpi_preempt_count() == pins &&
                             native_printk_irqs_enabled() == !(round & 1));
        memset(borrowed, 'X', sizeof(borrowed)); memset(bytes, 0, sizeof(bytes));
        for (unsigned int i = 0; i < pins; i++) vinix_linuxkpi_preempt_enable_no_resched();
        if (round & 1) vinix_linuxkpi_irq_restore(flags);
        NATIVE_PRINTK_EXPECT(vinix_linuxkpi_may_sleep() && vinix_linuxkpi_cpu_id() == test->cpu);
        /* Four producers each have at most eight unretired records, leaving
         * room below the64-entry ring while retaining genuine concurrency. */
        if (round % 8 == 7) {
            NATIVE_PRINTK_EXPECT(!vinix_linuxkpi_printk_flush(vinix_linuxkpi_printk_snapshot(), 2000));
            cond_resched();
        }
    }
    test->result = result;
    complete(&test->done);
    pthread_exit(NULL);
    return NULL;
}

static int native_printk_producers(void)
{
    struct native_printk_capture capture;
    int result = native_printk_attach(&capture, NATIVE_PRINTK_PRODUCERS);
    if (result) return result;
    struct native_printk_producer tests[4] = {0};
    struct vinix_linuxkpi_printk_state before, after;
    vinix_linuxkpi_printk_get_state(&before);
    unsigned int cpus = vinix_linuxkpi_percpu_count();
    if (!cpus || cpus > 64) { result = -EOPNOTSUPP; goto out; }
    unsigned long taint_before = get_taint();
    for (unsigned int i = 0; i < ARRAY_SIZE(tests); i++) {
        tests[i].index = i; tests[i].cpu = i % cpus;
        init_completion(&tests[i].entered); init_completion(&tests[i].go);
        init_completion(&tests[i].done);
        tests[i].initialized = true;
        if (pthread_create(&tests[i].thread, NULL, native_printk_produce, &tests[i])) {
            result = -ENOMEM; goto out;
        }
        tests[i].started = true;
        if (!wait_for_completion_timeout(&tests[i].entered, 2000)) { result = -EIO; goto out; }
    }
    BUG_ON(vinix_linuxkpi_printk_test_pause(false, 0));
    for (unsigned int i = 0; i < ARRAY_SIZE(tests); i++) complete(&tests[i].go);
    for (unsigned int i = 0; i < ARRAY_SIZE(tests); i++)
        if (!wait_for_completion_timeout(&tests[i].done, 2000)) { result = -EIO; goto out; }
    NATIVE_PRINTK_EXPECT((get_taint() & (taint_before | 15UL)) == (taint_before | 15UL));
out:
    for (unsigned int i = 0; i < ARRAY_SIZE(tests); i++) {
        __atomic_store_n(&tests[i].cancel, 1, __ATOMIC_RELEASE);
        if (tests[i].initialized) complete_all(&tests[i].go);
    }
    for (unsigned int i = 0; i < ARRAY_SIZE(tests); i++) {
        if (!tests[i].started) continue;
        BUG_ON(pthread_join(tests[i].thread, NULL));
        if (!result && tests[i].result) result = tests[i].result;
    }
    {
        int cleanup = native_printk_detach(&capture);
        if (!result) result = cleanup;
    }
    if (result) return result;
    vinix_linuxkpi_printk_get_state(&after);
    NATIVE_PRINTK_EXPECT(capture.count == 256 && after.dropped == before.dropped &&
                         after.submitted == before.submitted + 256 &&
                         after.retired == after.submitted);
    for (unsigned int i = 0; i < ARRAY_SIZE(capture.seen); i++)
        NATIVE_PRINTK_EXPECT(capture.seen[i] == ~(u64)0);
    return result;
}

static int native_printk_overflow(void)
{
    struct native_printk_capture capture;
    int result = native_printk_attach(&capture, NATIVE_PRINTK_OVERFLOW);
    if (result) return result;
    capture.hold_first = true;
    struct vinix_linuxkpi_printk_state before, held, after;
    vinix_linuxkpi_printk_get_state(&before);
    NATIVE_PRINTK_EXPECT(_printk("held") == 4);
    u64 first = vinix_linuxkpi_printk_snapshot();
    BUG_ON(vinix_linuxkpi_printk_test_pause(false, 0));
    if (!wait_for_completion_timeout(&capture.first_entered, 2000)) { result = -EIO; goto out; }
    for (unsigned int i = 0; i < VINIX_PRINTK_RECORD_COUNT + 16; i++)
        NATIVE_PRINTK_EXPECT(_printk("overflow=%02u", i) == 11);
    u64 last = vinix_linuxkpi_printk_snapshot();
    vinix_linuxkpi_printk_get_state(&held);
    NATIVE_PRINTK_EXPECT(held.queued == 64 && held.in_flight &&
                         held.retired == first - 1 && held.dropped == before.dropped + 16 &&
                         held.submitted == first + 80);
    NATIVE_PRINTK_EXPECT(vinix_linuxkpi_printk_flush(first + 10, 0) == -ETIMEDOUT);
    complete(&capture.first_release);
    NATIVE_PRINTK_EXPECT(!vinix_linuxkpi_printk_flush(last, 2000));
out:
    {
        int cleanup = native_printk_detach(&capture);
        if (!result) result = cleanup;
    }
    if (result) return result;
    vinix_linuxkpi_printk_get_state(&after);
    NATIVE_PRINTK_EXPECT(capture.count == 65 && after.retired == after.submitted &&
                         !after.queued && !after.in_flight && after.dropped == before.dropped + 16);
    return result;
}

struct native_printk_flusher {
    pthread_t thread;
    struct completion entered, done;
    u64 snapshot;
    int result;
};
static void *native_printk_flush_thread(void *argument)
{
    struct native_printk_flusher *test = argument;
    complete(&test->entered);
    test->result = vinix_linuxkpi_printk_flush(test->snapshot, 2000);
    complete(&test->done);
    pthread_exit(NULL);
    return NULL;
}

static int native_printk_snapshot(void)
{
    struct native_printk_capture capture;
    int result = native_printk_attach(&capture, NATIVE_PRINTK_SNAPSHOT);
    if (result) return result;
    capture.hold_first = true; capture.hold_late = true;
    struct native_printk_flusher flusher = {0};
    bool started = false;
    init_completion(&flusher.entered); init_completion(&flusher.done);
    NATIVE_PRINTK_EXPECT(_printk("old") == 3);
    flusher.snapshot = vinix_linuxkpi_printk_snapshot();
    BUG_ON(vinix_linuxkpi_printk_test_pause(false, 0));
    if (!wait_for_completion_timeout(&capture.first_entered, 2000)) { result = -EIO; goto out; }
    if (pthread_create(&flusher.thread, NULL, native_printk_flush_thread, &flusher)) {
        result = -ENOMEM; goto out;
    }
    started = true;
    if (!wait_for_completion_timeout(&flusher.entered, 2000)) { result = -EIO; goto out; }
    NATIVE_PRINTK_EXPECT(!completion_done(&flusher.done));
    NATIVE_PRINTK_EXPECT(_printk("late") == 4);
    complete(&capture.first_release);
    if (!wait_for_completion_timeout(&capture.late_entered, 2000)) { result = -EIO; goto out; }
    NATIVE_PRINTK_EXPECT(wait_for_completion_timeout(&flusher.done, 2000) && !flusher.result);
    struct vinix_linuxkpi_printk_state state;
    vinix_linuxkpi_printk_get_state(&state);
    NATIVE_PRINTK_EXPECT(state.in_flight && state.retired == flusher.snapshot && capture.count == 1);
out:
    complete_all(&capture.first_release); complete_all(&capture.late_release);
    if (started) BUG_ON(pthread_join(flusher.thread, NULL));
    {
        int cleanup = native_printk_detach(&capture);
        if (!result) result = cleanup;
    }
    if (result) return result;
    NATIVE_PRINTK_EXPECT(capture.count == 2 && !strcmp(capture.records[0].text, "old") &&
                         !strcmp(capture.records[1].text, "late"));
    return result;
}

int vinix_linuxkpi_printk_native_selftest(void)
{
    int result = native_printk_formats();
    if (!result) result = native_printk_basic();
    if (!result) result = native_printk_producers();
    if (!result) result = native_printk_overflow();
    if (!result) result = native_printk_snapshot();
    if (result) kprintf("linuxkpi: native logging self-test failed at condition %d\n", -result);
    return result;
}
#endif
