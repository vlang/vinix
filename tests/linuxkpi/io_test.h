/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_IO_TEST_H
#define VINIX_IO_TEST_H
/* Real LinuxKPI I/O wait APIs, with native run-queue transitions instrumented
 * by the shared host task model. This file owns only accounting observations;
 * intent nesting, waits, deadlines and signal filtering use the C backends. */
#include <linux/sched/stat.h>

static unsigned int host_iowait_counts[4];
static _Thread_local void (*host_iowait_before_block)(struct native_task_model *);

/* Called by successful native enqueue/dead dequeue while queue_lock is held. */
static void host_iowait_end_locked(struct native_task_model *task)
{
    if (!task->iowait_cpu_plus_one) return;
    assert(!task->queued);
    unsigned int cpu = task->iowait_cpu_plus_one - 1;
    assert(cpu < ARRAY_SIZE(host_iowait_counts));
    assert(__atomic_fetch_sub(&host_iowait_counts[cpu], 1, __ATOMIC_ACQ_REL));
    task->iowait_cpu_plus_one = 0;
}

void vinix_linuxkpi_iowait_block(void *owner)
{
    struct native_task_model *task = owner;
    assert(task == native_task);
    if (host_iowait_before_block) {
        void (*hook)(struct native_task_model *) = host_iowait_before_block;
        host_iowait_before_block = NULL;
        hook(task);
    }
    assert(!pthread_mutex_lock(&task->queue_lock));
    if (!task->queued && !task->dead && vinix_linuxkpi_task_in_iowait(task->storage)) {
        assert(!task->iowait_cpu_plus_one);
        assert(current_cpu < ARRAY_SIZE(host_iowait_counts));
        __atomic_fetch_add(&host_iowait_counts[current_cpu], 1, __ATOMIC_ACQ_REL);
        task->iowait_cpu_plus_one = current_cpu + 1;
    }
    assert(!pthread_mutex_unlock(&task->queue_lock));
}

unsigned int vinix_linuxkpi_iowait_count(unsigned int cpu)
{
    assert(cpu < ARRAY_SIZE(host_iowait_counts));
    return __atomic_load_n(&host_iowait_counts[cpu], __ATOMIC_ACQUIRE);
}

static void io_test_wait(unsigned int *value, unsigned int expected)
{
    for (unsigned int spin = 0; spin < 1000000; spin++) {
        if (__atomic_load_n(value, __ATOMIC_ACQUIRE) >= expected) return;
        sched_yield();
    }
    assert(!"I/O waiter failed to make progress");
}

enum io_test_operation { IO_TEST_DIRECT, IO_TEST_TIMEOUT, IO_TEST_PLAIN,
    IO_TEST_BIT, IO_TEST_BIT_LOCK, IO_TEST_BIT_TIMEOUT, IO_TEST_NESTED };
struct io_test_actor {
    struct native_task_model model;
    pthread_t thread;
    unsigned long *word;
    enum io_test_operation operation;
    unsigned int cpu, state, entered, returned, release, done;
    unsigned int before_block_calls;
    long timeout, result;
    bool signal_before_block;
};
static _Thread_local struct io_test_actor *io_test_current;

static void io_test_wake_before_block(struct native_task_model *task)
{
    assert(io_test_current && io_test_current->signal_before_block);
    __atomic_fetch_add(&io_test_current->before_block_calls, 1, __ATOMIC_RELEASE);
    /* Signal delivery occurs independently of the Linux task wait lock.
     * Enqueue before the accounting helper sees the task: it must not count
     * an already runnable task, and schedule's next scan must accept signal. */
    __atomic_store_n(&task->pending, 1ULL << 14, __ATOMIC_RELEASE);
    assert(vinix_linuxkpi_task_enqueue(task));
}

