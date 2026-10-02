/* SPDX-License-Identifier: GPL-2.0-only */
#if defined(VINIX_LINUXKPI) && !defined(VINIX_LINUXKPI_HOST_TEST)
#include <linux/init.h>
#include <linux/bitops.h>
#include <linux/sched.h>
#include <linux/sched/task.h>
#include <linux/wait_bit.h>
#include <linux/completion.h>
#include <linux/delay.h>
#include <linux/errno.h>
#include <linux/jiffies.h>
#include <linux/slab.h>
#include <vinix/runtime.h>
#include <pthread.h>

void vinix_linuxkpi_test_task_signal(void *thread, u64 pending);

enum native_bit_operation { NATIVE_BIT_CLEAR, NATIVE_BIT_LOCK, NATIVE_BIT_SET,
                            NATIVE_VAR_WAIT, NATIVE_VAR_KILLABLE };
struct native_bit_thread {
    struct task_struct *task;
    pthread_t thread;
    struct completion entered, acquired, release, done;
    unsigned long *word;
    void *var;
    unsigned int *ready, *payload;
    int bit, value, result;
    unsigned int state;
    enum native_bit_operation operation;
    bool initialized, started;
};

static void *native_bit_thread(void *argument)
{
    struct native_bit_thread *test = argument;
    test->task = get_task_struct(current);
    complete(&test->entered);
    if (test->operation == NATIVE_BIT_CLEAR)
        test->value = wait_on_bit(test->word, test->bit, test->state);
    else if (test->operation == NATIVE_BIT_LOCK) {
        test->value = wait_on_bit_lock(test->word, test->bit, test->state);
        if (!test->value) {
            if (!test_bit(test->bit, test->word)) test->result = -EIO;
            complete(&test->acquired);
            wait_for_completion(&test->release);
            clear_and_wake_up_bit(test->bit, test->word);
        }
    } else if (test->operation == NATIVE_BIT_SET) {
        DEFINE_WAIT(wait);
        struct wait_queue_head *queue = bit_waitqueue(test->word, test->bit);
        for (;;) {
            prepare_to_wait(queue, &wait, TASK_UNINTERRUPTIBLE);
            if (test_bit_acquire(test->bit, test->word)) break;
            schedule();
        }
        finish_wait(queue, &wait);
    } else if (test->operation == NATIVE_VAR_KILLABLE)
        test->value = wait_var_event_killable(test->var, READ_ONCE(*test->ready));
    else wait_var_event(test->var, READ_ONCE(*test->ready));
    if (!test->value && test->payload && READ_ONCE(*test->payload) != 42) test->result = -EIO;
    vinix_linuxkpi_test_task_signal(test->task->vinix_thread, 0);
    if (!task_is_running(current) || !vinix_linuxkpi_may_sleep()) test->result = -EIO;
    complete(&test->done);
    pthread_exit(NULL);
    return NULL;
}

static int native_bit_start(struct native_bit_thread *test, enum native_bit_operation operation,
                             unsigned long *word, int bit, unsigned int state,
                             void *var, unsigned int *ready, unsigned int *payload)
{
    *test = (struct native_bit_thread){ .operation = operation, .word = word, .bit = bit,
        .state = state, .var = var, .ready = ready, .payload = payload };
    init_completion(&test->entered);
    init_completion(&test->acquired);
    init_completion(&test->release);
    init_completion(&test->done);
    test->initialized = true;
    if (pthread_create(&test->thread, NULL, native_bit_thread, test)) return -ENOMEM;
    test->started = true;
    return wait_for_completion_timeout(&test->entered, 500) ? 0 : -EIO;
}

static int native_bit_parked(struct native_bit_thread *test)
{
    unsigned long deadline = jiffies + 500;
    while (__atomic_load_n(&test->task->__state, __ATOMIC_ACQUIRE) != test->state ||
           vinix_linuxkpi_task_queued(test->task->vinix_thread)) {
        if (time_after_eq(jiffies, deadline)) return -EIO;
        msleep(1);
    }
    return 0;
}

static int native_bit_join(struct native_bit_thread *test)
{
    if (!test->started) return 0;
    BUG_ON(pthread_join(test->thread, NULL));
    int result = test->result;
    while (__atomic_load_n(&test->task->__state, __ATOMIC_ACQUIRE) != TASK_DEAD) cond_resched();
    put_task_struct(test->task);
    test->started = false;
    return result;
}

static unsigned int native_bit_collision(unsigned long *words, unsigned int excluded)
{
    struct wait_queue_head *queue = bit_waitqueue(words, 0);
    for (unsigned int i = 16; i < 1024; i++)
        if (i != excluded && bit_waitqueue(&words[i], 0) == queue) return i;
    return 0;
}

