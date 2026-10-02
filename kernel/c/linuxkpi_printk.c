/* SPDX-License-Identifier: GPL-2.0-only */
/* Bounded ordinary/IRQ printk capture. NMI and panic-console bypass are pending.
 * Producers never allocate, write the console, or wake a native task. */
#ifdef VINIX_LINUXKPI
#ifdef VINIX_LINUXKPI_HOST_TEST
#include <pthread.h>
#endif
#include <linux/printk.h>
#include <linux/sched.h>
#include <linux/sched/task.h>
#include <linux/spinlock.h>
#include <linux/mutex.h>
#include <linux/completion.h>
#include <linux/delay.h>
#include <linux/jiffies.h>
#include <linux/errno.h>
#include <linux/panic.h>
#include <linux/string.h>
#include <vinix/format.h>
#include <vinix/printk.h>
#ifndef VINIX_LINUXKPI_HOST_TEST
#include <pthread.h>
#else
void vinix_linuxkpi_host_logger_enter(void);
void vinix_linuxkpi_host_logger_leave(void);
#endif

int console_printk[4] = {
    CONSOLE_LOGLEVEL_DEFAULT, MESSAGE_LOGLEVEL_DEFAULT,
    CONSOLE_LOGLEVEL_MIN, CONSOLE_LOGLEVEL_DEFAULT,
};
int suppress_printk;
int oops_in_progress;

static DEFINE_RAW_SPINLOCK(printk_lock);
static DEFINE_MUTEX(printk_lifecycle);
static DECLARE_COMPLETION(printk_ready);
static struct vinix_linuxkpi_printk_record printk_records[VINIX_PRINTK_RECORD_COUNT];
static unsigned int printk_head, printk_count;
static u64 printk_submitted, printk_dropped, printk_truncated, printk_format_errors;
static u64 printk_in_flight;
static bool printk_stop, printk_paused, printk_key_ready, printk_fail_create;
static struct task_struct *printk_task;
static pthread_t printk_thread;
static vinix_linuxkpi_printk_sink printk_sink;
static void *printk_sink_argument;

/* One consumer emits in order. Discarding queued entries cannot retire an
 * earlier stack copy whose console/sink invocation has not returned yet. */
static u64 retired_locked(void)
{
    if (printk_in_flight) return printk_in_flight - 1;
    if (printk_count) return printk_records[printk_head].sequence - 1;
    return printk_submitted;
}

