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

/* Must match proc.Thread.linuxkpi_task, an aligned, zeroed 64-byte buffer.
 * No allocation or independent lifetime: retained references pin its owner. */
_Static_assert(sizeof(struct task_struct) <= 64, "native task view buffer is too small");
_Static_assert(_Alignof(struct task_struct) <= _Alignof(u64), "native task view alignment");

static void copy_comm(char *destination, const char *name, size_t length)
{
    size_t count = length < TASK_COMM_LEN - 1 ? length : TASK_COMM_LEN - 1;
    if (count) memcpy(destination, name, count);
    memset(destination + count, 0, TASK_COMM_LEN - count);
}

void vinix_linuxkpi_task_init(void *storage, void *thread, int pid, int tgid,
                            const char *name, size_t length)
{
    BUG_ON(!storage || !thread);
    struct task_struct *task = storage;
    task->vinix_thread = thread;
    task->pid = pid;
    task->tgid = tgid;
    task->flags = 0;
    task->__state = TASK_RUNNING;
    task->in_iowait = 0;
    raw_spin_lock_init(&task->vinix_wait_lock);
    copy_comm(task->vinix_initial_comm, name, length);
    memcpy(task->comm, task->vinix_initial_comm, TASK_COMM_LEN);
}

void vinix_linuxkpi_task_inherit(void *storage, void *thread, int pid, int tgid,
                               const void *source)
{
    const struct task_struct *parent = source;
    vinix_linuxkpi_task_init(storage, thread, pid, tgid, parent->comm, TASK_COMM_LEN);
}

void *vinix_linuxkpi_task_view(void *storage, void *thread, int pid, int tgid,
                             const char *name, size_t length, bool exiting)
{
    BUG_ON(!storage || !thread);
    struct task_struct *task = storage;
    BUG_ON(task->vinix_thread != thread);
    /* IDs are immutable after construction; a retained view never needs to
     * read a process that could already have been destroyed. */
    BUG_ON(task->pid != pid || task->tgid != tgid);
    /* Linux task flags belong to the task, not this native name/ID refresh.
     * Exit is terminal: a late non-exiting native snapshot must not erase it
     * or flags set by unchanged driver inlines. */
    if (exiting) __atomic_fetch_or(&task->flags, PF_EXITING, __ATOMIC_RELAXED);
    if (length) copy_comm(task->comm, name, length);
    else memcpy(task->comm, task->vinix_initial_comm, TASK_COMM_LEN);
    return task;
}

void vinix_linuxkpi_task_dead(void *storage)
{
    struct task_struct *task = storage;
    unsigned long flags;
    raw_spin_lock_irqsave(&task->vinix_wait_lock, flags);
    __atomic_fetch_or(&task->flags, PF_EXITING, __ATOMIC_RELAXED);
    __atomic_store_n(&task->__state, TASK_DEAD, __ATOMIC_RELEASE);
    raw_spin_unlock_irqrestore(&task->vinix_wait_lock, flags);
}

void vinix_linuxkpi_set_task_state(unsigned int state)
{
    /* Only ordinary waits are implemented. Special stopped/parked/frozen
     * states require separate scheduler and lifetime protocols. */
    BUG_ON(state != TASK_RUNNING && state != TASK_INTERRUPTIBLE &&
           state != TASK_UNINTERRUPTIBLE && state != TASK_KILLABLE && state != TASK_IDLE);
    /* Linux set_current_state requires a full store barrier before the
     * caller tests its condition. Using it for __set_current_state is safe. */
    __atomic_store_n(&current->__state, state, __ATOMIC_SEQ_CST);
}

void schedule(void)
{
    BUG_ON(!vinix_linuxkpi_may_sleep());
    struct task_struct *task = current;
    bool first = true;
    for (;;) {
        unsigned long flags;
        raw_spin_lock_irqsave(&task->vinix_wait_lock, flags);
        unsigned int state = __atomic_load_n(&task->__state, __ATOMIC_RELAXED);
        BUG_ON(state == TASK_DEAD);
        if (state == TASK_RUNNING) {
            raw_spin_unlock_irqrestore(&task->vinix_wait_lock, flags);
            if (first) (void)cond_resched();
            return;
        }
        /* Remove first, then check signals: native signal delivery can enqueue
         * independently of this lock. A signal before removal remains pending;
         * one after the check leaves a queue entry before we actually switch. */
        vinix_linuxkpi_task_dequeue(task->vinix_thread);
        if (signal_pending_state(state, task)) {
            BUG_ON(!vinix_linuxkpi_task_enqueue(task->vinix_thread));
            __atomic_store_n(&task->__state, TASK_RUNNING, __ATOMIC_RELAXED);
            raw_spin_unlock_irqrestore(&task->vinix_wait_lock, flags);
            return;
        }
        /* Intent belongs to this current task. Ordinary waits need no new
         * native queue-lock acquisition; real I/O admission is serialized
         * against every wake after accepted signals have been excluded. */
        if (vinix_linuxkpi_task_in_iowait(task))
            vinix_linuxkpi_iowait_block(task->vinix_thread);
        raw_spin_unlock_irqrestore(&task->vinix_wait_lock, flags);
        vinix_linuxkpi_task_park();
        /* Native signal delivery wakes every unmasked signal. Only the Linux
         * state filter above, or wake_up_state changing it to RUNNING, accepts
         * that enqueue. A disallowed signal has to go back to sleep. */
        first = false;
    }
}