static void *io_test_thread(void *argument)
{
    struct io_test_actor *actor = argument;
    native_task = &actor->model;
    current_cpu = actor->cpu;
    io_test_current = actor;
    if (actor->signal_before_block) host_iowait_before_block = io_test_wake_before_block;
    __atomic_store_n(&actor->entered, 1, __ATOMIC_RELEASE);
    if (actor->operation == IO_TEST_BIT)
        actor->result = wait_on_bit_io(actor->word, 3, actor->state);
    else if (actor->operation == IO_TEST_BIT_LOCK)
        actor->result = wait_on_bit_lock_io(actor->word, 3, actor->state);
    else if (actor->operation == IO_TEST_BIT_TIMEOUT)
        actor->result = out_of_line_wait_on_bit_timeout(actor->word, 3, bit_wait_io_timeout,
                                                        actor->state, actor->timeout);
    else if (actor->operation == IO_TEST_NESTED) {
        int outer = io_schedule_prepare(), inner = io_schedule_prepare();
        assert(!outer && inner == 1 && vinix_linuxkpi_task_in_iowait(actor->model.storage));
        set_current_state(actor->state);
        io_schedule();
        assert(vinix_linuxkpi_task_in_iowait(actor->model.storage));
        io_schedule_finish(inner);
        assert(vinix_linuxkpi_task_in_iowait(actor->model.storage));
        io_schedule_finish(outer);
    } else {
        set_current_state(actor->state);
        if (actor->operation == IO_TEST_TIMEOUT) actor->result = io_schedule_timeout(actor->timeout);
        else if (actor->operation == IO_TEST_PLAIN) schedule();
        else io_schedule();
    }
    assert(task_is_running(current) && interrupts && !preempt_depth);
    assert(!vinix_linuxkpi_task_in_iowait(actor->model.storage));
    assert(!actor->model.iowait_cpu_plus_one && !host_iowait_before_block);
    __atomic_store_n(&actor->returned, 1, __ATOMIC_RELEASE);
    if (actor->operation == IO_TEST_BIT_LOCK && !actor->result) {
        assert(test_bit(3, actor->word));
        io_test_wait(&actor->release, 1);
        clear_and_wake_up_bit(3, actor->word);
    }
    __atomic_store_n(&actor->done, 1, __ATOMIC_RELEASE);
    native_task = NULL;
    io_test_current = NULL;
    return NULL;
}

static void io_test_start(struct io_test_actor *actor, enum io_test_operation operation,
                          unsigned int cpu, unsigned int state)
{
    actor->operation = operation;
    actor->cpu = cpu;
    actor->state = state;
    sync_model_init(&actor->model, 240 + cpu);
    actor->model.iteration = 1;
    assert(!pthread_create(&actor->thread, NULL, io_test_thread, actor));
    io_test_wait(&actor->entered, 1);
}

static void io_test_parked(struct io_test_actor *actor)
{
    io_test_wait(&actor->model.parked, 1);
    assert(!vinix_linuxkpi_task_queued(&actor->model));
    if (actor->operation == IO_TEST_PLAIN)
        assert(!actor->model.iowait_cpu_plus_one);
    else {
        assert(vinix_linuxkpi_task_in_iowait(actor->model.storage));
        assert(actor->model.iowait_cpu_plus_one == actor->cpu + 1);
    }
}

static void io_test_join(struct io_test_actor *actor)
{
    io_test_wait(&actor->done, 1);
    assert(!pthread_join(actor->thread, NULL));
    assert(!actor->model.iowait_cpu_plus_one);
    sync_model_destroy(&actor->model);
}

static void io_test_zero_counts(void)
{
    assert(!nr_iowait());
    for (unsigned int cpu = 0; cpu < 4; cpu++) assert(!nr_iowait_cpu(cpu));
}

static void io_test_count_wait(unsigned int cpu, unsigned int expected)
{
    for (unsigned int spin = 0; spin < 1000000; spin++) {
        if (nr_iowait_cpu(cpu) == expected) return;
        sched_yield();
    }
    assert(!"I/O accounting transition failed to make progress");
}

static void io_test_tokens(void)
{
    io_test_zero_counts();
    assert(!vinix_linuxkpi_task_in_iowait(native_task->storage));
    int outer = io_schedule_prepare();
    assert(!outer && vinix_linuxkpi_task_in_iowait(native_task->storage));
    int inner = io_schedule_prepare();
    assert(inner == 1 && vinix_linuxkpi_task_in_iowait(native_task->storage));
    struct native_task_model child;
    sync_model_init(&child, 250);
    vinix_linuxkpi_task_inherit(child.storage, &child, child.pid, child.tgid, native_task->storage);
    assert(!vinix_linuxkpi_task_in_iowait(child.storage));
    sync_model_destroy(&child);
    io_test_zero_counts(); /* Intent alone never counts a runnable task. */
    io_schedule(); /* RUNNING: yield, preserve nested intent, no I/O count. */
    set_current_state(TASK_UNINTERRUPTIBLE);
    assert(!io_schedule_timeout(0));
    assert(task_is_running(current) && vinix_linuxkpi_task_in_iowait(native_task->storage));
    io_test_zero_counts();
    io_schedule_finish(inner);
    assert(vinix_linuxkpi_task_in_iowait(native_task->storage));
    io_schedule_finish(outer);
    assert(!vinix_linuxkpi_task_in_iowait(native_task->storage));
    native_task->pending = 1ULL << 14;
    set_current_state(TASK_INTERRUPTIBLE);
    assert(io_schedule_timeout(10) == 10);
    assert(task_is_running(current) && !vinix_linuxkpi_task_in_iowait(native_task->storage));
    native_task->pending = 0;
    io_test_zero_counts();
    assert(!vinix_linuxkpi_time_waiters());
}