static int native_bit_keyed(void)
{
    unsigned long words[1024] = {0};
    struct native_bit_thread tests[3] = {0};
    unsigned int payload = 0, collision;
    int wrong_bit = 0, result = 0;
    /* A multiword bit index retains its exact base address and bit key. */
    for (int bit = BITS_PER_LONG; bit < 1024 * BITS_PER_LONG; bit++)
        if (bit_waitqueue(words, bit) == bit_waitqueue(words, 0)) { wrong_bit = bit; break; }
    if (!wrong_bit) return -EIO;
    collision = native_bit_collision(words, wrong_bit / BITS_PER_LONG);
    if (!collision) return -EIO;
    set_bit(0, words);
    set_bit(wrong_bit, words);
    set_bit(0, &words[collision]);
    if (native_bit_start(&tests[0], NATIVE_BIT_CLEAR, words, 0, TASK_UNINTERRUPTIBLE, NULL, NULL, &payload) ||
        native_bit_start(&tests[1], NATIVE_BIT_CLEAR, words, wrong_bit, TASK_UNINTERRUPTIBLE, NULL, NULL, &payload) ||
        native_bit_start(&tests[2], NATIVE_BIT_CLEAR, &words[collision], 0, TASK_UNINTERRUPTIBLE, NULL, NULL, &payload))
        { result = -EIO; goto out; }
    for (unsigned int i = 0; i < ARRAY_SIZE(tests); i++)
        if (native_bit_parked(&tests[i])) { result = -EIO; goto out; }
    WRITE_ONCE(payload, 42);
    vinix_linuxkpi_test_alloc_oom(0);
    unsigned long flags = vinix_linuxkpi_irq_save();
    clear_and_wake_up_bit(0, words);
    vinix_linuxkpi_irq_restore(flags);
    /* An IRQ-off producer must not consume the caller's next allocation. */
    void *unexpected = kmalloc(1, GFP_KERNEL);
    vinix_linuxkpi_test_alloc_oom(-1);
    if (unexpected) { kfree(unexpected); result = -EIO; }
    if (!wait_for_completion_timeout(&tests[0].done, 500) ||
        completion_done(&tests[1].done) || completion_done(&tests[2].done) ||
        !test_bit(wrong_bit, words) || !test_bit(0, &words[collision])) result = -EIO;
out:
    WRITE_ONCE(payload, 42);
    clear_and_wake_up_bit(0, words);
    clear_and_wake_up_bit(wrong_bit, words);
    clear_and_wake_up_bit(0, &words[collision]);
    for (unsigned int i = 0; i < ARRAY_SIZE(tests); i++)
        if (native_bit_join(&tests[i])) result = -EIO;
    if (waitqueue_active(bit_waitqueue(words, 0))) result = -EIO;
    return result;
}

static int native_bit_quota(void)
{
    unsigned long words[1024] = {0};
    struct native_bit_thread tests[3] = {0};
    unsigned int payload = 42, collision = native_bit_collision(words, 0);
    int result = 0;
    if (!collision) return -EIO;
    set_bit(0, words);
    set_bit(0, &words[collision]);
    /* Queue a mismatched exclusive waiter before the matching lockers. */
    for (unsigned int i = 0; i < ARRAY_SIZE(tests); i++) {
        if (native_bit_start(&tests[i], NATIVE_BIT_LOCK, i ? words : &words[collision], 0,
                             TASK_UNINTERRUPTIBLE, NULL, NULL, &payload) || native_bit_parked(&tests[i]))
            { result = -EIO; goto out; }
    }
    clear_and_wake_up_bit(0, words);
    unsigned long deadline = jiffies + 500;
    while (!completion_done(&tests[1].acquired) && !completion_done(&tests[2].acquired)) {
        if (time_after_eq(jiffies, deadline)) { result = -EIO; goto out; }
        msleep(1);
    }
    unsigned int first = completion_done(&tests[1].acquired) ? 1 : 2;
    unsigned int second = first == 1 ? 2 : 1;
    if (completion_done(&tests[0].acquired) || completion_done(&tests[second].acquired) ||
        !test_bit(0, words) || native_bit_parked(&tests[second])) result = -EIO;
    complete(&tests[first].release);
    if (!wait_for_completion_timeout(&tests[second].acquired, 500)) result = -EIO;
out:
    for (unsigned int i = 0; i < ARRAY_SIZE(tests); i++)
        if (tests[i].initialized) complete_all(&tests[i].release);
    clear_and_wake_up_bit(0, words);
    clear_and_wake_up_bit(0, &words[collision]);
    for (unsigned int i = 0; i < ARRAY_SIZE(tests); i++)
        if (native_bit_join(&tests[i])) result = -EIO;
    if (waitqueue_active(bit_waitqueue(words, 0))) result = -EIO;
    return result;
}

