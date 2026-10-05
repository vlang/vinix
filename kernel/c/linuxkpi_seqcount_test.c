/* SPDX-License-Identifier: GPL-2.0-only */
#if defined(VINIX_LINUXKPI) && !defined(VINIX_LINUXKPI_HOST_TEST)
#include <linux/seqlock.h>
#include <linux/completion.h>
#include <linux/delay.h>
#include <linux/errno.h>
#include <vinix/runtime.h>
#include <pthread.h>

/* These probes use process-context readers. BH/NMI entrypoints and pointer
 * reclamation remain separate native services, not supplied by seqcounts. */
#define NATIVE_SEQ_EXPECT(condition) do { if (!(condition)) result = -EIO; } while (0)
static DEFINE_SEQLOCK(native_seq_static_lock);
static bool native_seq_irqs_enabled(void)
{
    return !!(vinix_linuxkpi_irq_flags() & (1UL << 9));
}

struct native_seq_pair { unsigned long value, inverse; };
static void native_seq_store(struct native_seq_pair *pair, unsigned long value)
{
    WRITE_ONCE(pair->value, value);
    WRITE_ONCE(pair->inverse, ~value);
}

static int native_seq_basic(void)
{
    int result = 0;
    seqcount_t plain = SEQCNT_ZERO(plain);
    NATIVE_SEQ_EXPECT(raw_read_seqcount(&plain) == 0);
    seqcount_init(&plain);
    unsigned int start = read_seqcount_begin(&plain);
    preempt_disable();
    write_seqcount_begin(&plain);
    NATIVE_SEQ_EXPECT(preempt_count() == 1 && (raw_read_seqcount(&plain) & 1));
    NATIVE_SEQ_EXPECT(read_seqcount_retry(&plain, start));
    NATIVE_SEQ_EXPECT(read_seqcount_retry(&plain, raw_seqcount_begin(&plain)));
    write_seqcount_end(&plain);
    NATIVE_SEQ_EXPECT(preempt_count() == 1 && read_seqcount_retry(&plain, start));
    start = __read_seqcount_begin(&plain);
    smp_rmb();
    NATIVE_SEQ_EXPECT(!__read_seqcount_retry(&plain, start));
    write_seqcount_invalidate(&plain);
    NATIVE_SEQ_EXPECT(raw_read_seqcount(&plain) == start + 2 && read_seqcount_retry(&plain, start));
    start = raw_read_seqcount_begin(&plain);
    raw_write_seqcount_barrier(&plain);
    NATIVE_SEQ_EXPECT(raw_read_seqcount(&plain) == start + 2 && read_seqcount_retry(&plain, start));
    WRITE_ONCE(plain.sequence, UINT_MAX - 1);
    raw_write_seqcount_begin(&plain);
    NATIVE_SEQ_EXPECT(raw_read_seqcount(&plain) == UINT_MAX);
    raw_write_seqcount_end(&plain);
    NATIVE_SEQ_EXPECT(raw_read_seqcount(&plain) == 0);
    preempt_enable();

    spinlock_t spin;
    spin_lock_init(&spin);
    seqcount_spinlock_t associated_spin;
    seqcount_spinlock_init(&associated_spin, &spin);
    unsigned long irq;
    spin_lock_irqsave(&spin, irq);
    write_seqcount_begin_nested(&associated_spin, 0);
    NATIVE_SEQ_EXPECT(!native_seq_irqs_enabled() && preempt_count() == 1);
    write_seqcount_end(&associated_spin);
    spin_unlock_irqrestore(&spin, irq);
    NATIVE_SEQ_EXPECT(native_seq_irqs_enabled() && !preempt_count());

    struct mutex mutex;
    mutex_init(&mutex);
    seqcount_mutex_t associated_mutex;
    seqcount_mutex_init(&associated_mutex, &mutex);
    mutex_lock(&mutex);
    preempt_disable();
    write_seqcount_begin(&associated_mutex);
    NATIVE_SEQ_EXPECT(native_seq_irqs_enabled() && preempt_count() == 2);
    write_seqcount_end(&associated_mutex);
    NATIVE_SEQ_EXPECT(preempt_count() == 1);
    preempt_enable();
    raw_write_seqcount_begin(&associated_mutex);
    NATIVE_SEQ_EXPECT(preempt_count() == 1);
    raw_write_seqcount_end(&associated_mutex);
    NATIVE_SEQ_EXPECT(!preempt_count());
    mutex_unlock(&mutex);
    mutex_destroy(&mutex);

    seqlock_init(&native_seq_static_lock);
    start = read_seqbegin(&native_seq_static_lock);
    write_seqlock_irqsave(&native_seq_static_lock, irq);
    NATIVE_SEQ_EXPECT(!native_seq_irqs_enabled() && preempt_count() == 1);
    write_sequnlock_irqrestore(&native_seq_static_lock, irq);
    NATIVE_SEQ_EXPECT(native_seq_irqs_enabled() && !preempt_count() && read_seqretry(&native_seq_static_lock, start));
    int exclusive = -1;
    read_seqbegin_or_lock(&native_seq_static_lock, &exclusive);
    NATIVE_SEQ_EXPECT(spin_is_locked(&native_seq_static_lock.lock) && preempt_count() == 1);
    NATIVE_SEQ_EXPECT(!need_seqretry(&native_seq_static_lock, exclusive));
    done_seqretry(&native_seq_static_lock, exclusive);
    NATIVE_SEQ_EXPECT(!spin_is_locked(&native_seq_static_lock.lock) && !preempt_count());
    unsigned long outer_irq = vinix_linuxkpi_irq_save();
    exclusive = -1;
    irq = read_seqbegin_or_lock_irqsave(&native_seq_static_lock, &exclusive);
    NATIVE_SEQ_EXPECT(!native_seq_irqs_enabled() && preempt_count() == 1);
    done_seqretry_irqrestore(&native_seq_static_lock, exclusive, irq);
    NATIVE_SEQ_EXPECT(!native_seq_irqs_enabled() && !preempt_count());
    vinix_linuxkpi_irq_restore(outer_irq);

    seqcount_latch_t latch = SEQCNT_LATCH_ZERO(latch);
    seqcount_latch_init(&latch);
    struct native_seq_pair copies[2];
    native_seq_store(&copies[0], 1); native_seq_store(&copies[1], 1);
    write_seqcount_latch_begin(&latch);
    NATIVE_SEQ_EXPECT(native_seq_irqs_enabled() && !preempt_count());
    start = read_seqcount_latch(&latch);
    NATIVE_SEQ_EXPECT((start & 1) && copies[start & 1].value == 1);
    native_seq_store(&copies[0], 2);
    NATIVE_SEQ_EXPECT(!read_seqcount_latch_retry(&latch, start));
    write_seqcount_latch(&latch);
    NATIVE_SEQ_EXPECT(read_seqcount_latch_retry(&latch, start));
    start = raw_read_seqcount_latch(&latch);
    NATIVE_SEQ_EXPECT(!(start & 1) && copies[start & 1].value == 2);
    native_seq_store(&copies[1], 2);
    write_seqcount_latch_end(&latch);
    NATIVE_SEQ_EXPECT(!raw_read_seqcount_latch_retry(&latch, start));
    NATIVE_SEQ_EXPECT(native_seq_irqs_enabled() && !preempt_count());
    return result;
}