static void io_test_cpu_counts(void)
{
    struct io_test_actor actors[4] = {{0}};
    const unsigned int cpus[] = {1, 1, 3, 2};
    for (unsigned int i = 0; i < ARRAY_SIZE(actors); i++) {
        io_test_start(&actors[i], i == 3 ? IO_TEST_PLAIN : IO_TEST_DIRECT, cpus[i], TASK_UNINTERRUPTIBLE);
        io_test_parked(&actors[i]);
    }
    assert(nr_iowait() == 3 && nr_iowait_cpu(1) == 2 && nr_iowait_cpu(3) == 1);
    assert(!nr_iowait_cpu(0) && !nr_iowait_cpu(2));
    current_cpu = 0; /* Wake from another CPU must debit the blocking origin. */
    for (unsigned int i = 0; i < ARRAY_SIZE(actors); i++) {
        assert(wake_up_process((struct task_struct *)actors[i].model.storage));
        assert(!actors[i].model.iowait_cpu_plus_one);
        assert(!wake_up_process((struct task_struct *)actors[i].model.storage));
        assert(nr_iowait() == (i < 3 ? 2 - i : 0));
        io_test_join(&actors[i]);
    }
    io_test_zero_counts();
}

static void io_test_deadlines(void)
{
    for (unsigned int outcome = 0; outcome < 3; outcome++) {
        struct io_test_actor actor = { .timeout = 10 };
        io_test_start(&actor, IO_TEST_TIMEOUT, outcome, TASK_INTERRUPTIBLE);
        io_test_parked(&actor);
        assert(nr_iowait_cpu(outcome) == 1 && nr_iowait() == 1 && vinix_linuxkpi_time_waiters() == 1);
        host_time_advance(outcome ? 3 : 10);
        if (outcome == 1) assert(wake_up_process((struct task_struct *)actor.model.storage));
        else if (outcome == 2) {
            __atomic_store_n(&actor.model.pending, 1ULL << 14, __ATOMIC_RELEASE);
            assert(vinix_linuxkpi_task_enqueue(&actor.model));
        }
        /* Removal belongs to successful enqueue, before the waiter resumes. */
        io_test_zero_counts();
        io_test_join(&actor);
        assert(actor.result == (outcome ? 7 : 0) && !vinix_linuxkpi_time_waiters());
    }
}

static void io_test_bits(void)
{
    unsigned long word = 0;
    for (unsigned int round = 0; round < 32; round++) {
        for (unsigned int operation = IO_TEST_BIT; operation <= IO_TEST_BIT_TIMEOUT; operation++) {
            for (unsigned int cancel = 0; cancel < 2; cancel++) {
                set_bit(3, &word);
                struct io_test_actor actor = { .word = &word, .timeout = 10 };
                io_test_start(&actor, operation, round % 4, TASK_INTERRUPTIBLE);
                io_test_parked(&actor);
                assert(nr_iowait() == 1 && nr_iowait_cpu(round % 4) == 1);
                if (cancel) {
                    __atomic_store_n(&actor.model.pending, 1ULL << 14, __ATOMIC_RELEASE);
                    assert(vinix_linuxkpi_task_enqueue(&actor.model));
                } else clear_and_wake_up_bit(3, &word);
                io_test_zero_counts();
                if (!cancel && operation == IO_TEST_BIT_LOCK) {
                    io_test_wait(&actor.returned, 1);
                    __atomic_store_n(&actor.release, 1, __ATOMIC_RELEASE);
                }
                io_test_join(&actor);
                assert(actor.result == (cancel ? -EINTR : 0));
                assert(!waitqueue_active(bit_waitqueue(&word, 3)) && !vinix_linuxkpi_time_waiters());
                clear_and_wake_up_bit(3, &word);
            }
        }
    }
    set_bit(3, &word);
    assert(out_of_line_wait_on_bit_timeout(&word, 3, bit_wait_io_timeout,
                                          TASK_UNINTERRUPTIBLE, 0) == -EAGAIN);
    clear_and_wake_up_bit(3, &word);
    assert(!wait_on_bit_io(&word, 3, TASK_UNINTERRUPTIBLE));
    assert(!wait_on_bit_lock_io(&word, 3, TASK_UNINTERRUPTIBLE));
    clear_and_wake_up_bit(3, &word);
    io_test_zero_counts();
    set_bit(3, &word);
    struct io_test_actor actor = { .word = &word, .timeout = 10 };
    io_test_start(&actor, IO_TEST_BIT_TIMEOUT, 3, TASK_UNINTERRUPTIBLE);
    io_test_parked(&actor);
    host_time_advance(3);
    assert(wake_up_process((struct task_struct *)actor.model.storage));
    /* The held bit causes a second I/O sleep, with the original absolute
     * boundary. A spurious wake neither extends it nor retains two slots. */
    io_test_count_wait(3, 1);
    assert(nr_iowait() == 1);
    host_time_advance(7);
    io_test_join(&actor);
    assert(actor.result == -EAGAIN && test_bit(3, &word));
    assert(!waitqueue_active(bit_waitqueue(&word, 3)) && !vinix_linuxkpi_time_waiters());
    clear_and_wake_up_bit(3, &word);
    io_test_zero_counts();
}

