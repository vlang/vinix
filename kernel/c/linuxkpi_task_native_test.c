/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifdef VINIX_LINUXKPI
#include <linux/bug.h>
#include <linux/errno.h>
#include <linux/kernel.h>
#include <linux/sched.h>
#include <linux/sched/signal.h>
#include <linux/sched/task.h>
#include <linux/smp.h>
#include <linux/spinlock.h>
#include <linux/string.h>
#include <linux/vtime.h>
#define TASK_TEST_FLAGS (PF_VCPU | 0x40000000U)


/* Independent native fixtures retained from the C implementation. */
#ifndef VINIX_LINUXKPI_HOST_TEST
#include <pthread.h>
void vinix_linuxkpi_test_task_signal(void *thread, u64 pending);

struct native_wait_test {
    struct task_struct *task;
    unsigned int phase;
    bool early;
    int result;
};

static void *native_wait_worker(void *argument)
{
    struct native_wait_test *test = argument;
    struct task_struct *task = get_task_struct(current);
    __atomic_fetch_or(&task->flags, TASK_TEST_FLAGS & ~PF_VCPU, __ATOMIC_RELAXED);
    vtime_account_guest_enter();
    test->task = task; /* Hand the retained reference to the controller. */
    set_current_state(TASK_UNINTERRUPTIBLE);
    __atomic_store_n(&test->phase, 1, __ATOMIC_RELEASE);
    if (test->early)
        while (__atomic_load_n(&test->phase, __ATOMIC_ACQUIRE) < 2) cond_resched();
    schedule();
    test->result = task_is_running(task) && current == task &&
        (__atomic_load_n(&task->flags, __ATOMIC_RELAXED) & TASK_TEST_FLAGS) == TASK_TEST_FLAGS ? 0 : -EIO;
    __atomic_store_n(&test->phase, 3, __ATOMIC_RELEASE);
    pthread_exit((void *)0x1234);
    return NULL;
}

int vinix_linuxkpi_task_native_selftest(void)
{
    /* Exceeds the former 64-corpse limit. Every worker's two native stacks,
     * FPU buffer and Thread must survive join/detach, then be reclaimed. */
    struct task_struct *held[70];
    int result = 0;
    for (unsigned int i = 0; i < ARRAY_SIZE(held); i++) {
        struct native_wait_test test = { .early = !!(i & 1) };
        pthread_t worker;
        BUG_ON(pthread_create(&worker, NULL, native_wait_worker, &test));
        while (__atomic_load_n(&test.phase, __ATOMIC_ACQUIRE) < 1) cond_resched();
        held[i] = test.task;
        if (wake_up_state(held[i], TASK_INTERRUPTIBLE)) result = -EIO;
        if (!test.early) {
            while (vinix_linuxkpi_task_queued(held[i]->vinix_thread)) cond_resched();
            vinix_linuxkpi_test_task_signal(held[i]->vinix_thread, 1ULL << 14);
            while (vinix_linuxkpi_task_queued(held[i]->vinix_thread)) cond_resched();
            if (__atomic_load_n(&held[i]->__state, __ATOMIC_RELAXED) != TASK_UNINTERRUPTIBLE)
                result = -EIO;
            vinix_linuxkpi_test_task_signal(held[i]->vinix_thread, 0);
        }
        if (wake_up_process(held[i]) != 1) result = -EIO;
        if (test.early) __atomic_store_n(&test.phase, 2, __ATOMIC_RELEASE);
        if (i % 3 == 0) {
            BUG_ON(pthread_detach(worker));
            while (__atomic_load_n(&test.phase, __ATOMIC_ACQUIRE) < 3) cond_resched();
        } else {
            void *value = NULL;
            BUG_ON(pthread_join(worker, &value));
            if (value != (void *)0x1234) result = -EIO;
        }
        if (test.result) result = -EIO;
        while (!vinix_linuxkpi_task_is_dead(held[i]->vinix_thread)) cond_resched();
        if (wake_up_process(held[i])) result = -EIO;
    }
    for (unsigned int i = 0; i < ARRAY_SIZE(held); i++) {
        while (__atomic_load_n(&held[i]->__state, __ATOMIC_ACQUIRE) != TASK_DEAD) cond_resched();
        unsigned int expected = TASK_TEST_FLAGS | PF_EXITING;
        if ((__atomic_load_n(&held[i]->flags, __ATOMIC_RELAXED) & expected) != expected) result = -EIO;
        if (get_task_struct(held[i]) != held[i]) result = -EIO;
        put_task_struct(held[i]);
        put_task_struct(held[i]); /* Last dereference: can free its native owner. */
    }
    return result;
}
#endif
#endif
