/* SPDX-License-Identifier: GPL-2.0-only */
/* Hashed bit/variable waits and action loops adapted from Linux 6.6.157
 * kernel/sched/wait_bit.c. Native queue/task/deadline services, bootstrap
 * publication and stack lifetime guarantees are supplied by Vinix. */
#ifdef VINIX_LINUXKPI
#include <linux/sched.h>
#include <linux/sched/signal.h>
#include <linux/init.h>
#include <linux/bitops.h>
#include <linux/wait_bit.h>
#include <linux/jiffies.h>
#include <linux/hash.h>
#include <linux/cache.h>
#include <linux/bug.h>
#include <linux/errno.h>

#define WAIT_TABLE_BITS 8
#define WAIT_TABLE_SIZE (1U << WAIT_TABLE_BITS)

/* Permanent boot storage, with no per-word or per-waiter allocation. Original
 * DEFINE_WAIT_BIT/variable-event records remain on the waiting task's stack. */
static wait_queue_head_t bit_wait_table[WAIT_TABLE_SIZE] __cacheline_aligned;
static bool bit_wait_ready;

void wait_bit_init(void)
{
    /* Bootstrap is serialized by the boot owner before publishing any users.
     * A later idempotent call must never reset a queue containing live waits. */
    if (__atomic_load_n(&bit_wait_ready, __ATOMIC_ACQUIRE)) return;
    for (unsigned int bucket = 0; bucket < WAIT_TABLE_SIZE; bucket++)
        init_waitqueue_head(&bit_wait_table[bucket]);
    __atomic_store_n(&bit_wait_ready, true, __ATOMIC_RELEASE);
}

wait_queue_head_t *bit_waitqueue(void *word, int bit)
{
    BUG_ON(!__atomic_load_n(&bit_wait_ready, __ATOMIC_ACQUIRE));
    const int shift = BITS_PER_LONG == 32 ? 5 : 6;
    unsigned long value = (unsigned long)word << shift | bit;
    /* Keep the original address/index key even for bits in another word of
     * a caller-owned bitmap. Hash collisions never determine key equality. */
    return &bit_wait_table[hash_long(value, WAIT_TABLE_BITS)];
}

wait_queue_head_t *__var_waitqueue(void *variable)
{
    BUG_ON(!__atomic_load_n(&bit_wait_ready, __ATOMIC_ACQUIRE));
    /* An address key may refer to an object already retired by the producer.
     * Neither this hash nor the variable wake callback reads that object. */
    return &bit_wait_table[hash_ptr(variable, WAIT_TABLE_BITS)];
}

int wake_bit_function(struct wait_queue_entry *entry, unsigned int mode,
                      int sync, void *argument)
{
    struct wait_bit_key *key = argument;
    struct wait_bit_queue_entry *wait = container_of(entry, struct wait_bit_queue_entry, wq_entry);
    if (wait->key.flags != key->flags || wait->key.bit_nr != key->bit_nr ||
        test_bit(key->bit_nr, key->flags)) return 0;
    return autoremove_wake_function(entry, mode, sync, key);
}

static int var_wake_function(struct wait_queue_entry *entry, unsigned int mode,
                            int sync, void *argument)
{
    struct wait_bit_key *key = argument;
    struct wait_bit_queue_entry *wait = container_of(entry, struct wait_bit_queue_entry, wq_entry);
    if (wait->key.flags != key->flags || wait->key.bit_nr != key->bit_nr) return 0;
    return autoremove_wake_function(entry, mode, sync, key);
}

void init_wait_var_entry(struct wait_bit_queue_entry *wait, void *variable, int flags)
{
    *wait = (struct wait_bit_queue_entry){
        .key = { .flags = variable, .bit_nr = -1 },
        .wq_entry = {
            .flags = flags,
            .private = current,
            .func = var_wake_function,
            .entry = LIST_HEAD_INIT(wait->wq_entry.entry),
        },
    };
}

