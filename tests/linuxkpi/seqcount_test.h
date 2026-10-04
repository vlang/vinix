/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_SEQCOUNT_TEST_H
#define VINIX_LINUXKPI_SEQCOUNT_TEST_H
#include <linux/seqlock.h>

static DEFINE_SEQLOCK(seqcount_static_lock);

struct seqcount_test_pair { unsigned long value, inverse; };
static void seqcount_test_store(struct seqcount_test_pair *pair, unsigned long value)
{
    WRITE_ONCE(pair->value, value);
    WRITE_ONCE(pair->inverse, ~value);
}

static void seqcount_test_basic(void)
{
    seqcount_t plain = SEQCNT_ZERO(plain);
    assert(raw_read_seqcount(&plain) == 0);
    seqcount_init(&plain);
    unsigned int start = read_seqcount_begin(&plain);
    preempt_disable();
    write_seqcount_begin(&plain);
    assert(preempt_count() == 1 && (raw_read_seqcount(&plain) & 1));
    assert(read_seqcount_retry(&plain, start));
    assert(read_seqcount_retry(&plain, raw_seqcount_begin(&plain)));
    write_seqcount_end(&plain);
    assert(preempt_count() == 1 && read_seqcount_retry(&plain, start));
    start = __read_seqcount_begin(&plain);
    smp_rmb();
    assert(!__read_seqcount_retry(&plain, start));
    write_seqcount_invalidate(&plain);
    assert(raw_read_seqcount(&plain) == start + 2 && read_seqcount_retry(&plain, start));
    start = raw_read_seqcount_begin(&plain);
    raw_write_seqcount_barrier(&plain);
    assert(raw_read_seqcount(&plain) == start + 2 && read_seqcount_retry(&plain, start));
    WRITE_ONCE(plain.sequence, UINT_MAX - 1);
    raw_write_seqcount_begin(&plain);
    assert(raw_read_seqcount(&plain) == UINT_MAX);
    raw_write_seqcount_end(&plain);
    assert(raw_read_seqcount(&plain) == 0);
    preempt_enable();

    spinlock_t spin;
    spin_lock_init(&spin);
    seqcount_spinlock_t associated_spin;
    seqcount_spinlock_init(&associated_spin, &spin);
    unsigned long irq;
    spin_lock_irqsave(&spin, irq);
    write_seqcount_begin_nested(&associated_spin, 0);
    assert(!interrupts && preempt_count() == 1);
    write_seqcount_end(&associated_spin);
    spin_unlock_irqrestore(&spin, irq);
    assert(interrupts && !preempt_count());

    struct mutex mutex;
    mutex_init(&mutex);
    seqcount_mutex_t associated_mutex;
    seqcount_mutex_init(&associated_mutex, &mutex);
    mutex_lock(&mutex);
    preempt_disable();
    write_seqcount_begin(&associated_mutex);
    assert(interrupts && preempt_count() == 2);
    write_seqcount_end(&associated_mutex);
    assert(preempt_count() == 1);
    preempt_enable();
    raw_write_seqcount_begin(&associated_mutex);
    assert(preempt_count() == 1);
    raw_write_seqcount_end(&associated_mutex);
    assert(!preempt_count());
    mutex_unlock(&mutex);
    mutex_destroy(&mutex);

    seqlock_init(&seqcount_static_lock);
    start = read_seqbegin(&seqcount_static_lock);
    write_seqlock_irqsave(&seqcount_static_lock, irq);
    assert(!interrupts && preempt_count() == 1);
    write_sequnlock_irqrestore(&seqcount_static_lock, irq);
    assert(interrupts && !preempt_count() && read_seqretry(&seqcount_static_lock, start));
    int exclusive = -1;
    read_seqbegin_or_lock(&seqcount_static_lock, &exclusive);
    assert(spin_is_locked(&seqcount_static_lock.lock) && preempt_count() == 1);
    assert(!need_seqretry(&seqcount_static_lock, exclusive));
    done_seqretry(&seqcount_static_lock, exclusive);
    assert(!spin_is_locked(&seqcount_static_lock.lock) && !preempt_count());
    unsigned long outer_irq = vinix_linuxkpi_irq_save();
    exclusive = -1;
    irq = read_seqbegin_or_lock_irqsave(&seqcount_static_lock, &exclusive);
    assert(!interrupts && preempt_count() == 1);
    done_seqretry_irqrestore(&seqcount_static_lock, exclusive, irq);
    assert(!interrupts && !preempt_count());
    vinix_linuxkpi_irq_restore(outer_irq);

    seqcount_latch_t latch = SEQCNT_LATCH_ZERO(latch);
    seqcount_latch_init(&latch);
    struct seqcount_test_pair copies[2];
    seqcount_test_store(&copies[0], 1); seqcount_test_store(&copies[1], 1);
    write_seqcount_latch_begin(&latch);
    assert(interrupts && !preempt_count());
    start = read_seqcount_latch(&latch);
    assert((start & 1) && copies[start & 1].value == 1);
    seqcount_test_store(&copies[0], 2);
    assert(!read_seqcount_latch_retry(&latch, start));
    write_seqcount_latch(&latch);
    assert(read_seqcount_latch_retry(&latch, start));
    start = raw_read_seqcount_latch(&latch);
    assert(!(start & 1) && copies[start & 1].value == 2);
    seqcount_test_store(&copies[1], 2);
    write_seqcount_latch_end(&latch);
    assert(!raw_read_seqcount_latch_retry(&latch, start));
    assert(interrupts && !preempt_count());
}

