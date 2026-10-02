/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_WAIT_BIT_TEST_H
#define VINIX_WAIT_BIT_TEST_H
/* Public Linux bit/variable waits against the real task wait and timeout
 * backends. Included after sync_test.h and time_test.h by the host runner. */
#include <linux/init.h>
#include <linux/bitops.h>
#include <linux/wait_bit.h>
#include <sys/mman.h>

static void wait_bit_test_wait(unsigned int *value, unsigned int target)
{
    for (unsigned int spin = 0; spin < 1000000; spin++) {
        if (__atomic_load_n(value, __ATOMIC_ACQUIRE) >= target) return;
        sched_yield();
    }
    assert(!"bit/variable wait did not make progress");
}

enum wait_bit_test_operation {
    WAIT_BIT_NORMAL, WAIT_BIT_LOCK, WAIT_BIT_TIMED, WAIT_BIT_SET,
    WAIT_VAR_NORMAL, WAIT_VAR_INTERRUPT, WAIT_VAR_KILLABLE, WAIT_VAR_TIMED,
};
struct wait_bit_test_actor {
    struct native_task_model model;
    pthread_t thread;
    unsigned long *word;
    void *key;
    unsigned int *condition, *payload;
    enum wait_bit_test_operation operation;
    unsigned int state, started, actions, awakened, action_release, returned, release, done;
    int bit;
    long timeout, result;
    bool gate_action, clear_before_park, success_at_expiry, track_timeout;
};
static _Thread_local struct wait_bit_test_actor *wait_bit_test_current;