struct native_seq_shared {
    spinlock_t spinlock;
    struct mutex mutex;
    seqcount_t plain;
    seqcount_spinlock_t spin;
    seqcount_mutex_t sleeping;
    seqlock_t seqlock;
    seqcount_latch_t latch;
    struct native_seq_pair values[4], copies[2];
};
struct native_seq_worker {
    struct native_seq_shared *shared;
    pthread_t thread;
    struct completion entered, go, done;
    unsigned int index, cpu, reads, cancel;
    int result;
    bool initialized, started;
};

static int native_seq_update(struct native_seq_shared *test, unsigned int kind)
{
    int result = 0;
    unsigned long irq = 0;
    if (kind < 2) spin_lock_irqsave(&test->spinlock, irq);
    else if (kind == 2 || kind == 4) mutex_lock(&test->mutex);
    else write_seqlock_irqsave(&test->seqlock, irq);
    if (kind == 0) write_seqcount_begin(&test->plain);
    else if (kind == 1) write_seqcount_begin(&test->spin);
    else if (kind == 2) write_seqcount_begin(&test->sleeping);
    if (kind < 4) {
        NATIVE_SEQ_EXPECT(preempt_count() == 1 && native_seq_irqs_enabled() == (kind == 2));
        unsigned long value = test->values[kind].value + 1;
        WRITE_ONCE(test->values[kind].value, value);
        cpu_relax();
        WRITE_ONCE(test->values[kind].inverse, ~value);
    } else {
        unsigned long value = test->copies[0].value + 1;
        write_seqcount_latch_begin(&test->latch);
        NATIVE_SEQ_EXPECT(native_seq_irqs_enabled() && !preempt_count());
        WRITE_ONCE(test->copies[0].value, value);
        cond_resched(); /* Latch readers use the untouched other copy. */
        WRITE_ONCE(test->copies[0].inverse, ~value);
        write_seqcount_latch(&test->latch);
        WRITE_ONCE(test->copies[1].value, value);
        cond_resched();
        WRITE_ONCE(test->copies[1].inverse, ~value);
        write_seqcount_latch_end(&test->latch);
    }
    if (kind == 0) write_seqcount_end(&test->plain);
    else if (kind == 1) write_seqcount_end(&test->spin);
    else if (kind == 2) write_seqcount_end(&test->sleeping);
    if (kind < 2) spin_unlock_irqrestore(&test->spinlock, irq);
    else if (kind == 2 || kind == 4) mutex_unlock(&test->mutex);
    else write_sequnlock_irqrestore(&test->seqlock, irq);
    NATIVE_SEQ_EXPECT(native_seq_irqs_enabled() && !preempt_count());
    return result;
}