int wake_up_state(struct task_struct *task, unsigned int state)
{
    unsigned long flags;
    raw_spin_lock_irqsave(&task->vinix_wait_lock, flags);
    /* Pair the caller's preceding condition publication with the waiter's
     * full set_current_state barrier, including on a wake that finds it running. */
    __atomic_thread_fence(__ATOMIC_SEQ_CST);
    unsigned int previous = __atomic_load_n(&task->__state, __ATOMIC_RELAXED);
    int woke = 0;
    if ((previous & state) && (previous & TASK_NORMAL) &&
        !vinix_linuxkpi_task_is_dead(task->vinix_thread)) {
        __atomic_store_n(&task->__state, TASK_RUNNING, __ATOMIC_RELAXED);
        if (vinix_linuxkpi_task_enqueue(task->vinix_thread)) woke = 1;
        else {
            /* Exiting concurrently is legitimate; a full native run queue
             * must fail explicitly rather than silently losing this wake. */
            BUG_ON(!vinix_linuxkpi_task_is_dead(task->vinix_thread));
            /* Native death can precede task_dead obtaining our wait lock.
             * Every acquired TASK_DEAD publication also exposes EXITING. */
            __atomic_fetch_or(&task->flags, PF_EXITING, __ATOMIC_RELAXED);
            __atomic_store_n(&task->__state, TASK_DEAD, __ATOMIC_RELEASE);
        }
    }
    raw_spin_unlock_irqrestore(&task->vinix_wait_lock, flags);
    return woke;
}

int wake_up_process(struct task_struct *task)
{
    return wake_up_state(task, TASK_NORMAL);
}

/* Exercise both an upstream-owned bit and an independent sentinel without
 * changing task layout or allocating test records. */
#define TASK_TEST_FLAGS (PF_VCPU | 0x40000000U)

int vinix_linuxkpi_task_selftest(void)
{
    struct task_struct *task = current;
    int pid = task_pid_nr(task), tgid = task_tgid_nr(task);
    if (!task->comm[0] || strnlen(task->comm, TASK_COMM_LEN) == TASK_COMM_LEN) return -EIO;
    unsigned int original_flags = __atomic_fetch_or(&task->flags, TASK_TEST_FLAGS & ~PF_VCPU, __ATOMIC_RELAXED);
    vtime_account_guest_enter();
    unsigned int cpu = get_cpu();
    int result = 0;
    if (smp_processor_id() != cpu || raw_smp_processor_id() != cpu || cond_resched()) result = -EIO;
    put_cpu();
    unsigned long flags = vinix_linuxkpi_irq_save();
    if (cond_resched()) result = -EIO;
    vinix_linuxkpi_irq_restore(flags);
    if (cond_resched() != 1 || current != task || task_pid_nr(task) != pid ||
        task_tgid_nr(task) != tgid) result = -EIO;
    if ((__atomic_load_n(&current->flags, __ATOMIC_RELAXED) & TASK_TEST_FLAGS) != TASK_TEST_FLAGS)
        result = -EIO;
    vtime_account_guest_exit();
    if ((__atomic_load_n(&current->flags, __ATOMIC_RELAXED) & TASK_TEST_FLAGS) != (TASK_TEST_FLAGS & ~PF_VCPU))
        result = -EIO;
    if (original_flags & PF_VCPU) vtime_account_guest_enter();
    /* Remove only bits introduced here; preserve terminal exit and every
     * pre-existing current-task flag. */
    __atomic_fetch_and(&task->flags, ~(TASK_TEST_FLAGS & ~original_flags), __ATOMIC_RELAXED);
    return result;
}

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