static int wait_bit_test_action(struct wait_bit_key *key, int mode)
{
    struct wait_bit_test_actor *actor = wait_bit_test_current;
    assert(actor && key->flags == actor->word && key->bit_nr == actor->bit);
    __atomic_fetch_add(&actor->actions, 1, __ATOMIC_RELEASE);
    int result = actor->operation == WAIT_BIT_TIMED ? bit_wait_timeout(key, mode) : bit_wait(key, mode);
    __atomic_fetch_add(&actor->awakened, 1, __ATOMIC_RELEASE);
    if (actor->gate_action) wait_bit_test_wait(&actor->action_release, 1);
    return result;
}
static void wait_bit_test_clear_hook(void)
{
    struct wait_bit_test_actor *actor = wait_bit_test_current;
    assert(actor && actor->clear_before_park);
    if (!queue_waiters(bit_waitqueue(actor->word, actor->bit))) {
        host_irq_restore_hook = wait_bit_test_clear_hook;
        return;
    }
    if (actor->payload) *actor->payload = 0xabc123;
    clear_and_wake_up_bit(actor->bit, actor->word);
}
static void wait_bit_test_expiry_hook(void)
{
    struct wait_bit_test_actor *actor = wait_bit_test_current;
    assert(actor && actor->success_at_expiry);
    if (!vinix_linuxkpi_time_waiters()) {
        host_irq_restore_hook = wait_bit_test_expiry_hook;
        return;
    }
    host_time_advance(actor->timeout);
    if (actor->payload) *actor->payload = 0xabc123;
    store_release_wake_up(actor->condition, 1);
}
static void *wait_bit_test_actor_thread(void *argument)
{
    struct wait_bit_test_actor *actor = argument;
    native_task = &actor->model;
    current_cpu = actor->model.pid % 4;
    wait_bit_test_current = actor;
    __atomic_store_n(&actor->started, 1, __ATOMIC_RELEASE);
    if (actor->clear_before_park) host_irq_restore_hook = wait_bit_test_clear_hook;
    if (actor->success_at_expiry) host_irq_restore_hook = wait_bit_test_expiry_hook;
    switch (actor->operation) {
    case WAIT_BIT_NORMAL:
        actor->result = wait_on_bit_action(actor->word, actor->bit, wait_bit_test_action, actor->state);
        break;
    case WAIT_BIT_LOCK:
        actor->result = wait_on_bit_lock_action(actor->word, actor->bit, wait_bit_test_action, actor->state);
        break;
    case WAIT_BIT_TIMED:
        actor->result = actor->track_timeout ?
            out_of_line_wait_on_bit_timeout(actor->word, actor->bit, wait_bit_test_action,
                                            actor->state, actor->timeout) :
            wait_on_bit_timeout(actor->word, actor->bit, actor->state, actor->timeout);
        break;
    case WAIT_BIT_SET: {
        struct wait_queue_head *queue = bit_waitqueue(actor->word, actor->bit);
        DEFINE_WAIT(wait);
        for (;;) {
            prepare_to_wait(queue, &wait, actor->state);
            if (test_bit_acquire(actor->bit, actor->word)) break;
            schedule();
        }
        finish_wait(queue, &wait);
        break;
    }
    case WAIT_VAR_NORMAL:
        wait_var_event(actor->key, __atomic_load_n(actor->condition, __ATOMIC_ACQUIRE));
        break;
    case WAIT_VAR_INTERRUPT:
        actor->result = wait_var_event_interruptible(actor->key,
            __atomic_load_n(actor->condition, __ATOMIC_ACQUIRE));
        break;
    case WAIT_VAR_KILLABLE:
        actor->result = wait_var_event_killable(actor->key,
            __atomic_load_n(actor->condition, __ATOMIC_ACQUIRE));
        break;
    case WAIT_VAR_TIMED:
        actor->result = wait_var_event_timeout(actor->key,
            __atomic_load_n(actor->condition, __ATOMIC_ACQUIRE), actor->timeout);
        break;
    }
    assert(task_is_running(current) && interrupts && !preempt_depth);
    assert(!host_irq_restore_hook);
    if (actor->payload && actor->result >= 0) assert(*actor->payload == 0xabc123);
    __atomic_store_n(&actor->returned, 1, __ATOMIC_RELEASE);
    if (actor->operation == WAIT_BIT_LOCK && !actor->result) {
        assert(test_bit(actor->bit, actor->word));
        wait_bit_test_wait(&actor->release, 1);
        clear_and_wake_up_bit(actor->bit, actor->word);
    }
    __atomic_store_n(&actor->done, 1, __ATOMIC_RELEASE);
    wait_bit_test_current = NULL;
    native_task = NULL;
    return NULL;
}
static void wait_bit_test_start(struct wait_bit_test_actor *actor,
                                enum wait_bit_test_operation operation,
                                unsigned long *word, int bit, unsigned int state)
{
    actor->operation = operation;
    actor->word = word;
    if (!actor->key) actor->key = word;
    actor->bit = bit;
    actor->state = state;
    sync_model_init(&actor->model, 220);
    actor->model.iteration = 1;
    assert(!pthread_create(&actor->thread, NULL, wait_bit_test_actor_thread, actor));
    wait_bit_test_wait(&actor->started, 1);
}
static void wait_bit_test_parked(struct wait_bit_test_actor *actor)
{
    wait_bit_test_wait(&actor->model.parked, 1);
    assert(!vinix_linuxkpi_task_queued(&actor->model));
    struct wait_queue_head *queue = actor->operation >= WAIT_VAR_NORMAL ?
        __var_waitqueue(actor->key) : bit_waitqueue(actor->word, actor->bit);
    assert(waitqueue_active(queue));
}
static void wait_bit_test_join(struct wait_bit_test_actor *actor)
{
    wait_bit_test_wait(&actor->done, 1);
    assert(!pthread_join(actor->thread, NULL));
    sync_model_destroy(&actor->model);
}
static void wait_bit_test_signal(struct wait_bit_test_actor *actor, u64 signal)
{
    __atomic_store_n(&actor->model.pending, signal, __ATOMIC_RELEASE);
    /* Native signal delivery enqueues without changing the Linux wait state;
     * schedule must apply that state's fatal/nonfatal signal filter itself. */
    assert(vinix_linuxkpi_task_enqueue(&actor->model));
}
static void wait_bit_test_basics(void)
{
    unsigned long words[3] = {0};
    assert(!wait_on_bit(words, BITS_PER_LONG + 5, TASK_UNINTERRUPTIBLE));
    assert(!wait_on_bit_timeout(words, 3, TASK_INTERRUPTIBLE, 0));
    assert(!wait_on_bit_lock(words, BITS_PER_LONG + 5, TASK_UNINTERRUPTIBLE));
    assert(test_bit(BITS_PER_LONG + 5, words));
    clear_and_wake_up_bit(BITS_PER_LONG + 5, words);
    for (unsigned int early = 0; early < 2; early++) {
        unsigned int payload = 0;
        set_bit(BITS_PER_LONG + 5, words);
        struct wait_bit_test_actor actor = { .payload = &payload, .clear_before_park = !!early };
        wait_bit_test_start(&actor, WAIT_BIT_NORMAL, words, BITS_PER_LONG + 5, TASK_UNINTERRUPTIBLE);
        if (!early) {
            wait_bit_test_parked(&actor);
            unsigned long flags = vinix_linuxkpi_irq_save();
            payload = 0xabc123;
            clear_and_wake_up_bit(BITS_PER_LONG + 5, words);
            assert(!interrupts);
            vinix_linuxkpi_irq_restore(flags);
        }
        wait_bit_test_join(&actor);
        assert(!actor.result && !waitqueue_active(bit_waitqueue(words, BITS_PER_LONG + 5)));
        if (early) assert(!actor.model.parked);
    }
    /* Ordinary bucket users wait for SET, as display reset code does. A
     * bucket wake must not reject all users just because its bit stays set. */
    struct wait_bit_test_actor set = {0};
    wait_bit_test_start(&set, WAIT_BIT_SET, words, 11, TASK_UNINTERRUPTIBLE);
    wait_bit_test_parked(&set);
    set_bit(11, words); smp_mb__after_atomic(); wake_up_bit(words, 11);
    wait_bit_test_join(&set);
    assert(!set.result && test_bit(11, words));
    clear_and_wake_up_bit(11, words);
}