int vprintk_emit(int facility, int level, const struct dev_printk_info *dev_info,
                 const char *fmt, va_list args)
{
    if (facility || dev_info) return -EOPNOTSUPP;
    if (level < LOGLEVEL_SCHED || level > LOGLEVEL_DEBUG || !fmt) return -EINVAL;
    if (READ_ONCE(suppress_printk)) return 0;
    if (level == LOGLEVEL_SCHED) level = LOGLEVEL_DEFAULT;

    /* Materialize every borrowed string, pointer extension and nested va_list
     * before publication. No producer-owned address enters a ring record. */
    struct vinix_linuxkpi_printk_record record = {0};
    int result = vinix_linuxkpi_vformat(record.text, sizeof(record.text), fmt, args,
                                       &record.format_status);
    if (result < 0) return result;
    size_t length = (unsigned int)result;
    if (length >= sizeof(record.text)) {
        length = sizeof(record.text) - 1;
        record.flags |= VINIX_PRINTK_TRUNCATED;
    }
    if (length && record.text[length - 1] == '\n') {
        length--;
        record.flags |= VINIX_PRINTK_NEWLINE;
    }
    size_t prefix = 0;
    /* Prefixes may be produced by %s. The first numeric prefix supplies the
     * default level, while every recognized prefix is removed from the text. */
    while (length - prefix >= 2) {
        int header = printk_get_level(record.text + prefix);
        if (!header) break;
        if (header == 'c') record.flags |= VINIX_PRINTK_CONT;
        else if (level == LOGLEVEL_DEFAULT) level = header - '0';
        prefix += 2;
    }
    if (prefix) {
        length -= prefix;
        memmove(record.text, record.text + prefix, length);
    }
    record.text[length] = '\0';
    record.length = (unsigned short)length;
    record.level = (unsigned char)(level == LOGLEVEL_DEFAULT ?
                                  READ_ONCE(default_message_loglevel) & 7 : level);
    record.caller = vinix_linuxkpi_log_caller();

    unsigned long flags;
    raw_spin_lock_irqsave(&printk_lock, flags);
    /* A 64-bit boot-lifetime ordinal cannot be reused as a flush boundary. */
    BUG_ON(printk_submitted == ~(u64)0);
    record.sequence = ++printk_submitted;
    if (printk_count == VINIX_PRINTK_RECORD_COUNT) {
        printk_head = (printk_head + 1) % VINIX_PRINTK_RECORD_COUNT;
        printk_count--;
        printk_dropped++;
    }
    unsigned int slot = (printk_head + printk_count) % VINIX_PRINTK_RECORD_COUNT;
    printk_records[slot] = record;
    printk_count++;
    if (record.flags & VINIX_PRINTK_TRUNCATED) printk_truncated++;
    if (record.format_status & (VINIX_FORMAT_INVALID | VINIX_FORMAT_UNSUPPORTED))
        printk_format_errors++;
    raw_spin_unlock_irqrestore(&printk_lock, flags);
    /* Linux printk returns stored payload bytes, excluding level headers and
     * its separately represented trailing newline. This is not snprintf. */
    return (int)length;
}

int vprintk(const char *fmt, va_list args)
{
    return vprintk_emit(0, LOGLEVEL_DEFAULT, NULL, fmt, args);
}
int _printk(const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    int result = vprintk(fmt, args);
    va_end(args);
    return result;
}
int _printk_deferred(const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    int result = vprintk_emit(0, LOGLEVEL_SCHED, NULL, fmt, args);
    va_end(args);
    return result;
}
void vinix_linuxkpi_warn_format(const char *file, int line, const char *fmt, ...)
{
    add_taint(TAINT_WARN, LOCKDEP_STILL_OK);
    if (!fmt) {
        _printk(KERN_WARNING "linuxkpi: warning at %s:%d\n", file, line);
        return;
    }
    va_list args;
    va_start(args, fmt);
    struct va_format nested = { .fmt = fmt, .va = &args };
    _printk(KERN_WARNING "linuxkpi: warning at %s:%d: %pV", file, line, &nested);
    va_end(args);
}

u64 vinix_linuxkpi_printk_snapshot(void)
{
    unsigned long flags;
    raw_spin_lock_irqsave(&printk_lock, flags);
    u64 snapshot = printk_submitted;
    raw_spin_unlock_irqrestore(&printk_lock, flags);
    return snapshot;
}
void vinix_linuxkpi_printk_get_state(struct vinix_linuxkpi_printk_state *state)
{
    unsigned long flags;
    raw_spin_lock_irqsave(&printk_lock, flags);
    *state = (struct vinix_linuxkpi_printk_state){
        .submitted = printk_submitted, .retired = retired_locked(),
        .dropped = printk_dropped, .truncated = printk_truncated,
        .format_errors = printk_format_errors, .queued = printk_count,
        .in_flight = !!printk_in_flight, .worker_live = !!printk_task,
        .paused = printk_paused, .key_ready = printk_key_ready,
    };
    raw_spin_unlock_irqrestore(&printk_lock, flags);
}