struct seqcount_test_shared {
    spinlock_t spinlock;
    struct mutex mutex;
    seqcount_t plain;
    seqcount_spinlock_t spin;
    seqcount_mutex_t sleeping;
    seqlock_t seqlock;
    seqcount_latch_t latch;
    struct seqcount_test_pair values[4], copies[2];
    unsigned int ready, go;
};
struct seqcount_test_worker {
    struct native_task_model model;
    struct seqcount_test_shared *shared;
    unsigned int index, reads;
};

static void seqcount_test_update(struct seqcount_test_shared *test, unsigned int kind)
{
    unsigned long irq = 0;
    if (kind < 2) spin_lock_irqsave(&test->spinlock, irq);
    else if (kind == 2 || kind == 4) mutex_lock(&test->mutex);
    else write_seqlock_irqsave(&test->seqlock, irq);
    if (kind == 0) write_seqcount_begin(&test->plain);
    else if (kind == 1) write_seqcount_begin(&test->spin);
    else if (kind == 2) write_seqcount_begin(&test->sleeping);
    if (kind < 4) {
        assert(preempt_count() == 1 && interrupts == (kind == 2));
        unsigned long value = test->values[kind].value + 1;
        WRITE_ONCE(test->values[kind].value, value);
        cpu_relax();
        WRITE_ONCE(test->values[kind].inverse, ~value);
    } else {
        unsigned long value = test->copies[0].value + 1;
        write_seqcount_latch_begin(&test->latch);
        assert(interrupts && !preempt_count());
        WRITE_ONCE(test->copies[0].value, value);
        sched_yield(); /* Latch readers use the untouched other copy. */
        WRITE_ONCE(test->copies[0].inverse, ~value);
        write_seqcount_latch(&test->latch);
        WRITE_ONCE(test->copies[1].value, value);
        sched_yield();
        WRITE_ONCE(test->copies[1].inverse, ~value);
        write_seqcount_latch_end(&test->latch);
    }
    if (kind == 0) write_seqcount_end(&test->plain);
    else if (kind == 1) write_seqcount_end(&test->spin);
    else if (kind == 2) write_seqcount_end(&test->sleeping);
    if (kind < 2) spin_unlock_irqrestore(&test->spinlock, irq);
    else if (kind == 2 || kind == 4) mutex_unlock(&test->mutex);
    else write_sequnlock_irqrestore(&test->seqlock, irq);
    assert(interrupts && !preempt_count());
}