static void wait_bit_test_collision_keys(unsigned long words[][8], size_t count,
                                        int *first, int *second, unsigned long **other)
{
    *first = *second = -1;
    for (int a = 0; a < 8 * BITS_PER_LONG && *first < 0; a++)
        for (int b = a + 1 > BITS_PER_LONG ? a + 1 : BITS_PER_LONG;
             b < 8 * BITS_PER_LONG; b++)
            if (bit_waitqueue(words[0], a) == bit_waitqueue(words[0], b)) {
                *first = a; *second = b; break;
            }
    assert(*first >= 0 && *second > *first);
    *other = NULL;
    for (size_t i = 1; i < count; i++)
        if (bit_waitqueue(words[i], *first) == bit_waitqueue(words[0], *first)) {
            *other = words[i]; break;
        }
    assert(*other);
}
static void wait_bit_test_collisions(void)
{
    unsigned long words[1024][8] = {{0}}, *other;
    int first, second;
    wait_bit_test_collision_keys(words, ARRAY_SIZE(words), &first, &second, &other);
    for (unsigned int different_address = 0; different_address < 2; different_address++) {
        unsigned long *wrong_word = different_address ? other : words[0];
        int wrong_bit = different_address ? first : second;
        set_bit(first, words[0]); set_bit(wrong_bit, wrong_word);
        struct wait_bit_test_actor matching = {0}, wrong = {0};
        wait_bit_test_start(&wrong, WAIT_BIT_NORMAL, wrong_word, wrong_bit, TASK_UNINTERRUPTIBLE);
        wait_bit_test_parked(&wrong);
        wait_bit_test_start(&matching, WAIT_BIT_NORMAL, words[0], first, TASK_UNINTERRUPTIBLE);
        wait_bit_test_parked(&matching);
        assert(queue_waiters(bit_waitqueue(words[0], first)) == 2);
        /* Initializing again must preserve existing boot-lifetime buckets. */
        wait_bit_init();
        wake_up_bit(words[0], first); /* A still-set matching bit is filtered. */
        assert(!vinix_linuxkpi_task_queued(&matching.model));
        assert(!vinix_linuxkpi_task_queued(&wrong.model));
        assert(test_and_clear_wake_up_bit(first, words[0]));
        assert(!test_and_clear_wake_up_bit(first, words[0]));
        wait_bit_test_join(&matching);
        assert(!__atomic_load_n(&wrong.returned, __ATOMIC_ACQUIRE));
        assert(!vinix_linuxkpi_task_queued(&wrong.model));
        assert(queue_waiters(bit_waitqueue(words[0], first)) == 1);
        clear_and_wake_up_bit(wrong_bit, wrong_word);
        wait_bit_test_join(&wrong);
        assert(!matching.result && !wrong.result);
        assert(!waitqueue_active(bit_waitqueue(words[0], first)));
    }
}
static void wait_bit_test_wake_quota(void)
{
    unsigned long words[1024][8] = {{0}}, *other;
    int bit, wrong_bit;
    wait_bit_test_collision_keys(words, ARRAY_SIZE(words), &bit, &wrong_bit, &other);
    set_bit(bit, words[0]); set_bit(wrong_bit, words[0]);
    struct wait_bit_test_actor wrong = { .gate_action = true };
    struct wait_bit_test_actor lockers[2] = {{ .gate_action = true }, { .gate_action = true }};
    struct wait_bit_test_actor normal[3] = {{ .gate_action = true },
        { .gate_action = true }, { .gate_action = true }};
    /* A mismatched exclusive waiter precedes the matching exclusive waiters. */
    wait_bit_test_start(&wrong, WAIT_BIT_LOCK, words[0], wrong_bit, TASK_UNINTERRUPTIBLE);
    wait_bit_test_parked(&wrong);
    for (unsigned int i = 0; i < ARRAY_SIZE(lockers); i++) {
        wait_bit_test_start(&lockers[i], WAIT_BIT_LOCK, words[0], bit, TASK_UNINTERRUPTIBLE);
        wait_bit_test_parked(&lockers[i]);
    }
    for (unsigned int i = 0; i < ARRAY_SIZE(normal); i++) {
        wait_bit_test_start(&normal[i], WAIT_BIT_NORMAL, words[0], bit, TASK_UNINTERRUPTIBLE);
        wait_bit_test_parked(&normal[i]);
    }
    unsigned long flags = vinix_linuxkpi_irq_save();
    clear_and_wake_up_bit(bit, words[0]);
    assert(!interrupts);
    vinix_linuxkpi_irq_restore(flags);
    for (unsigned int i = 0; i < ARRAY_SIZE(normal); i++) wait_bit_test_wait(&normal[i].awakened, 1);
    wait_bit_test_wait(&lockers[0].awakened, 1);
    assert(!vinix_linuxkpi_task_queued(&wrong.model));
    assert(!vinix_linuxkpi_task_queued(&lockers[1].model));
    assert(!wrong.awakened && !lockers[1].awakened);
    assert(queue_waiters(bit_waitqueue(words[0], bit)) == 2);
    /* Hold the selected locker outside its atomic acquisition until every
     * ordinary waiter has observed the cleared bit and retired its stack. */
    for (unsigned int i = 0; i < ARRAY_SIZE(normal); i++) {
        __atomic_store_n(&normal[i].action_release, 1, __ATOMIC_RELEASE);
        wait_bit_test_join(&normal[i]);
        assert(!normal[i].result);
    }
    __atomic_store_n(&lockers[0].action_release, 1, __ATOMIC_RELEASE);
    wait_bit_test_wait(&lockers[0].returned, 1);
    assert(!lockers[0].result && test_bit(bit, words[0]));
    __atomic_store_n(&lockers[0].release, 1, __ATOMIC_RELEASE);
    wait_bit_test_join(&lockers[0]);
    wait_bit_test_wait(&lockers[1].awakened, 1);
    __atomic_store_n(&lockers[1].action_release, 1, __ATOMIC_RELEASE);
    wait_bit_test_wait(&lockers[1].returned, 1);
    assert(!lockers[1].result && test_bit(bit, words[0]));
    __atomic_store_n(&lockers[1].release, 1, __ATOMIC_RELEASE);
    wait_bit_test_join(&lockers[1]);
    __atomic_store_n(&wrong.action_release, 1, __ATOMIC_RELEASE);
    __atomic_store_n(&wrong.release, 1, __ATOMIC_RELEASE);
    clear_and_wake_up_bit(wrong_bit, words[0]);
    wait_bit_test_join(&wrong);
    assert(!wrong.result && !waitqueue_active(bit_waitqueue(words[0], bit)));
}

