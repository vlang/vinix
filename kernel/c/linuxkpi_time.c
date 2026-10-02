/* SPDX-License-Identifier: GPL-2.0-only */
/* Time conversion helpers adapted from Linux kernel/time/time.c.
 * Copyright (C) 1991, 1992 Linus Torvalds. */
#ifdef VINIX_LINUXKPI
#include <linux/sched.h>
#include <linux/sched/signal.h>
#include <linux/spinlock.h>
#include <linux/list.h>
#include <linux/ktime.h>
#include <linux/delay.h>

_Static_assert(HZ == 1000 && BITS_PER_LONG == 64, "LinuxKPI time configuration");
/* Linux's two tick names must refer to the same little-endian 64-bit word. */
unsigned long volatile jiffies __cacheline_aligned_in_smp = INITIAL_JIFFIES;
#if defined(VINIX_LINUXKPI_HOST_TEST) && defined(__APPLE__)
/* Darwin's compiler rejects C aliases; its assembler supports the symbol
 * assignment. Host tests verify both names have precisely the same address. */
__asm__(".globl _jiffies_64\n.set _jiffies_64, _jiffies");
#else
extern u64 jiffies_64 __attribute__((alias("jiffies")));
#endif
static DEFINE_RAW_SPINLOCK(deadline_lock);
static LIST_HEAD(deadlines);
static u64 last_tick_ns;

struct sleep_deadline {
    struct list_head entry;
    struct task_struct *task;
    unsigned long expires;
};

void vinix_linuxkpi_time_tick(u64 now_ns)
{
    unsigned long flags;
    raw_spin_lock_irqsave(&deadline_lock, flags);
    if (now_ns >= last_tick_ns) {
        last_tick_ns = now_ns;
        unsigned long now = INITIAL_JIFFIES + now_ns / TICK_NSEC;
        __atomic_store_n(&jiffies, now, __ATOMIC_RELAXED);
        struct sleep_deadline *wait, *next;
        list_for_each_entry_safe(wait, next, &deadlines, entry) {
            if (time_after_eq(now, wait->expires)) {
                struct task_struct *task = wait->task;
                /* Removal and every task dereference finish under the lock.
                 * The waiter takes this same lock before returning. */
                list_del_init(&wait->entry);
                wake_up_process(task);
            }
        }
    }
    raw_spin_unlock_irqrestore(&deadline_lock, flags);
    vinix_linuxkpi_timer_tick();
}

size_t vinix_linuxkpi_time_waiters(void)
{
    unsigned long flags;
    size_t result = 0;
    raw_spin_lock_irqsave(&deadline_lock, flags);
    struct list_head *entry;
    list_for_each(entry, &deadlines) result++;
    raw_spin_unlock_irqrestore(&deadline_lock, flags);
    return result;
}

long schedule_timeout(long timeout)
{
    might_sleep();
    if (timeout == MAX_SCHEDULE_TIMEOUT) {
        schedule();
        return MAX_SCHEDULE_TIMEOUT;
    }
    if (timeout <= 0) {
        WARN_ON(timeout < 0);
        __set_current_state(TASK_RUNNING);
        if (!timeout) cond_resched();
        return 0;
    }
    struct sleep_deadline wait = { .task = current };
    unsigned long flags;
    raw_spin_lock_irqsave(&deadline_lock, flags);
    wait.expires = jiffies + (unsigned long)timeout;
    list_add_tail(&wait.entry, &deadlines);
    raw_spin_unlock_irqrestore(&deadline_lock, flags);
    schedule();
    raw_spin_lock_irqsave(&deadline_lock, flags);
    list_del_init(&wait.entry);
    long remaining = (long)(wait.expires - jiffies);
    raw_spin_unlock_irqrestore(&deadline_lock, flags);
    __set_current_state(TASK_RUNNING);
    return remaining > 0 ? remaining : 0;
}

long schedule_timeout_interruptible(long timeout)
{
    __set_current_state(TASK_INTERRUPTIBLE);
    return schedule_timeout(timeout);
}
long schedule_timeout_uninterruptible(long timeout)
{
    __set_current_state(TASK_UNINTERRUPTIBLE);
    return schedule_timeout(timeout);
}
long schedule_timeout_killable(long timeout)
{
    __set_current_state(TASK_KILLABLE);
    return schedule_timeout(timeout);
}
long schedule_timeout_idle(long timeout)
{
    __set_current_state(TASK_IDLE);
    return schedule_timeout(timeout);
}