static int native_bit_display(void)
{
    unsigned long word = 0;
    unsigned int payload = 0;
    struct native_bit_thread test = {0};
    int result = native_bit_start(&test, NATIVE_BIT_SET, &word, 0,
                                  TASK_UNINTERRUPTIBLE, NULL, NULL, &payload);
    if (!result && native_bit_parked(&test)) result = -EIO;
    WRITE_ONCE(payload, 42);
    set_bit(0, &word);
    smp_mb__after_atomic();
    /* The display reset waiter is ordinary: it waits for a SET bit. */
    wake_up_bit(&word, 0);
    if (!wait_for_completion_timeout(&test.done, 500)) result = -EIO;
    if (native_bit_join(&test) || waitqueue_active(bit_waitqueue(&word, 0))) result = -EIO;
    return result;
}

static int native_bit_interrupt(void)
{
    unsigned long word = 1;
    struct native_bit_thread test = {0};
    int result = native_bit_start(&test, NATIVE_BIT_CLEAR, &word, 0,
                                  TASK_INTERRUPTIBLE, NULL, NULL, NULL);
    if (!result) {
        if (native_bit_parked(&test)) result = -EIO;
        vinix_linuxkpi_test_task_signal(test.task->vinix_thread, 1ULL << 14);
        if (!wait_for_completion_timeout(&test.done, 500) || test.value != -EINTR ||
            !test_bit(0, &word)) result = -EIO;
    }
    clear_and_wake_up_bit(0, &word);
    if (native_bit_join(&test) || waitqueue_active(bit_waitqueue(&word, 0))) result = -EIO;
    return result;
}

static int native_var_test(bool killable, bool inaccessible)
{
    unsigned int ready = 0, payload = 0;
    struct native_bit_thread test = {0};
    void *address = inaccessible ? (void *)1 : kmalloc(64, GFP_KERNEL);
    bool allocated = !inaccessible && address;
    if (!address) return -ENOMEM;
    int result = native_bit_start(&test, killable ? NATIVE_VAR_KILLABLE : NATIVE_VAR_WAIT,
                                  NULL, 0, killable ? TASK_KILLABLE : TASK_UNINTERRUPTIBLE,
                                  address, &ready, &payload);
    if (result) goto out;
    if (native_bit_parked(&test)) { result = -EIO; goto out; }
    if (killable) {
        vinix_linuxkpi_test_task_signal(test.task->vinix_thread, 1ULL << 14);
        if (native_bit_parked(&test) || completion_done(&test.done)) result = -EIO;
        vinix_linuxkpi_test_task_signal(test.task->vinix_thread, 1ULL << 8);
        if (!wait_for_completion_timeout(&test.done, 500) || test.value != -ERESTARTSYS)
            result = -EIO;
    } else {
        /* Actual wait conditions use separate live storage. Address hashing
         * and keyed variable wake must not read the retired object itself. */
        if (allocated) { kfree(address); allocated = false; }
        WRITE_ONCE(payload, 42);
        WRITE_ONCE(ready, 1);
        smp_mb();
        unsigned long flags = vinix_linuxkpi_irq_save();
        wake_up_var(address);
        vinix_linuxkpi_irq_restore(flags);
        if (!wait_for_completion_timeout(&test.done, 500)) result = -EIO;
    }
out:
    WRITE_ONCE(payload, 42);
    WRITE_ONCE(ready, 1);
    smp_mb();
    wake_up_var(address);
    if (native_bit_join(&test) || waitqueue_active(__var_waitqueue(address))) result = -EIO;
    if (allocated) kfree(address);
    return result;
}

static int native_bit_action_error(struct wait_bit_key *key, int mode) { return -ENOSPC; }
static int native_bit_action_clear(struct wait_bit_key *key, int mode)
{
    clear_bit_unlock(key->bit_nr, key->flags);
    return -EINTR;
}