static unsigned int wait_bit_test_custom_calls;
static int wait_bit_test_custom_result;
static bool wait_bit_test_custom_clear;
static int wait_bit_test_custom_action(struct wait_bit_key *key, int mode)
{
    assert(current->__state == (unsigned int)mode);
    wait_bit_test_custom_calls++;
    if (wait_bit_test_custom_clear) clear_bit(key->bit_nr, key->flags);
    return wait_bit_test_custom_result;
}
static void wait_bit_test_actions(void)
{
    unsigned long word = BIT(7);
    DECLARE_WAIT_QUEUE_HEAD(queue);
    DEFINE_WAIT_BIT(wait, &word, 7);
    for (unsigned int lock = 0; lock < 2; lock++) {
        for (unsigned int clear = 0; clear < 2; clear++) {
            for (unsigned int positive = 0; positive < 2; positive++) {
                set_bit(7, &word);
                wait_bit_test_custom_calls = 0;
                wait_bit_test_custom_result = positive ? 7 : -EIO;
                wait_bit_test_custom_clear = !!clear;
                int result = lock ?
                    __wait_on_bit_lock(&queue, &wait, wait_bit_test_custom_action, TASK_INTERRUPTIBLE) :
                    __wait_on_bit(&queue, &wait, wait_bit_test_custom_action, TASK_INTERRUPTIBLE);
                assert(result == (lock && clear ? 0 : wait_bit_test_custom_result));
                assert(wait_bit_test_custom_calls == 1 && !waitqueue_active(&queue));
                assert(task_is_running(current));
                assert(test_bit(7, &word) == (!!lock || !clear));
            }
        }
    }
    clear_and_wake_up_bit(7, &word);
}
static void wait_bit_test_signals(void)
{
    unsigned long word = BIT(9);
    /* Reuse stack addresses over many successful cancellations. Every case
     * must detach the entry, timer and task reference before model reuse. */
    for (unsigned int round = 0; round < 32; round++) {
        for (unsigned int kind = WAIT_BIT_NORMAL; kind <= WAIT_BIT_TIMED; kind++) {
            struct wait_bit_test_actor actor = { .timeout = 10 };
            wait_bit_test_start(&actor, kind, &word, 9, TASK_INTERRUPTIBLE);
            wait_bit_test_parked(&actor);
            wait_bit_test_signal(&actor, 1ULL << 14);
            wait_bit_test_join(&actor);
            assert(actor.result == -EINTR && test_bit(9, &word));
            assert(!waitqueue_active(bit_waitqueue(&word, 9)) && !vinix_linuxkpi_time_waiters());
        }
    }
    for (unsigned int lock = 0; lock < 2; lock++) {
        struct wait_bit_test_actor actor = {0};
        wait_bit_test_start(&actor, lock ? WAIT_BIT_LOCK : WAIT_BIT_NORMAL,
                            &word, 9, TASK_KILLABLE);
        wait_bit_test_parked(&actor);
        wait_bit_test_signal(&actor, 1ULL << 14); /* Nonfatal signal is ignored. */
        while (vinix_linuxkpi_task_queued(&actor.model)) sched_yield();
        assert(!__atomic_load_n(&actor.returned, __ATOMIC_ACQUIRE));
        assert(__atomic_load_n(&actor.actions, __ATOMIC_ACQUIRE) == 1);
        wait_bit_test_signal(&actor, 1ULL << 8);
        wait_bit_test_join(&actor);
        assert(actor.result == -EINTR && test_bit(9, &word));
    }
    /* A lock's available bit wins the action's signal result. An ordinary
     * bit waiter still returns its action error when the bit clears late. */
    for (unsigned int lock = 0; lock < 2; lock++) {
        struct wait_bit_test_actor actor = { .gate_action = true };
        wait_bit_test_start(&actor, lock ? WAIT_BIT_LOCK : WAIT_BIT_NORMAL,
                            &word, 9, TASK_INTERRUPTIBLE);
        wait_bit_test_parked(&actor);
        wait_bit_test_signal(&actor, 1ULL << 14);
        wait_bit_test_wait(&actor.awakened, 1);
        clear_and_wake_up_bit(9, &word);
        __atomic_store_n(&actor.action_release, 1, __ATOMIC_RELEASE);
        if (lock) {
            wait_bit_test_wait(&actor.returned, 1);
            assert(!actor.result && test_bit(9, &word));
            __atomic_store_n(&actor.release, 1, __ATOMIC_RELEASE);
        }
        wait_bit_test_join(&actor);
        assert(actor.result == (lock ? 0 : -EINTR));
        assert(!waitqueue_active(bit_waitqueue(&word, 9)));
        set_bit(9, &word);
    }
    clear_and_wake_up_bit(9, &word);
    native_task->pending = 1ULL << 14;
    assert(!wait_on_bit(&word, 9, TASK_INTERRUPTIBLE));
    assert(!wait_on_bit_lock(&word, 9, TASK_INTERRUPTIBLE));
    clear_and_wake_up_bit(9, &word);
    native_task->pending = 0;
}
static void wait_bit_test_deadlines(void)
{
    unsigned long word = BIT(12);
    assert(wait_on_bit_timeout(&word, 12, TASK_UNINTERRUPTIBLE, 0) == -EAGAIN);
    assert(!waitqueue_active(bit_waitqueue(&word, 12)) && !vinix_linuxkpi_time_waiters());
    struct wait_bit_test_actor actor = { .timeout = 10, .track_timeout = true };
    wait_bit_test_start(&actor, WAIT_BIT_TIMED, &word, 12, TASK_UNINTERRUPTIBLE);
    wait_bit_test_parked(&actor);
    assert(vinix_linuxkpi_time_waiters() == 1);
    host_time_advance(3);
    wake_up_process((struct task_struct *)actor.model.storage); /* Spurious wake at tick 3. */
    wait_bit_test_wait(&actor.actions, 2);
    while (!vinix_linuxkpi_time_waiters() || vinix_linuxkpi_task_queued(&actor.model)) sched_yield();
    host_time_advance(3);
    wake_up_process((struct task_struct *)actor.model.storage); /* Spurious wake at tick 6. */
    wait_bit_test_wait(&actor.actions, 3);
    while (!vinix_linuxkpi_time_waiters() || vinix_linuxkpi_task_queued(&actor.model)) sched_yield();
    host_time_advance(4); /* Original boundary, rather than ten ticks after the last wake. */
    wait_bit_test_join(&actor);
    assert(actor.result == -EAGAIN && test_bit(12, &word));
    assert(!vinix_linuxkpi_time_waiters() && !waitqueue_active(bit_waitqueue(&word, 12)));
    actor = (struct wait_bit_test_actor){ .timeout = 10 };
    wait_bit_test_start(&actor, WAIT_BIT_TIMED, &word, 12, TASK_UNINTERRUPTIBLE);
    wait_bit_test_parked(&actor);
    host_time_advance(4);
    clear_and_wake_up_bit(12, &word);
    wait_bit_test_join(&actor);
    assert(!actor.result && !vinix_linuxkpi_time_waiters());
    /* Isolate wrap arithmetic from the host's bounded nanosecond clock.
     * Inject jiffies only while no threads/deadlines are live, and restore it
     * without issuing a tick. A future deadline crossing zero must pass the
     * expiry check and return the pending signal; an elapsed boundary must
     * report expiry. Real sleeping/deadline dispatch is covered above. */
    assert(!vinix_linuxkpi_time_waiters());
    unsigned long actual_jiffies = READ_ONCE(jiffies);
    WRITE_ONCE(jiffies, ULONG_MAX - 3);
    set_bit(12, &word);
    native_task->pending = 1ULL << 14;
    assert(wait_on_bit_timeout(&word, 12, TASK_INTERRUPTIBLE, 6) == -EINTR);
    native_task->pending = 0;
    WRITE_ONCE(jiffies, 2);
    struct wait_bit_key key = { .flags = &word, .bit_nr = 12, .timeout = ULONG_MAX - 3 };
    assert(bit_wait_timeout(&key, TASK_UNINTERRUPTIBLE) == -EAGAIN);
    WRITE_ONCE(jiffies, actual_jiffies);
    assert(task_is_running(current) && !vinix_linuxkpi_time_waiters());
    clear_and_wake_up_bit(12, &word);
}
static void wait_bit_test_variables(void)
{
    unsigned int values[1024] = {0}, *other = NULL;
    for (size_t i = 1; i < ARRAY_SIZE(values); i++) {
        if (__var_waitqueue(&values[i]) == __var_waitqueue(&values[0])) {
            other = &values[i]; break;
        }
    }
    assert(other);
    unsigned int conditions[2] = {0}, payload = 0;
    struct wait_bit_test_actor wrong = { .key = other, .condition = &conditions[1] };
    struct wait_bit_test_actor matching = { .key = &values[0], .condition = &conditions[0] };
    wait_bit_test_start(&wrong, WAIT_VAR_NORMAL, NULL, 0, TASK_UNINTERRUPTIBLE);
    wait_bit_test_parked(&wrong);
    wait_bit_test_start(&matching, WAIT_VAR_NORMAL, NULL, 0, TASK_UNINTERRUPTIBLE);
    wait_bit_test_parked(&matching);
    __atomic_store_n(&conditions[0], 1, __ATOMIC_RELEASE); smp_mb(); wake_up_var(&values[0]);
    wait_bit_test_join(&matching);
    assert(!vinix_linuxkpi_task_queued(&wrong.model));
    assert(queue_waiters(__var_waitqueue(&values[0])) == 1);
    __atomic_store_n(&conditions[1], 1, __ATOMIC_RELEASE); smp_mb(); wake_up_var(other);
    wait_bit_test_join(&wrong);
    assert(!waitqueue_active(__var_waitqueue(&values[0])));
    for (unsigned int round = 0; round < 32; round++) {
        for (unsigned int killable = 0; killable < 2; killable++) {
            unsigned int condition = 0;
            struct wait_bit_test_actor actor = { .key = &condition, .condition = &condition };
            wait_bit_test_start(&actor, killable ? WAIT_VAR_KILLABLE : WAIT_VAR_INTERRUPT,
                                NULL, 0, killable ? TASK_KILLABLE : TASK_INTERRUPTIBLE);
            wait_bit_test_parked(&actor);
            wait_bit_test_signal(&actor, 1ULL << (killable ? 8 : 14));
            wait_bit_test_join(&actor);
            assert(actor.result == -ERESTARTSYS && !waitqueue_active(__var_waitqueue(&condition)));
        }
    }
    unsigned int condition = 1;
    native_task->pending = 1ULL << 14;
    assert(!wait_var_event_interruptible(&condition, condition));
    assert(!__wait_var_event_interruptible(&condition, condition));
    native_task->pending = 1ULL << 8;
    assert(!__wait_var_event_killable(&condition, condition));
    assert(!waitqueue_active(__var_waitqueue(&condition)) && task_is_running(current));
    assert(wait_var_event_timeout(&condition, condition, 0) == 1);
    condition = 0;
    assert(!wait_var_event_timeout(&condition, condition, 0));
    native_task->pending = 0;
    /* Variable keys use bit_nr=-1 on the same table as bit waits. Find a
     * shared address/bucket to ensure the sentinel is compared, never read
     * as a bit index, and neither API consumes the other's keyed waiter. */
    unsigned long mixed_words[1024][8] = {{0}}, *mixed_word = NULL;
    int mixed_bit = -1;
    for (size_t i = 0; i < ARRAY_SIZE(mixed_words) && !mixed_word; i++) {
        for (int bit = 0; bit < 8 * BITS_PER_LONG; bit++) {
            if (bit_waitqueue(mixed_words[i], bit) == __var_waitqueue(mixed_words[i])) {
                mixed_word = mixed_words[i]; mixed_bit = bit; break;
            }
        }
    }
    assert(mixed_word && mixed_bit >= 0);
    for (unsigned int var_first = 0; var_first < 2; var_first++) {
        condition = 0;
        set_bit(mixed_bit, mixed_word);
        struct wait_bit_test_actor bit_actor = {0};
        struct wait_bit_test_actor var_actor = { .key = mixed_word, .condition = &condition };
        wait_bit_test_start(&bit_actor, WAIT_BIT_NORMAL, mixed_word, mixed_bit, TASK_UNINTERRUPTIBLE);
        wait_bit_test_parked(&bit_actor);
        wait_bit_test_start(&var_actor, WAIT_VAR_NORMAL, NULL, 0, TASK_UNINTERRUPTIBLE);
        wait_bit_test_parked(&var_actor);
        if (var_first) {
            __atomic_store_n(&condition, 1, __ATOMIC_RELEASE); smp_mb(); wake_up_var(mixed_word);
            wait_bit_test_join(&var_actor);
            assert(!vinix_linuxkpi_task_queued(&bit_actor.model));
            clear_and_wake_up_bit(mixed_bit, mixed_word);
            wait_bit_test_join(&bit_actor);
        } else {
            clear_and_wake_up_bit(mixed_bit, mixed_word);
            wait_bit_test_join(&bit_actor);
            assert(!vinix_linuxkpi_task_queued(&var_actor.model));
            __atomic_store_n(&condition, 1, __ATOMIC_RELEASE); smp_mb(); wake_up_var(mixed_word);
            wait_bit_test_join(&var_actor);
        }
        assert(!waitqueue_active(__var_waitqueue(mixed_word)));
    }
    for (unsigned int outcome = 0; outcome < 3; outcome++) {
        condition = payload = 0;
        struct wait_bit_test_actor actor = { .key = &condition, .condition = &condition,
            .timeout = 10, .payload = outcome ? &payload : NULL, .success_at_expiry = outcome == 2 };
        wait_bit_test_start(&actor, WAIT_VAR_TIMED, NULL, 0, TASK_UNINTERRUPTIBLE);
        if (outcome != 2) {
            wait_bit_test_parked(&actor);
            host_time_advance(outcome ? 4 : 10);
            if (outcome) {
                payload = 0xabc123;
                store_release_wake_up(&condition, 1);
            }
        }
        wait_bit_test_join(&actor);
        assert(actor.result == (outcome == 0 ? 0 : outcome == 1 ? 6 : 1));
        assert(!vinix_linuxkpi_time_waiters() && !waitqueue_active(__var_waitqueue(&condition)));
    }
    /* i915_active may retire the keyed object before wake_up_var(ref). The
     * address remains an opaque key; only this separately owned condition is
     * read. A dereference would fault both before and after unmapping it. */
    for (unsigned int unmap = 0; unmap < 2; unmap++) {
        void *key = mmap(NULL, 4096, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        assert(key != MAP_FAILED);
        condition = 0;
        struct wait_bit_test_actor actor = { .key = key, .condition = &condition };
        wait_bit_test_start(&actor, WAIT_VAR_NORMAL, NULL, 0, TASK_UNINTERRUPTIBLE);
        wait_bit_test_parked(&actor);
        if (unmap) assert(!munmap(key, 4096));
        __atomic_store_n(&condition, 1, __ATOMIC_RELEASE); smp_mb(); wake_up_var(key);
        wait_bit_test_join(&actor);
        assert(!waitqueue_active(__var_waitqueue(key)));
        if (!unmap) assert(!munmap(key, 4096));
    }
}
static void wait_bit_tests(void)
{
    struct native_task_model controller;
    sync_model_init(&controller, 221);
    native_task = &controller;
    size_t before = live_pages;
    assert(!fail_allocation);
    fail_allocation = true;
    wait_bit_init();
    wait_bit_test_basics();
    wait_bit_test_collisions();
    wait_bit_test_wake_quota();
    wait_bit_test_actions();
    wait_bit_test_signals();
    wait_bit_test_deadlines();
    wait_bit_test_variables();
    assert(live_pages == before && !vinix_linuxkpi_time_waiters());
    assert(task_is_running(current) && interrupts && !preempt_depth);
    fail_allocation = false;
    native_task = NULL;
    sync_model_destroy(&controller);
}

#endif