/* The native HPET/TSC clock is not disciplined by an NTP service. These two
 * clock domains currently advance identically; suspend/real/TAI are absent. */
ktime_t ktime_get(void) { return (ktime_t)vinix_linuxkpi_clock_ns(); }
ktime_t ktime_get_raw(void) { return (ktime_t)vinix_linuxkpi_clock_ns(); }
u32 ktime_get_resolution_ns(void) { return vinix_linuxkpi_clock_resolution_ns(); }
void ktime_get_ts64(struct timespec64 *value) { *value = ns_to_timespec64(ktime_get()); }
void ktime_get_raw_ts64(struct timespec64 *value) { *value = ns_to_timespec64(ktime_get_raw()); }
void ktime_get_coarse_ts64(struct timespec64 *value)
{
    *value = ns_to_timespec64((get_jiffies_64() - INITIAL_JIFFIES) * TICK_NSEC);
}
time64_t ktime_get_seconds(void) { return (get_jiffies_64() - INITIAL_JIFFIES) / HZ; }

/* Conversion helpers supplement the unchanged Linux jiffies/ktime/time64
 * headers. This fixed-HZ target uses exact integer ratios. Linux's narrow
 * jiffies_to_usecs/msecs results deliberately retain unsigned truncation. */
unsigned int jiffies_to_msecs(unsigned long value) { return value; }
unsigned int jiffies_to_usecs(unsigned long value) { return value * 1000; }
u64 jiffies64_to_msecs(u64 value) { return value; }
u64 jiffies64_to_nsecs(u64 value) { return value * TICK_NSEC; }
unsigned long __msecs_to_jiffies(unsigned int value)
{
    return (int)value < 0 ? MAX_JIFFY_OFFSET : _msecs_to_jiffies(value);
}
unsigned long __usecs_to_jiffies(unsigned int value)
{
    if (value > jiffies_to_usecs(MAX_JIFFY_OFFSET)) return MAX_JIFFY_OFFSET;
    return _usecs_to_jiffies(value);
}
u64 nsecs_to_jiffies64(u64 value) { return value / TICK_NSEC; }
unsigned long nsecs_to_jiffies(u64 value) { return nsecs_to_jiffies64(value); }
clock_t jiffies_to_clock_t(unsigned long value) { return value / (HZ / USER_HZ); }
u64 jiffies_64_to_clock_t(u64 value) { return value / (HZ / USER_HZ); }
u64 nsec_to_clock_t(u64 value) { return value / (NSEC_PER_SEC / USER_HZ); }
unsigned long clock_t_to_jiffies(unsigned long value)
{
    return value >= (~0UL / (HZ / USER_HZ)) ? ~0UL : value * (HZ / USER_HZ);
}

struct timespec64 ns_to_timespec64(s64 value)
{
    struct timespec64 result = { .tv_sec = value / NSEC_PER_SEC, .tv_nsec = value % NSEC_PER_SEC };
    if (result.tv_nsec < 0) { result.tv_nsec += NSEC_PER_SEC; result.tv_sec--; }
    return result;
}
void set_normalized_timespec64(struct timespec64 *value, time64_t seconds, s64 nanoseconds)
{
    struct timespec64 remainder = ns_to_timespec64(nanoseconds);
    value->tv_sec = seconds + remainder.tv_sec;
    value->tv_nsec = remainder.tv_nsec;
}
void jiffies_to_timespec64(unsigned long ticks, struct timespec64 *value)
{
    value->tv_sec = ticks / HZ;
    value->tv_nsec = (ticks % HZ) * TICK_NSEC;
}
unsigned long timespec64_to_jiffies(const struct timespec64 *value)
{
    /* Use the upstream scaled conversion and its precise saturation point. */
    u64 seconds = value->tv_sec;
    long nanoseconds = value->tv_nsec + TICK_NSEC - 1;
    if (seconds >= MAX_SEC_IN_JIFFIES) { seconds = MAX_SEC_IN_JIFFIES; nanoseconds = 0; }
    return ((seconds * SEC_CONVERSION) +
            (((u64)nanoseconds * NSEC_CONVERSION) >> (NSEC_JIFFIE_SC - SEC_JIFFIE_SC))) >> SEC_JIFFIE_SC;
}
ktime_t ktime_add_safe(ktime_t left, ktime_t right)
{
    ktime_t result;
    if (__builtin_add_overflow(left, right, &result)) return KTIME_MAX;
    return result < 0 || result < left || result < right ? KTIME_MAX : result;
}