static int native_seq_read(struct native_seq_shared *test, unsigned int kind)
{
    int result = 0;
    unsigned int start;
    unsigned long value, inverse;
    bool retry;
    do {
        if (kind == 0) start = read_seqcount_begin(&test->plain);
        else if (kind == 1) start = read_seqcount_begin(&test->spin);
        else if (kind == 2) start = read_seqcount_begin(&test->sleeping);
        else if (kind == 3) start = read_seqbegin(&test->seqlock);
        else start = read_seqcount_latch(&test->latch);
        struct native_seq_pair *pair = kind < 4 ? &test->values[kind] : &test->copies[start & 1];
        value = READ_ONCE(pair->value);
        cpu_relax();
        inverse = READ_ONCE(pair->inverse);
        if (kind == 0) retry = read_seqcount_retry(&test->plain, start);
        else if (kind == 1) retry = read_seqcount_retry(&test->spin, start);
        else if (kind == 2) retry = read_seqcount_retry(&test->sleeping, start);
        else if (kind == 3) retry = read_seqretry(&test->seqlock, start);
        else retry = read_seqcount_latch_retry(&test->latch, start);
    } while (retry);
    NATIVE_SEQ_EXPECT(inverse == ~value && native_seq_irqs_enabled() && !preempt_count());
    return result;
}

static void *native_seq_thread(void *argument)
{
    struct native_seq_worker *worker = argument;
    worker->result = vinix_linuxkpi_worker_bind(worker->cpu);
    complete(&worker->entered);
    wait_for_completion(&worker->go);
    for (unsigned int round = 0; !worker->result &&
        round < (worker->index < 2 ? 128U : 256U) &&
        !__atomic_load_n(&worker->cancel, __ATOMIC_ACQUIRE); round++) {
        for (unsigned int kind = 0; kind < 5; kind++) {
            int result;
            if (worker->index < 2) result = native_seq_update(worker->shared, kind);
            else { result = native_seq_read(worker->shared, kind); worker->reads++; }
            if (result) worker->result = result;
        }
        cond_resched();
        if (!(round % 16)) msleep(1);
        if (!native_seq_irqs_enabled() || preempt_count() ||
            vinix_linuxkpi_cpu_id() != worker->cpu) worker->result = -EIO;
    }
    complete(&worker->done);
    pthread_exit(NULL);
    return NULL;
}

int vinix_linuxkpi_seqcount_native_selftest(void)
{
    int result = native_seq_basic();
    if (result) return result;
    struct native_seq_shared test = {0};
    spin_lock_init(&test.spinlock); mutex_init(&test.mutex);
    seqcount_init(&test.plain); seqcount_spinlock_init(&test.spin, &test.spinlock);
    seqcount_mutex_init(&test.sleeping, &test.mutex); seqlock_init(&test.seqlock);
    seqcount_latch_init(&test.latch);
    for (unsigned int i = 0; i < ARRAY_SIZE(test.values); i++) native_seq_store(&test.values[i], 0);
    for (unsigned int i = 0; i < ARRAY_SIZE(test.copies); i++) native_seq_store(&test.copies[i], 0);
    struct native_seq_worker workers[4] = {0};
    unsigned int cpus = vinix_linuxkpi_percpu_count();
    if (!cpus || cpus > 64) { result = -EOPNOTSUPP; goto out; }
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++) {
        workers[i].shared = &test;
        workers[i].index = i;
        workers[i].cpu = i % cpus;
        init_completion(&workers[i].entered); init_completion(&workers[i].go);
        init_completion(&workers[i].done);
        workers[i].initialized = true;
        if (pthread_create(&workers[i].thread, NULL, native_seq_thread, &workers[i])) {
            result = -ENOMEM;
            goto out;
        }
        workers[i].started = true;
        if (!wait_for_completion_timeout(&workers[i].entered, 2000)) { result = -EIO; goto out; }
    }
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++) complete(&workers[i].go);
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++)
        if (!wait_for_completion_timeout(&workers[i].done, 2000)) { result = -EIO; goto out; }
out:
    /* Cancellation is sampled between complete writer transactions. No
     * controller waits or sleeps with an odd ordinary sequence counter. */
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++) {
        __atomic_store_n(&workers[i].cancel, 1, __ATOMIC_RELEASE);
        if (workers[i].initialized) complete_all(&workers[i].go);
    }
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++) {
        if (!workers[i].started) continue;
        BUG_ON(pthread_join(workers[i].thread, NULL));
        if (workers[i].result) result = -EIO;
        if (!result && i >= 2 && workers[i].reads != 5 * 256) result = -EIO;
    }
    if (!result) {
        for (unsigned int i = 0; i < ARRAY_SIZE(test.values); i++)
            NATIVE_SEQ_EXPECT(test.values[i].value == 256 && test.values[i].inverse == ~256UL);
        for (unsigned int i = 0; i < ARRAY_SIZE(test.copies); i++)
            NATIVE_SEQ_EXPECT(test.copies[i].value == 256 && test.copies[i].inverse == ~256UL);
    }
    mutex_destroy(&test.mutex);
    return result;
}
#endif