int __wait_on_bit(struct wait_queue_head *queue, struct wait_bit_queue_entry *wait,
                  wait_bit_action_f *action, unsigned int mode)
{
    int result = 0;
    do {
        prepare_to_wait(queue, &wait->wq_entry, mode);
        if (test_bit(wait->key.bit_nr, wait->key.flags)) result = action(&wait->key, mode);
    } while (test_bit_acquire(wait->key.bit_nr, wait->key.flags) && !result);
    /* Native finish_wait always takes the queue lock, including after an
     * autoremove wake, before this record's stack frame is allowed to return. */
    finish_wait(queue, &wait->wq_entry);
    return result;
}

int out_of_line_wait_on_bit(void *word, int bit, wait_bit_action_f *action,
                            unsigned int mode)
{
    struct wait_queue_head *queue = bit_waitqueue(word, bit);
    DEFINE_WAIT_BIT(wait, word, bit);
    return __wait_on_bit(queue, &wait, action, mode);
}

int out_of_line_wait_on_bit_timeout(void *word, int bit, wait_bit_action_f *action,
                                    unsigned int mode, unsigned long timeout)
{
    struct wait_queue_head *queue = bit_waitqueue(word, bit);
    DEFINE_WAIT_BIT(wait, word, bit);
    /* Capture the absolute boundary once. Spurious wakes must not extend it. */
    wait.key.timeout = jiffies + timeout;
    return __wait_on_bit(queue, &wait, action, mode);
}

int __wait_on_bit_lock(struct wait_queue_head *queue, struct wait_bit_queue_entry *wait,
                       wait_bit_action_f *action, unsigned int mode)
{
    int result = 0;
    for (;;) {
        prepare_to_wait_exclusive(queue, &wait->wq_entry, mode);
        if (test_bit(wait->key.bit_nr, wait->key.flags)) {
            result = action(&wait->key, mode);
            if (result) finish_wait(queue, &wait->wq_entry);
        }
        /* The fully ordered atomic acquisition wins a concurrent signal or
         * action error if the bit is available, including after cancellation. */
        if (!test_and_set_bit(wait->key.bit_nr, wait->key.flags)) {
            if (!result) finish_wait(queue, &wait->wq_entry);
            return 0;
        } else if (result) return result;
    }
}

int out_of_line_wait_on_bit_lock(void *word, int bit, wait_bit_action_f *action,
                                 unsigned int mode)
{
    struct wait_queue_head *queue = bit_waitqueue(word, bit);
    DEFINE_WAIT_BIT(wait, word, bit);
    return __wait_on_bit_lock(queue, &wait, action, mode);
}

void __wake_up_bit(struct wait_queue_head *queue, void *word, int bit)
{
    struct wait_bit_key key = __WAIT_BIT_KEY_INITIALIZER(word, bit);
    /* The caller must order its condition publication before this active
     * check, as required by the original helpers. Key filtering happens in
     * each callback; ordinary entries on the bucket also receive this wake. */
    if (waitqueue_active(queue)) __wake_up(queue, TASK_NORMAL, 1, &key);
}

void wake_up_bit(void *word, int bit)
{
    /* Dispatch even while the bit is SET: i915's display reset uses ordinary
     * queue entries here to wait for a set bit, rather than wake_bit_function. */
    __wake_up_bit(bit_waitqueue(word, bit), word, bit);
}

void wake_up_var(void *variable)
{
    __wake_up_bit(__var_waitqueue(variable), variable, -1);
}

int bit_wait(struct wait_bit_key *key, int mode)
{
    schedule();
    return signal_pending_state(mode, current) ? -EINTR : 0;
}

int bit_wait_timeout(struct wait_bit_key *key, int mode)
{
    unsigned long now = READ_ONCE(jiffies);
    if (time_after_eq(now, key->timeout)) return -EAGAIN;
    schedule_timeout(key->timeout - now);
    return signal_pending_state(mode, current) ? -EINTR : 0;
}

/* I/O actions live in linuxkpi_io.c with native blocked-CPU accounting. */
#endif