/* msleep retries early wakeups; converting with one extra tick prevents an
 * arm just before the next PIT interrupt from shortening the requested wait. */
void msleep(unsigned int milliseconds)
{
    unsigned long remaining = msecs_to_jiffies(milliseconds) + 1;
    while (remaining) remaining = schedule_timeout_uninterruptible(remaining);
}
unsigned long msleep_interruptible(unsigned int milliseconds)
{
    unsigned long remaining = msecs_to_jiffies(milliseconds) + 1;
    while (remaining && !signal_pending(current)) remaining = schedule_timeout_interruptible(remaining);
    return jiffies_to_msecs(remaining);
}
void ndelay(unsigned long nanoseconds)
{
    u64 start = vinix_linuxkpi_clock_ns();
    while (vinix_linuxkpi_clock_ns() - start < nanoseconds) vinix_linuxkpi_spin_wait();
}
void udelay(unsigned long microseconds)
{
    BUG_ON(microseconds > U64_MAX / NSEC_PER_USEC);
    ndelay(microseconds * NSEC_PER_USEC);
}

int vinix_linuxkpi_time_selftest(void)
{
    volatile uintptr_t tick_address = (uintptr_t)&jiffies;
    if (tick_address != (uintptr_t)&jiffies_64) return -EIO;
    u64 before = ktime_get_coarse_ns();
    u64 mono = ktime_get_ns();
    u64 raw = ktime_get_raw_ns();
    if (mono < before || raw < mono) return -EIO;
    struct timespec64 value = ns_to_timespec64(-1);
    if (value.tv_sec != -1 || value.tv_nsec != NSEC_PER_SEC - 1) return -EIO;
    if (msecs_to_jiffies(2) != 2 || usecs_to_jiffies(1001) != 2 ||
        !time_after(1UL, ULONG_MAX) || ktime_add_safe(KTIME_MAX, 1) != KTIME_MAX) return -EIO;
    return 0;
}

#ifndef VINIX_LINUXKPI_HOST_TEST
#include <pthread.h>
#include <linux/sched/task.h>
#include <linux/completion.h>
void vinix_linuxkpi_test_task_signal(void *thread, u64 pending);

struct native_time_worker {
    struct task_struct *task;
    int result;
    struct native_time_failure {
        unsigned int reasons;
        unsigned long elapsed;
        long timeout, queue, simple, completion, completed, interrupted, killable;
    } failures[8];
};

/* Permanent services may legitimately be sleeping while this fixture runs.
 * Check only its joined workers, retaining each task through this locked
 * inspection rather than racing an unrelated service's arm/expiry cycle. */
static size_t native_time_task_waiters(struct task_struct *task)
{
    unsigned long flags;
    size_t result = 0;
    raw_spin_lock_irqsave(&deadline_lock, flags);
    struct sleep_deadline *wait;
    list_for_each_entry(wait, &deadlines, entry)
        if (wait->task == task) result++;
    raw_spin_unlock_irqrestore(&deadline_lock, flags);
    return result;
}