int vinix_linuxkpi_printk_flush(u64 snapshot, unsigned int timeout_ms)
{
    if (!vinix_linuxkpi_may_sleep()) return -EWOULDBLOCK;
    struct task_struct *caller = current;
    unsigned long deadline = jiffies + msecs_to_jiffies(timeout_ms);
    for (;;) {
        unsigned long flags;
        raw_spin_lock_irqsave(&printk_lock, flags);
        int result = 1;
        if (snapshot > printk_submitted) result = -EINVAL;
        else if (caller == printk_task) result = -EDEADLK;
        else if (retired_locked() >= snapshot) result = 0;
        else if (!printk_task) result = -ENODEV;
        raw_spin_unlock_irqrestore(&printk_lock, flags);
        if (result != 1) return result;
        if (time_after_eq(jiffies, deadline)) return -ETIMEDOUT;
        msleep(1);
    }
}

static void *printk_worker(void *argument)
{
#ifdef VINIX_LINUXKPI_HOST_TEST
    vinix_linuxkpi_host_logger_enter();
#endif
    struct task_struct *task = get_task_struct(current);
    unsigned long flags;
    raw_spin_lock_irqsave(&printk_lock, flags);
    printk_task = task;
    raw_spin_unlock_irqrestore(&printk_lock, flags);
    complete(&printk_ready);
    for (;;) {
        struct vinix_linuxkpi_printk_record record;
        vinix_linuxkpi_printk_sink sink;
        void *sink_argument;
        raw_spin_lock_irqsave(&printk_lock, flags);
        bool stop = printk_stop && !printk_count;
        bool ready = !printk_paused && printk_count;
        bool key_ready = printk_key_ready;
        if (ready) {
            record = printk_records[printk_head];
            printk_head = (printk_head + 1) % VINIX_PRINTK_RECORD_COUNT;
            printk_count--;
            printk_in_flight = record.sequence;
            sink = printk_sink;
            sink_argument = printk_sink_argument;
        }
        raw_spin_unlock_irqrestore(&printk_lock, flags);
        if (stop) break;
        if (!key_ready) {
            u64 key[2];
            if (vinix_linuxkpi_log_key(key)) {
                int result = vinix_linuxkpi_format_set_key(key);
                raw_spin_lock_irqsave(&printk_lock, flags);
                if (!result || result == -EALREADY) printk_key_ready = true;
                raw_spin_unlock_irqrestore(&printk_lock, flags);
                /* Wipe the worker's borrowed secret after immutable publish. */
                __atomic_store_n(&key[0], 0, __ATOMIC_RELAXED);
                __atomic_store_n(&key[1], 0, __ATOMIC_RELAXED);
                barrier();
            }
        }
        if (!ready) {
            msleep(10);
            continue;
        }
        BUG_ON(!vinix_linuxkpi_may_sleep());
        if (sink) sink(&record, sink_argument);
        else if (record.level < READ_ONCE(console_loglevel)) {
            /* Independent records, including unknown-caller continuations.
             * The native console receives one owned byte range per record. */
            record.text[record.length] = '\n';
            vinix_linuxkpi_log_write(record.text, (size_t)record.length + 1);
        }
        raw_spin_lock_irqsave(&printk_lock, flags);
        BUG_ON(printk_in_flight != record.sequence);
        printk_in_flight = 0;
        raw_spin_unlock_irqrestore(&printk_lock, flags);
    }
#ifdef VINIX_LINUXKPI_HOST_TEST
    vinix_linuxkpi_host_logger_leave();
#endif
    /* Native pthreads enter the callback directly; no return trampoline owns
     * their exit. The join and retained task reference cover this transition. */
    pthread_exit(NULL);
    return NULL;
}