static void io_test_dying_dequeue(void)
{
    /* A terminal native queue removal owns the remaining slot, even though
     * no runnable enqueue occurs. Retain the stack model while observing it. */
    struct native_task_model *controller = native_task, dying;
    sync_model_init(&dying, 251);
    native_task = &dying;
    current_cpu = 1;
    int token = io_schedule_prepare();
    assert(!token);
    vinix_linuxkpi_task_dequeue(&dying);
    vinix_linuxkpi_iowait_block(&dying);
    assert(nr_iowait() == 1 && nr_iowait_cpu(1) == 1);
    __atomic_store_n(&dying.dead, true, __ATOMIC_RELEASE);
    vinix_linuxkpi_task_dead(dying.storage);
    assert(!vinix_linuxkpi_task_enqueue(&dying));
    assert(nr_iowait_cpu(1) == 1); /* Rejected enqueue cannot finish a slot. */
    vinix_linuxkpi_task_dequeue(&dying);
    io_test_zero_counts();
    io_schedule_finish(token);
    assert(!vinix_linuxkpi_task_in_iowait(dying.storage));
    native_task = controller;
    sync_model_destroy(&dying);
}

static void io_test_queue_edges(void)
{
    struct io_test_actor actor = {0};
    io_test_start(&actor, IO_TEST_NESTED, 2, TASK_UNINTERRUPTIBLE);
    io_test_parked(&actor);
    assert(nr_iowait_cpu(2) == 1);
    assert(!pthread_mutex_lock(&actor.model.queue_lock));
    actor.model.reject_enqueue = true;
    assert(!pthread_mutex_unlock(&actor.model.queue_lock));
    assert(!vinix_linuxkpi_task_enqueue(&actor.model));
    assert(nr_iowait_cpu(2) == 1 && !vinix_linuxkpi_task_queued(&actor.model));
    assert(!pthread_mutex_lock(&actor.model.queue_lock));
    actor.model.reject_enqueue = false;
    assert(!pthread_mutex_unlock(&actor.model.queue_lock));
    assert(wake_up_process((struct task_struct *)actor.model.storage));
    io_test_zero_counts();
    io_test_join(&actor);
    for (unsigned int round = 0; round < 64; round++) {
        actor = (struct io_test_actor){ .signal_before_block = true };
        io_test_start(&actor, IO_TEST_DIRECT, round % 4, TASK_INTERRUPTIBLE);
        io_test_join(&actor);
        assert(actor.before_block_calls == 1 && !actor.model.iowait_cpu_plus_one);
        io_test_zero_counts();
    }
}

static void io_tests(void)
{
    struct native_task_model controller;
    sync_model_init(&controller, 249);
    native_task = &controller;
    current_cpu = 0;
    size_t before = live_pages;
    assert(!fail_allocation);
    fail_allocation = true;
    io_test_tokens();
    io_test_cpu_counts();
    io_test_deadlines();
    io_test_bits();
    io_test_queue_edges();
    io_test_dying_dequeue();
    assert(live_pages == before && !vinix_linuxkpi_time_waiters());
    io_test_zero_counts();
    fail_allocation = false;
    native_task = NULL;
    sync_model_destroy(&controller);
}

#endif