static void *native_time_worker(void *argument)
{
    struct native_time_worker *worker = argument;
    worker->task = get_task_struct(current);
    for (unsigned int i = 0; i < 8; i++) {
        struct native_time_failure failure = {0};
        unsigned long start = jiffies;
        failure.timeout = schedule_timeout_uninterruptible(2);
        failure.elapsed = jiffies - start;
        if (failure.timeout) failure.reasons |= 1;
        if (time_before(jiffies, start + 2)) failure.reasons |= 2;
        DECLARE_WAIT_QUEUE_HEAD(queue);
        failure.queue = wait_event_timeout(queue, false, 1);
        if (failure.queue || waitqueue_active(&queue)) failure.reasons |= 4;
        DECLARE_SWAIT_QUEUE_HEAD(simple);
        failure.simple = swait_event_timeout_exclusive(simple, false, 1);
        if (failure.simple || swait_active(&simple)) failure.reasons |= 8;
        DECLARE_COMPLETION_ONSTACK(completion);
        failure.completion = wait_for_completion_timeout(&completion, 1);
        if (failure.completion || swait_active(&completion.wait)) failure.reasons |= 16;
        complete(&completion);
        failure.completed = wait_for_completion_timeout(&completion, 0);
        if (failure.completed != 1) failure.reasons |= 32;
        vinix_linuxkpi_test_task_signal(worker->task->vinix_thread, 1ULL << 14);
        failure.interrupted = wait_for_completion_interruptible_timeout(&completion, 5);
        if (failure.interrupted != -ERESTARTSYS) failure.reasons |= 64;
        /* The native signal enqueue must not finish this killable sleep. */
        failure.killable = schedule_timeout_killable(2);
        if (failure.killable) failure.reasons |= 128;
        vinix_linuxkpi_test_task_signal(worker->task->vinix_thread, 0);
        if (!task_is_running(current)) failure.reasons |= 256;
        if (!vinix_linuxkpi_may_sleep()) failure.reasons |= 512;
        if (failure.reasons) {
            worker->result = -EIO;
            worker->failures[i] = failure;
        }
    }
    pthread_exit(NULL);
    return NULL;
}

int vinix_linuxkpi_time_native_selftest(void)
{
    extern int kprintf(const char *, ...);
    extern bool vinix_linuxkpi_test_thread_reap_ready(void *owner);
    extern bool vinix_linuxkpi_test_reap_quiescent(void);
    struct native_time_worker workers[4] = {0};
    pthread_t threads[4];
    int result = 0;
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++)
        BUG_ON(pthread_create(&threads[i], NULL, native_time_worker, &workers[i]));
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++)
        BUG_ON(pthread_join(threads[i], NULL));
    u64 retirement_started = vinix_linuxkpi_clock_ns();
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++) {
        if (workers[i].result) result = -EIO;
        for (unsigned int round = 0; round < ARRAY_SIZE(workers[i].failures); round++) {
            struct native_time_failure *failure = &workers[i].failures[round];
            if (!failure->reasons) continue;
            /* Diagnostic formatting happens on the controller after join,
             * without a deadline lock or callback pin held. */
            kprintf("linuxkpi: time test worker=%u round=%u reasons=0x%x elapsed=%lu timeout=%ld queue=%ld simple=%ld completion=%ld completed=%ld interrupted=%ld killable=%ld\n",
                    i, round, failure->reasons, failure->elapsed, failure->timeout,
                    failure->queue, failure->simple, failure->completion,
                    failure->completed, failure->interrupted, failure->killable);
        }
        while (__atomic_load_n(&workers[i].task->__state, __ATOMIC_ACQUIRE) != TASK_DEAD) {
            if (vinix_linuxkpi_clock_ns() - retirement_started >= 1000000000ULL) {
                kprintf("linuxkpi: time test worker=%u did not publish TASK_DEAD\n", i);
                BUG();
            }
            cond_resched();
        }
        size_t retained = native_time_task_waiters(workers[i].task);
        if (retained) {
            kprintf("linuxkpi: time test worker=%u retained %zu timeout records after join\n", i, retained);
            /* A deadline still owns pointers into this task's stack. Do not
             * release its final pin or let the controller's fixture expire. */
            BUG();
        }
    }
    /* DEAD and join precede the final switch off the exiting task's stacks.
     * Observe every retained worker's off-stack deferred-list handoff before
     * releasing any final pin. A stable free count alone cannot prove it. */
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++)
        while (!vinix_linuxkpi_test_thread_reap_ready(workers[i].task->vinix_thread)) {
            if (vinix_linuxkpi_clock_ns() - retirement_started >= 1000000000ULL) {
                kprintf("linuxkpi: time test worker=%u did not reach off-stack reaper\n", i);
                BUG(); /* Retain all tasks and the enclosing fixture on failure. */
            }
            cond_resched();
        }
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++)
        put_task_struct(workers[i].task); /* Last access; can free the native Thread. */
    /* Another CPU can detach a ready node before this CPU's last-put scan.
     * Wait for its actual free too, without inspecting any released task. */
    while (!vinix_linuxkpi_test_reap_quiescent()) {
        if (vinix_linuxkpi_clock_ns() - retirement_started >= 1000000000ULL) {
            kprintf("linuxkpi: time test deferred frees did not finish\n");
            BUG();
        }
        cond_resched();
    }
    return result;
}
#endif
#endif
