/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_MUTEX_IO_TEST_H
#define VINIX_MUTEX_IO_TEST_H
/* Include after sync_test.h and io_test.h. These tests observe their existing
 * native queue model while all locking and intent changes use real APIs. */
#include <linux/mutex.h>
#include <linux/sched/stat.h>

enum mutex_io_operation { MUTEX_IO_DIRECT, MUTEX_IO_NESTED,
    MUTEX_IO_ORDINARY, MUTEX_IO_INTERRUPTIBLE_SCOPE };
struct mutex_io_actor {
    struct native_task_model model;
    struct mutex *lock;
    pthread_t thread;
    enum mutex_io_operation operation;
    unsigned int cpu, entered, acquired, release, done, block_calls;
    int result;
    bool prior_intent;
};
static _Thread_local struct mutex_io_actor *mutex_io_current;

static void mutex_io_before_block(struct native_task_model *task)
{
    assert(mutex_io_current && task == &mutex_io_current->model);
    __atomic_fetch_add(&mutex_io_current->block_calls, 1, __ATOMIC_RELEASE);
    /* Reinstall the observation for a later genuine schedule retry. The
     * accounting hook itself still decides whether this task is off-queue. */
    host_iowait_before_block = mutex_io_before_block;
}

static void *mutex_io_thread(void *argument)
{
    struct mutex_io_actor *actor = argument;
    native_task = &actor->model;
    current_cpu = actor->cpu;
    mutex_io_current = actor;
    int outer = actor->prior_intent ? io_schedule_prepare() : -1;
    if (outer >= 0) assert(!outer);
    if (actor->operation != MUTEX_IO_ORDINARY)
        host_iowait_before_block = mutex_io_before_block;
    __atomic_store_n(&actor->entered, 1, __ATOMIC_RELEASE);
    if (actor->operation == MUTEX_IO_DIRECT) mutex_lock_io(actor->lock);
    else if (actor->operation == MUTEX_IO_NESTED) mutex_lock_io_nested(actor->lock, 1);
    else if (actor->operation == MUTEX_IO_ORDINARY) mutex_lock(actor->lock);
    else {
        /* There is no interruptible mutex_lock_io API. An independent caller
         * may prepare an I/O scope around the existing interruptible API;
         * cancellation must remove its stack waiter and restore that scope. */
        int token = io_schedule_prepare();
        actor->result = mutex_lock_interruptible(actor->lock);
        io_schedule_finish(token);
    }
    host_iowait_before_block = NULL;
    assert(!!vinix_linuxkpi_task_in_iowait(actor->model.storage) == actor->prior_intent);
    assert(!actor->model.iowait_cpu_plus_one && task_is_running(current));
    assert(interrupts && !preempt_depth);
    if (!actor->result) {
        assert(atomic_long_read(&actor->lock->owner) == (long)current);
        __atomic_store_n(&actor->acquired, 1, __ATOMIC_RELEASE);
        /* This host yield leaves the native task RUNNING. Prior I/O intent
         * therefore remains visible without creating another blocked slot. */
        io_test_wait(&actor->release, 1);
        mutex_unlock(actor->lock);
    }
    if (outer >= 0) io_schedule_finish(outer);
    assert(!vinix_linuxkpi_task_in_iowait(actor->model.storage));
    __atomic_store_n(&actor->model.pending, 0, __ATOMIC_RELEASE);
    __atomic_store_n(&actor->done, 1, __ATOMIC_RELEASE);
    mutex_io_current = NULL;
    native_task = NULL;
    return NULL;
}

static void mutex_io_start(struct mutex_io_actor *actor, struct mutex *lock,
                          enum mutex_io_operation operation, unsigned int cpu, bool prior)
{
    *actor = (struct mutex_io_actor){ .lock = lock, .operation = operation,
                                   .cpu = cpu, .prior_intent = prior };
    sync_model_init(&actor->model, 280 + cpu);
    actor->model.iteration = 1;
    assert(!pthread_create(&actor->thread, NULL, mutex_io_thread, actor));
    io_test_wait(&actor->entered, 1);
    io_test_wait(&actor->model.parked, 1);
    assert(!vinix_linuxkpi_task_queued(&actor->model));
    assert(actor->model.iowait_cpu_plus_one == (operation == MUTEX_IO_ORDINARY ? 0 : cpu + 1));
}

static void mutex_io_join(struct mutex_io_actor *actor)
{
    io_test_wait(&actor->done, 1);
    assert(!pthread_join(actor->thread, NULL));
    assert(!actor->model.iowait_cpu_plus_one);
    sync_model_destroy(&actor->model);
}

static struct mutex *mutex_io_lock_argument(struct mutex *lock, unsigned int *calls)
{
    (*calls)++;
    return lock;
}

static void mutex_io_fast(void)
{
    struct mutex lock;
    mutex_init(&lock);
    unsigned int calls = 0, subclass = 0;
    u64 irq = vinix_linuxkpi_irq_flags();
    unsigned int depth = vinix_linuxkpi_preempt_count();
    for (unsigned int round = 0; round < 128; round++) {
        mutex_lock_io(mutex_io_lock_argument(&lock, &calls));
        assert(atomic_long_read(&lock.owner) == (long)current);
        assert(!vinix_linuxkpi_task_in_iowait(native_task->storage));
        assert(!native_task->dequeued && !native_task->iowait_cpu_plus_one);
        io_test_zero_counts();
        mutex_unlock(&lock);
        int outer = io_schedule_prepare();
        assert(!outer);
        /* CONFIG_DEBUG_LOCK_ALLOC=n discards the annotation expression, as
         * in the pinned public header, but evaluates the lock exactly once. */
        mutex_lock_io_nested(mutex_io_lock_argument(&lock, &calls), subclass++);
        assert(vinix_linuxkpi_task_in_iowait(native_task->storage));
        assert(!native_task->dequeued && !native_task->iowait_cpu_plus_one);
        io_test_zero_counts();
        mutex_unlock(&lock);
        assert(vinix_linuxkpi_task_in_iowait(native_task->storage));
        io_schedule_finish(outer);
        assert(!vinix_linuxkpi_task_in_iowait(native_task->storage));
    }
    assert(calls == 256 && !subclass);
    assert(irq == vinix_linuxkpi_irq_flags() && depth == vinix_linuxkpi_preempt_count());
    assert(!mutex_waiters(&lock));
    mutex_destroy(&lock);
}