static int native_bit_repeated(void)
{
    unsigned long word = 0;
    unsigned int ready = 1;
    int result = 0;
    for (unsigned int i = 0; i < 256; i++) {
        set_bit(0, &word);
        if (wait_on_bit_timeout(&word, 0, TASK_UNINTERRUPTIBLE, 0) != -EAGAIN ||
            wait_on_bit_action(&word, 0, native_bit_action_error, TASK_UNINTERRUPTIBLE) != -ENOSPC)
            result = -EIO;
        unsigned long started = jiffies;
        if (wait_on_bit_timeout(&word, 0, TASK_UNINTERRUPTIBLE, 1) != -EAGAIN ||
            time_before(jiffies, started + 1)) result = -EIO;
        /* Finish an errored wait, then win the now-free atomic lock. */
        if (wait_on_bit_lock_action(&word, 0, native_bit_action_clear, TASK_INTERRUPTIBLE) ||
            !test_bit(0, &word)) result = -EIO;
        clear_and_wake_up_bit(0, &word);
        if (wait_on_bit_timeout(&word, 0, TASK_UNINTERRUPTIBLE, 0) ||
            wait_var_event_timeout(&ready, READ_ONCE(ready), 0) != 1 ||
            wait_var_event_timeout(&ready, false, 1)) result = -EIO;
        if (waitqueue_active(bit_waitqueue(&word, 0)) || waitqueue_active(__var_waitqueue(&ready)))
            result = -EIO;
    }
    /* A completed condition wins even a simultaneously pending fatal signal.
     * Force the original variable slow macro as well: prepare_to_wait_event
     * must remove its stack record before the true condition wins the signal. */
    vinix_linuxkpi_test_task_signal(current->vinix_thread, 1ULL << 8);
    if (wait_var_event_killable(&ready, READ_ONCE(ready)) ||
        __wait_var_event_killable(&ready, READ_ONCE(ready)) ||
        __wait_var_event_interruptible(&ready, READ_ONCE(ready)) ||
        wait_on_bit(&word, 0, TASK_INTERRUPTIBLE)) result = -EIO;
    vinix_linuxkpi_test_task_signal(current->vinix_thread, 0);
    if (!task_is_running(current) || waitqueue_active(__var_waitqueue(&ready))) result = -EIO;
    return result;
}

int vinix_linuxkpi_wait_bit_native_selftest(void)
{
    extern int kprintf(const char *, ...);
    int result = 0;
#ifdef VINIX_LINUXKPI_TEST_TRACE
    kprintf("linuxkpi: wait-bit trace: repeated begin\n");
#endif
    if (native_bit_repeated()) { kprintf("linuxkpi: wait-bit repeated/action/deadline checks failed\n"); result = -EIO; }
#ifdef VINIX_LINUXKPI_TEST_TRACE
    kprintf("linuxkpi: wait-bit trace: repeated end; keyed begin\n");
#endif
    if (native_bit_keyed()) { kprintf("linuxkpi: wait-bit keyed collision/IRQ-off wake failed\n"); result = -EIO; }
#ifdef VINIX_LINUXKPI_TEST_TRACE
    kprintf("linuxkpi: wait-bit trace: keyed end; quota begin\n");
#endif
    if (native_bit_quota()) { kprintf("linuxkpi: wait-bit exclusive quota failed\n"); result = -EIO; }
#ifdef VINIX_LINUXKPI_TEST_TRACE
    kprintf("linuxkpi: wait-bit trace: quota end; display begin\n");
#endif
    if (native_bit_display()) { kprintf("linuxkpi: wait-bit ordinary SET waiter failed\n"); result = -EIO; }
#ifdef VINIX_LINUXKPI_TEST_TRACE
    kprintf("linuxkpi: wait-bit trace: display end; interrupt begin\n");
#endif
    if (native_bit_interrupt()) { kprintf("linuxkpi: wait-bit signal cancellation failed\n"); result = -EIO; }
#ifdef VINIX_LINUXKPI_TEST_TRACE
    kprintf("linuxkpi: wait-bit trace: interrupt end; variable killable begin\n");
#endif
    if (native_var_test(true, false)) { kprintf("linuxkpi: variable killable filtering failed\n"); result = -EIO; }
#ifdef VINIX_LINUXKPI_TEST_TRACE
    kprintf("linuxkpi: wait-bit trace: variable killable end; freed key begin\n");
#endif
    if (native_var_test(false, false)) { kprintf("linuxkpi: variable freed-address wake failed\n"); result = -EIO; }
#ifdef VINIX_LINUXKPI_TEST_TRACE
    kprintf("linuxkpi: wait-bit trace: freed key end; inaccessible key begin\n");
#endif
    if (native_var_test(false, true)) { kprintf("linuxkpi: variable inaccessible-address wake failed\n"); result = -EIO; }
#ifdef VINIX_LINUXKPI_TEST_TRACE
    kprintf("linuxkpi: wait-bit trace: inaccessible key end\n");
#endif
    return result;
}
#endif
