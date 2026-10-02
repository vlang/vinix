/* SPDX-License-Identifier: GPL-2.0-only */
#if defined(VINIX_LINUXKPI) && !defined(VINIX_LINUXKPI_HOST_TEST)
#include <linux/completion.h>
#include <linux/delay.h>
#include <linux/errno.h>
#include <linux/kernel.h>
#include <linux/sched.h>
#include <linux/workqueue.h>
#include <vinix/runtime.h>
#include <pthread.h>

#ifdef VINIX_LINUXKPI_TEST_TRACE
#include <linux/jiffies.h>
extern int kprintf(const char *, ...);
#define NATIVE_WORKER_TRACE(format, ...) \
    kprintf("linuxkpi: worker trace " format "\n", ##__VA_ARGS__)
#else
#define NATIVE_WORKER_TRACE(...) do { } while (0)
#endif

/* These tests use the actual anonymous kernel pthread constructor, scheduler
 * and reaper. The bridge measures a repeated batch after warming allocator
 * caches, so each injected failure must return its partial stacks/FPU/Thread. */
#define WORKER_EXIT_VALUE ((void *)0x51a9)

struct native_worker_result {
    unsigned int calls;
    int result;
    struct completion nice_ready, nice_release;
};

static void *native_worker_once(void *argument)
{
    struct native_worker_result *test = argument;
    __atomic_add_fetch(&test->calls, 1, __ATOMIC_RELAXED);
    pthread_exit(WORKER_EXIT_VALUE);
    return NULL;
}

static int native_worker_join(pthread_t thread, struct native_worker_result *test)
{
    void *value = NULL;
    NATIVE_WORKER_TRACE("join begin ticks=%lu", jiffies);
    if (pthread_join(thread, &value)) return -EIO;
    /* Join ends every writer's ownership of this stack result. Never inspect
     * the native thread pointer after the join releases its reference. */
    NATIVE_WORKER_TRACE("join complete ticks=%lu calls=%u result=%d value_ok=%u",
                        jiffies, __atomic_load_n(&test->calls, __ATOMIC_ACQUIRE),
                        test->result, value == WORKER_EXIT_VALUE);
    return value == WORKER_EXIT_VALUE &&
           __atomic_load_n(&test->calls, __ATOMIC_ACQUIRE) == 1 &&
           !test->result ? 0 : -EIO;
}

static int native_worker_failures(void)
{
    const unsigned int queue_flags[] = {
        0, WQ_UNBOUND, WQ_HIGHPRI, WQ_UNBOUND | WQ_HIGHPRI,
    };
    int result = 0;
    NATIVE_WORKER_TRACE("constructor failures begin ticks=%lu", jiffies);
    for (unsigned int repeat = 0; repeat < 20; repeat++) {
        for (int stage = 1; stage <= 4; stage++) {
            struct native_worker_result test = {0};
            pthread_t thread = (pthread_t)WORKER_EXIT_VALUE;
            NATIVE_WORKER_TRACE("constructor repeat=%u stage=%d pthread begin ticks=%lu",
                                repeat, stage, jiffies);
            vinix_linuxkpi_test_worker_oom(stage);
            int error = pthread_create(&thread, NULL, native_worker_once, &test);
            vinix_linuxkpi_test_worker_oom(0);
            NATIVE_WORKER_TRACE("constructor repeat=%u stage=%d pthread returned error=%d ticks=%lu",
                                repeat, stage, error, jiffies);
            if (!error) {
                /* An unexpectedly successful thread still owns test's stack
                 * record until join. Clean it up before reporting failure. */
                if (native_worker_join(thread, &test)) result = -EIO;
                result = -EIO;
            } else if (error != EAGAIN || thread != (pthread_t)WORKER_EXIT_VALUE ||
                       __atomic_load_n(&test.calls, __ATOMIC_ACQUIRE)) {
                result = -EIO;
            }
            for (unsigned int q = 0; q < ARRAY_SIZE(queue_flags); q++) {
                NATIVE_WORKER_TRACE("constructor repeat=%u stage=%d queue=%u flags=0x%x begin ticks=%lu",
                                    repeat, stage, q, queue_flags[q], jiffies);
                vinix_linuxkpi_test_worker_oom(stage);
                struct workqueue_struct *wq = alloc_workqueue("vinix-worker-oom",
                                                            queue_flags[q], 2);
                /* Also clear an injection if earlier metadata allocation
                 * failed before construction could consume it. */
                vinix_linuxkpi_test_worker_oom(0);
                if (wq) {
                    NATIVE_WORKER_TRACE("constructor unexpected queue success repeat=%u stage=%d queue=%u destroy begin ticks=%lu",
                                        repeat, stage, q, jiffies);
                    destroy_workqueue(wq);
                    result = -EIO;
                }
            }
            NATIVE_WORKER_TRACE("constructor repeat=%u stage=%d complete result=%d ticks=%lu",
                                repeat, stage, result, jiffies);
        }
    }
    NATIVE_WORKER_TRACE("constructor failures complete result=%d ticks=%lu", result, jiffies);
    /* A failure must not poison the next constructor or its join ownership. */
    struct native_worker_result recovery = {0};
    pthread_t thread;
    NATIVE_WORKER_TRACE("recovery pthread create begin ticks=%lu", jiffies);
    if (pthread_create(&thread, NULL, native_worker_once, &recovery)) return -ENOMEM;
    NATIVE_WORKER_TRACE("recovery pthread created ticks=%lu", jiffies);
    if (native_worker_join(thread, &recovery)) result = -EIO;
    NATIVE_WORKER_TRACE("recovery complete result=%d ticks=%lu", result, jiffies);
    return result;
}

static void native_worker_check_placement(struct native_worker_result *test,
                                          unsigned int cpu, int nice)
{
    NATIVE_WORKER_TRACE("placement check begin expected_cpu=%u nice=%d actual_cpu=%u ticks=%lu",
                        cpu, nice, vinix_linuxkpi_cpu_id(), jiffies);
    cond_resched();
    msleep(1);
    if (vinix_linuxkpi_cpu_id() != cpu || vinix_linuxkpi_worker_nice() != nice ||
        vinix_linuxkpi_worker_timeslice() != (nice == -20 ? 10000 : 5000))
        test->result = -EIO;
    NATIVE_WORKER_TRACE("placement check complete expected_cpu=%u nice=%d actual_cpu=%u result=%d ticks=%lu",
                        cpu, nice, vinix_linuxkpi_cpu_id(), test->result, jiffies);
}

static void *native_worker_context(void *argument)
{
    struct native_worker_result *test = argument;
    unsigned int cpus = vinix_linuxkpi_percpu_count();
    __atomic_add_fetch(&test->calls, 1, __ATOMIC_RELAXED);
    NATIVE_WORKER_TRACE("context actor entered cpus=%u actual_cpu=%u ticks=%lu",
                        cpus, vinix_linuxkpi_cpu_id(), jiffies);
    if (!cpus || cpus > 64 || !vinix_linuxkpi_may_sleep() ||
        vinix_linuxkpi_worker_nice() != 0) {
        test->result = -EIO;
    } else {
        for (unsigned int cpu = 0; cpu < cpus; cpu++) {
            NATIVE_WORKER_TRACE("context bind begin target=%u actual_cpu=%u ticks=%lu",
                                cpu, vinix_linuxkpi_cpu_id(), jiffies);
            if (vinix_linuxkpi_worker_bind(cpu)) test->result = -EIO;
            NATIVE_WORKER_TRACE("context bind complete target=%u actual_cpu=%u result=%d ticks=%lu",
                                cpu, vinix_linuxkpi_cpu_id(), test->result, jiffies);
            native_worker_check_placement(test, cpu, 0);
        }
        unsigned int last = cpus - 1;
        unsigned int other = cpus > 1 ? 0 : last;
        NATIVE_WORKER_TRACE("context invalid CPU/nice checks begin ticks=%lu", jiffies);
        /* Invalid requests must leave the established CPU/nice unchanged. */
        if (vinix_linuxkpi_worker_bind(cpus) != -EINVAL ||
            vinix_linuxkpi_worker_bind(~0U) != -EINVAL ||
            vinix_linuxkpi_worker_set_nice(-21) != -EINVAL ||
            vinix_linuxkpi_worker_set_nice(20) != -EINVAL)
            test->result = -EIO;
        native_worker_check_placement(test, last, 0);

        NATIVE_WORKER_TRACE("context IRQ-off checks begin ticks=%lu", jiffies);
        unsigned long flags = vinix_linuxkpi_irq_save();
        if (vinix_linuxkpi_worker_bind(other) != -EWOULDBLOCK ||
            vinix_linuxkpi_worker_set_nice(-20) != -EWOULDBLOCK ||
            (vinix_linuxkpi_irq_flags() & (1UL << 9)) ||
            vinix_linuxkpi_worker_nice() != 0 ||
            vinix_linuxkpi_cpu_id() != last)
            test->result = -EIO;
        vinix_linuxkpi_irq_restore(flags);
        native_worker_check_placement(test, last, 0);

        NATIVE_WORKER_TRACE("context preempt-disabled checks begin ticks=%lu", jiffies);
        vinix_linuxkpi_preempt_disable();
        unsigned int pinned = vinix_linuxkpi_preempt_count();
        if (!pinned || vinix_linuxkpi_worker_bind(other) != -EWOULDBLOCK ||
            vinix_linuxkpi_worker_set_nice(-20) != -EWOULDBLOCK ||
            vinix_linuxkpi_preempt_count() != pinned ||
            vinix_linuxkpi_worker_nice() != 0 ||
            vinix_linuxkpi_cpu_id() != last)
            test->result = -EIO;
        vinix_linuxkpi_preempt_enable();
        native_worker_check_placement(test, last, 0);

        NATIVE_WORKER_TRACE("context high-priority nice set begin ticks=%lu", jiffies);
        if (vinix_linuxkpi_worker_set_nice(-20)) test->result = -EIO;
        native_worker_check_placement(test, last, -20);
    }
    /* Keep the high-priority child alive while its ordinary parent checks
     * that neither their shared Process nor the parent's weight changed. */
    NATIVE_WORKER_TRACE("context nice_ready publish result=%d ticks=%lu", test->result, jiffies);
    complete(&test->nice_ready);
    wait_for_completion(&test->nice_release);
    NATIVE_WORKER_TRACE("context nice_release received ticks=%lu", jiffies);
    if (cpus && cpus <= 64)
        native_worker_check_placement(test, cpus - 1, -20);
    NATIVE_WORKER_TRACE("context actor exit result=%d ticks=%lu", test->result, jiffies);
    pthread_exit(WORKER_EXIT_VALUE);
    return NULL;
}

int vinix_linuxkpi_worker_native_selftest(void)
{
    NATIVE_WORKER_TRACE("batch begin ticks=%lu", jiffies);
    int result = native_worker_failures();
    struct native_worker_result test = {0};
    init_completion(&test.nice_ready);
    init_completion(&test.nice_release);
    if (vinix_linuxkpi_worker_nice() != 0 ||
        vinix_linuxkpi_worker_timeslice() != 5000) result = -EIO;
    NATIVE_WORKER_TRACE("controller nice check complete result=%d ticks=%lu", result, jiffies);
    pthread_t thread;
    NATIVE_WORKER_TRACE("context pthread create begin ticks=%lu", jiffies);
    if (pthread_create(&thread, NULL, native_worker_context, &test)) return -ENOMEM;
    NATIVE_WORKER_TRACE("context pthread created; wait nice_ready begin ticks=%lu", jiffies);
    if (!wait_for_completion_timeout(&test.nice_ready, 500) ||
        vinix_linuxkpi_worker_nice() != 0 ||
        vinix_linuxkpi_worker_timeslice() != 5000) result = -EIO;
    NATIVE_WORKER_TRACE("controller nice_ready wait complete result=%d ticks=%lu", result, jiffies);
    complete(&test.nice_release);
    NATIVE_WORKER_TRACE("controller nice_release published; join begin ticks=%lu", jiffies);
    if (native_worker_join(thread, &test) || vinix_linuxkpi_worker_nice() != 0 ||
        vinix_linuxkpi_worker_timeslice() != 5000) result = -EIO;
    NATIVE_WORKER_TRACE("batch complete result=%d ticks=%lu", result, jiffies);
    return result;
}
#endif