int vinix_linuxkpi_printk_bootstrap(void)
{
    if (!vinix_linuxkpi_may_sleep()) return -EWOULDBLOCK;
    struct task_struct *caller = current;
    unsigned long flags;
    raw_spin_lock_irqsave(&printk_lock, flags);
    bool self = caller == printk_task;
    raw_spin_unlock_irqrestore(&printk_lock, flags);
    if (self) return 0;
    mutex_lock(&printk_lifecycle);
    raw_spin_lock_irqsave(&printk_lock, flags);
    bool live = printk_task != NULL;
    if (live) {
        raw_spin_unlock_irqrestore(&printk_lock, flags);
        mutex_unlock(&printk_lifecycle);
        return 0;
    }
    printk_stop = false;
    bool fail = printk_fail_create;
    printk_fail_create = false;
    raw_spin_unlock_irqrestore(&printk_lock, flags);
    reinit_completion(&printk_ready);
    if (fail || pthread_create(&printk_thread, NULL, printk_worker, NULL)) {
        mutex_unlock(&printk_lifecycle);
        return -ENOMEM;
    }
    wait_for_completion(&printk_ready);
    mutex_unlock(&printk_lifecycle);
    return 0;
}
int vinix_linuxkpi_printk_shutdown(void)
{
    if (!vinix_linuxkpi_may_sleep()) return -EWOULDBLOCK;
    struct task_struct *caller = current;
    unsigned long flags;
    raw_spin_lock_irqsave(&printk_lock, flags);
    bool self = caller == printk_task;
    raw_spin_unlock_irqrestore(&printk_lock, flags);
    /* Never wait for a lifecycle owner which may already be joining us. */
    if (self) return -EDEADLK;
    mutex_lock(&printk_lifecycle);
    raw_spin_lock_irqsave(&printk_lock, flags);
    struct task_struct *task = printk_task;
    if (task == caller) {
        raw_spin_unlock_irqrestore(&printk_lock, flags);
        mutex_unlock(&printk_lifecycle);
        return -EDEADLK;
    }
    if (!task) {
        raw_spin_unlock_irqrestore(&printk_lock, flags);
        mutex_unlock(&printk_lifecycle);
        return 0;
    }
    printk_stop = true;
    printk_paused = false;
    raw_spin_unlock_irqrestore(&printk_lock, flags);
    BUG_ON(pthread_join(printk_thread, NULL));
    raw_spin_lock_irqsave(&printk_lock, flags);
    BUG_ON(printk_count || printk_in_flight);
    printk_task = NULL;
    printk_sink = NULL;
    printk_sink_argument = NULL;
    raw_spin_unlock_irqrestore(&printk_lock, flags);
    put_task_struct(task);
    mutex_unlock(&printk_lifecycle);
    return 0;
}

int vinix_linuxkpi_printk_test_pause(bool pause, unsigned int timeout_ms)
{
    if (!vinix_linuxkpi_may_sleep()) return -EWOULDBLOCK;
    struct task_struct *caller = current;
    unsigned long deadline = jiffies + msecs_to_jiffies(timeout_ms);
    for (;;) {
        unsigned long flags;
        raw_spin_lock_irqsave(&printk_lock, flags);
        if (caller == printk_task) {
            raw_spin_unlock_irqrestore(&printk_lock, flags);
            return -EDEADLK;
        }
        printk_paused = pause;
        bool busy = printk_in_flight != 0;
        raw_spin_unlock_irqrestore(&printk_lock, flags);
        if (!pause || !busy) return 0;
        if (time_after_eq(jiffies, deadline)) return -ETIMEDOUT;
        msleep(1);
    }
}
int vinix_linuxkpi_printk_test_sink(vinix_linuxkpi_printk_sink sink, void *argument)
{
    if (!vinix_linuxkpi_may_sleep()) return -EWOULDBLOCK;
    unsigned long flags;
    raw_spin_lock_irqsave(&printk_lock, flags);
    int result = -EBUSY;
    if (printk_paused && !printk_in_flight) {
        printk_sink = sink;
        printk_sink_argument = argument;
        result = 0;
    }
    raw_spin_unlock_irqrestore(&printk_lock, flags);
    return result;
}
void vinix_linuxkpi_printk_test_fail_create(bool fail)
{
    unsigned long flags;
    raw_spin_lock_irqsave(&printk_lock, flags);
    printk_fail_create = fail;
    raw_spin_unlock_irqrestore(&printk_lock, flags);
}
#endif