static void mutex_io_fifo_and_cancel(void)
{
    struct mutex lock;
    mutex_init(&lock);
    mutex_lock(&lock);
    struct mutex_io_actor actors[4];
    const unsigned int cpus[] = {1, 2, 3, 1};
    const enum mutex_io_operation operations[] = {MUTEX_IO_DIRECT,
        MUTEX_IO_INTERRUPTIBLE_SCOPE, MUTEX_IO_ORDINARY, MUTEX_IO_NESTED};
    for (unsigned int i = 0; i < ARRAY_SIZE(actors); i++) {
        mutex_io_start(&actors[i], &lock, operations[i], cpus[i], i < 2);
        assert(mutex_waiters(&lock) == i + 1);
    }
    assert(nr_iowait() == 3 && nr_iowait_cpu(1) == 2 && nr_iowait_cpu(2) == 1);
    assert(!nr_iowait_cpu(0) && !nr_iowait_cpu(3));
    __atomic_store_n(&actors[1].model.pending, 1ULL << 14, __ATOMIC_RELEASE);
    assert(vinix_linuxkpi_task_enqueue(&actors[1].model));
    mutex_io_join(&actors[1]);
    assert(actors[1].result == -EINTR && !__atomic_load_n(&actors[1].acquired, __ATOMIC_ACQUIRE));
    assert(mutex_waiters(&lock) == 3 && nr_iowait() == 2 && !nr_iowait_cpu(2));
    /* Neither ordinary nor fatal signals cancel the uninterruptible public
     * I/O mutex API. Each real wake/repark must retire and restart one slot. */
    for (unsigned int round = 0; round < 2; round++) {
        __atomic_store_n(&actors[3].model.pending, 1ULL << (round ? 8 : 14), __ATOMIC_RELEASE);
        assert(vinix_linuxkpi_task_enqueue(&actors[3].model));
        io_test_wait(&actors[3].block_calls, round + 2);
        io_test_count_wait(1, 2);
        assert(!vinix_linuxkpi_task_queued(&actors[3].model));
        assert(mutex_waiters(&lock) == 3 &&
               !__atomic_load_n(&actors[3].acquired, __ATOMIC_ACQUIRE) && nr_iowait() == 2);
    }
    current_cpu = 0; /* Wakes on CPU 0 retire the sleepers' CPU 1 slots. */
    mutex_unlock(&lock);
    const unsigned int order[] = {0, 2, 3};
    for (unsigned int slot = 0; slot < ARRAY_SIZE(order); slot++) {
        unsigned int index = order[slot];
        io_test_wait(&actors[index].acquired, 1);
        assert(atomic_long_read(&lock.owner) == (long)actors[index].model.storage);
        assert(!mutex_trylock(&lock));
        assert(nr_iowait() == (slot < 2 ? 1 : 0));
        assert(nr_iowait_cpu(1) == (slot < 2 ? 1 : 0));
        if (slot + 1 < ARRAY_SIZE(order))
            assert(!__atomic_load_n(&actors[order[slot + 1]].acquired, __ATOMIC_ACQUIRE));
        __atomic_store_n(&actors[index].release, 1, __ATOMIC_RELEASE);
        mutex_io_join(&actors[index]);
        assert(!actors[index].result);
    }
    assert(!mutex_is_locked(&lock) && !mutex_waiters(&lock));
    io_test_zero_counts();
    mutex_destroy(&lock);
}

static void mutex_io_handoff_wins_signal(void)
{
    struct mutex lock;
    mutex_init(&lock);
    mutex_lock(&lock);
    struct mutex_io_actor actor;
    mutex_io_start(&actor, &lock, MUTEX_IO_INTERRUPTIBLE_SCOPE, 3, true);
    assert(nr_iowait_cpu(3) == 1);
    /* Publish the signal without enqueuing: the direct ownership handoff is
     * the first accepted wake. Acquired ownership wins that pending signal. */
    __atomic_store_n(&actor.model.pending, 1ULL << 14, __ATOMIC_RELEASE);
    mutex_unlock(&lock);
    io_test_wait(&actor.acquired, 1);
    io_test_zero_counts();
    __atomic_store_n(&actor.release, 1, __ATOMIC_RELEASE);
    mutex_io_join(&actor);
    assert(!actor.result && !mutex_waiters(&lock));
    mutex_destroy(&lock);
}

static void mutex_io_tests(void)
{
    struct native_task_model controller;
    sync_model_init(&controller, 279);
    native_task = &controller;
    current_cpu = 0;
    size_t before = live_pages;
    assert(!fail_allocation);
    fail_allocation = true;
    mutex_io_fast();
    for (unsigned int round = 0; round < 16; round++) {
        mutex_io_fifo_and_cancel();
        mutex_io_handoff_wins_signal();
    }
    io_test_zero_counts();
    assert(live_pages == before && !controller.iowait_cpu_plus_one);
    fail_allocation = false;
    native_task = NULL;
    sync_model_destroy(&controller);
}
#endif