static void seqcount_test_read(struct seqcount_test_shared *test, unsigned int kind)
{
    unsigned int start;
    unsigned long value, inverse;
    bool retry;
    do {
        if (kind == 0) start = read_seqcount_begin(&test->plain);
        else if (kind == 1) start = read_seqcount_begin(&test->spin);
        else if (kind == 2) start = read_seqcount_begin(&test->sleeping);
        else if (kind == 3) start = read_seqbegin(&test->seqlock);
        else start = read_seqcount_latch(&test->latch);
        struct seqcount_test_pair *pair = kind < 4 ? &test->values[kind] : &test->copies[start & 1];
        value = READ_ONCE(pair->value);
        cpu_relax();
        inverse = READ_ONCE(pair->inverse);
        if (kind == 0) retry = read_seqcount_retry(&test->plain, start);
        else if (kind == 1) retry = read_seqcount_retry(&test->spin, start);
        else if (kind == 2) retry = read_seqcount_retry(&test->sleeping, start);
        else if (kind == 3) retry = read_seqretry(&test->seqlock, start);
        else retry = read_seqcount_latch_retry(&test->latch, start);
    } while (retry);
    assert(inverse == ~value && interrupts && !preempt_count());
}

static void *seqcount_test_thread(void *argument)
{
    struct seqcount_test_worker *worker = argument;
    native_task = &worker->model;
    current_cpu = worker->index;
    __atomic_add_fetch(&worker->shared->ready, 1, __ATOMIC_RELEASE);
    while (!__atomic_load_n(&worker->shared->go, __ATOMIC_ACQUIRE)) sched_yield();
    for (unsigned int round = 0; round < (worker->index < 2 ? 128U : 256U); round++) {
        for (unsigned int kind = 0; kind < 5; kind++) {
            if (worker->index < 2) seqcount_test_update(worker->shared, kind);
            else { seqcount_test_read(worker->shared, kind); worker->reads++; }
        }
        sched_yield();
    }
    assert(interrupts && !preempt_count() && task_is_running(current));
    native_task = NULL;
    return NULL;
}

static void seqcount_tests(void)
{
    size_t before = live_pages;
    unsigned int saved_cpu = current_cpu;
    struct native_task_model controller;
    sync_model_init(&controller, 269);
    native_task = &controller;
    seqcount_test_basic();
    struct seqcount_test_shared test = {0};
    spin_lock_init(&test.spinlock); mutex_init(&test.mutex);
    seqcount_init(&test.plain); seqcount_spinlock_init(&test.spin, &test.spinlock);
    seqcount_mutex_init(&test.sleeping, &test.mutex); seqlock_init(&test.seqlock);
    seqcount_latch_init(&test.latch);
    for (unsigned int i = 0; i < ARRAY_SIZE(test.values); i++) seqcount_test_store(&test.values[i], 0);
    for (unsigned int i = 0; i < ARRAY_SIZE(test.copies); i++) seqcount_test_store(&test.copies[i], 0);
    struct seqcount_test_worker workers[4];
    pthread_t threads[4];
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++) {
        workers[i] = (struct seqcount_test_worker){ .shared = &test, .index = i };
        sync_model_init(&workers[i].model, 270 + i);
        assert(!pthread_create(&threads[i], NULL, seqcount_test_thread, &workers[i]));
    }
    for (unsigned int spin = 0; __atomic_load_n(&test.ready, __ATOMIC_ACQUIRE) != 4; spin++) {
        assert(spin < 1000000); sched_yield();
    }
    __atomic_store_n(&test.go, 1, __ATOMIC_RELEASE);
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++) {
        assert(!pthread_join(threads[i], NULL));
        if (i >= 2) assert(workers[i].reads == 5 * 256);
        sync_model_destroy(&workers[i].model);
    }
    for (unsigned int i = 0; i < ARRAY_SIZE(test.values); i++)
        assert(test.values[i].value == 256 && test.values[i].inverse == ~256UL);
    for (unsigned int i = 0; i < ARRAY_SIZE(test.copies); i++)
        assert(test.copies[i].value == 256 && test.copies[i].inverse == ~256UL);
    mutex_destroy(&test.mutex);
    native_task = NULL;
    current_cpu = saved_cpu;
    sync_model_destroy(&controller);
    assert(live_pages == before && interrupts && !preempt_count());
}
#endif
