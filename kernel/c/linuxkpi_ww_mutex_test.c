/* SPDX-License-Identifier: GPL-2.0-only */
#if defined(VINIX_LINUXKPI) && !defined(VINIX_LINUXKPI_HOST_TEST)
#include <linux/completion.h>
#include <linux/delay.h>
#include <linux/errno.h>
#include <linux/jiffies.h>
#include <linux/sched.h>
#include <linux/sched/task.h>
#include <linux/spinlock.h>
#include <linux/ww_mutex.h>
#include <vinix/runtime.h>
#include <pthread.h>

void vinix_linuxkpi_test_task_signal(void *thread, u64 pending);

enum native_ww_operation {
    NATIVE_WD_INVERSION, NATIVE_WW_WOUNDED, NATIVE_WW_FIRST,
    NATIVE_WW_INTERRUPT, NATIVE_WW_NULL,
};
struct native_ww_test {
    struct ww_class class;
    struct ww_mutex locks[3];
    struct completion entered, go, backed_off, done;
    struct task_struct *parent, *task;
    pthread_t thread;
    enum native_ww_operation operation;
    unsigned long stamp;
    int lock_result, result;
    bool started, use_context;
};

static int native_ww_parked(struct task_struct *task, unsigned int state)
{
    unsigned long deadline = jiffies + 500;
    while (__atomic_load_n(&task->__state, __ATOMIC_ACQUIRE) != state ||
           vinix_linuxkpi_task_queued(task->vinix_thread)) {
        if (time_after_eq(jiffies, deadline)) return -EIO;
        msleep(1);
    }
    return 0;
}

static void *native_ww_thread(void *argument)
{
    struct native_ww_test *test = argument;
    struct ww_acquire_ctx ctx;
    bool held[3] = { false, false, false };
    test->task = get_task_struct(current);
    if (test->use_context) {
        ww_acquire_init(&ctx, &test->class);
        test->stamp = ctx.stamp;
    }
    if (test->operation == NATIVE_WD_INVERSION || test->operation == NATIVE_WW_WOUNDED) {
        if (ww_mutex_lock(&test->locks[1], &ctx)) test->result = -EIO;
        else held[1] = true;
    }
    complete(&test->entered);
    wait_for_completion(&test->go);

    if (test->operation == NATIVE_WD_INVERSION) {
        /* The older task really waits on our second object before the
         * younger transaction requests its first object and must die. */
        if (native_ww_parked(test->parent, TASK_UNINTERRUPTIBLE)) test->result = -EIO;
        test->lock_result = ww_mutex_lock(&test->locks[0], &ctx);
        if (test->lock_result != -EDEADLK || ctx.acquired != 1) test->result = -EIO;
        if (!test->lock_result) held[0] = true;
        if (held[0]) { ww_mutex_unlock(&test->locks[0]); held[0] = false; }
        if (held[1]) { ww_mutex_unlock(&test->locks[1]); held[1] = false; }
        complete(&test->backed_off);
        if (test->lock_result == -EDEADLK) {
            ww_mutex_lock_slow(&test->locks[0], &ctx);
            held[0] = true;
            if (ctx.stamp != test->stamp || ctx.acquired != 1 || ctx.wounded)
                test->result = -EIO;
            if (ww_mutex_lock(&test->locks[1], &ctx)) test->result = -EIO;
            else held[1] = true;
            if (ctx.acquired != 2 || ww_mutex_lock(&test->locks[0], &ctx) != -EALREADY ||
                ww_mutex_trylock(&test->locks[0], &ctx) || ctx.acquired != 2)
                test->result = -EIO;
        }
    } else if (test->operation == NATIVE_WW_WOUNDED) {
        /* Our younger context owns object 1 while sleeping on object 2.
         * The older task wounds through object 1 and must wake this wait. */
        test->lock_result = ww_mutex_lock(&test->locks[2], &ctx);
        if (test->lock_result != -EDEADLK || !ctx.wounded || ctx.acquired != 1)
            test->result = -EIO;
        if (!test->lock_result) held[2] = true;
        if (held[2]) { ww_mutex_unlock(&test->locks[2]); held[2] = false; }
        if (held[1]) { ww_mutex_unlock(&test->locks[1]); held[1] = false; }
        complete(&test->backed_off);
        if (test->lock_result == -EDEADLK) {
            ww_mutex_lock_slow(&test->locks[2], &ctx);
            held[2] = true;
            if (ctx.stamp != test->stamp || ctx.acquired != 1 || ctx.wounded)
                test->result = -EIO;
            if (ww_mutex_lock(&test->locks[1], &ctx)) test->result = -EIO;
            else held[1] = true;
            if (ctx.acquired != 2) test->result = -EIO;
        }
    } else {
        struct ww_acquire_ctx *context = test->use_context ? &ctx : NULL;
        if (test->operation == NATIVE_WW_INTERRUPT)
            test->lock_result = ww_mutex_lock_interruptible(&test->locks[0], context);
        else test->lock_result = ww_mutex_lock(&test->locks[0], context);
        if (!test->lock_result) held[0] = true;
        if (test->operation == NATIVE_WW_INTERRUPT) {
            vinix_linuxkpi_test_task_signal(test->task->vinix_thread, 0);
            if (test->lock_result != -EINTR || (context && ctx.acquired))
                test->result = -EIO;
        } else if (test->lock_result || (context && ctx.acquired != 1) ||
                   READ_ONCE(test->locks[0].ctx) != context) test->result = -EIO;
    }
    for (unsigned int i = 0; i < ARRAY_SIZE(held); i++)
        if (held[i]) ww_mutex_unlock(&test->locks[i]);
    if (test->use_context) {
        if (ctx.acquired) test->result = -EIO;
        ww_acquire_fini(&ctx);
    }
    if (!task_is_running(current) || !vinix_linuxkpi_may_sleep()) test->result = -EIO;
    complete(&test->done);
    pthread_exit(NULL);
    return NULL;
}

static void native_ww_init(struct native_ww_test *test, bool wait_die,
                           enum native_ww_operation operation, bool use_context)
{
    *test = (struct native_ww_test){ .operation = operation, .use_context = use_context };
    test->class = (struct ww_class)__WW_CLASS_INITIALIZER(native_ww_test, 0);
    test->class.is_wait_die = wait_die;
    for (unsigned int i = 0; i < ARRAY_SIZE(test->locks); i++)
        ww_mutex_init(&test->locks[i], &test->class);
    init_completion(&test->entered);
    init_completion(&test->go);
    init_completion(&test->backed_off);
    init_completion(&test->done);
    test->parent = get_task_struct(current);
}

static int native_ww_start(struct native_ww_test *test)
{
    if (pthread_create(&test->thread, NULL, native_ww_thread, test)) return -ENOMEM;
    test->started = true;
    return wait_for_completion_timeout(&test->entered, 500) ? 0 : -EIO;
}

static int native_ww_finish(struct native_ww_test *test)
{
    int result = 0;
    if (test->started) {
        /* All parent locks and gates must be released before joining. */
        complete_all(&test->go);
        BUG_ON(pthread_join(test->thread, NULL));
        result = test->result;
        while (__atomic_load_n(&test->task->__state, __ATOMIC_ACQUIRE) != TASK_DEAD)
            cond_resched();
        put_task_struct(test->task);
    }
    put_task_struct(test->parent);
    for (unsigned int i = 0; i < ARRAY_SIZE(test->locks); i++) {
        if (ww_mutex_is_locked(&test->locks[i]) || READ_ONCE(test->locks[i].ctx) ||
            !list_empty(&test->locks[i].base.wait_list)) result = -EIO;
        ww_mutex_destroy(&test->locks[i]);
    }
    return result;
}

static int native_ww_inversion(bool wait_die, bool wrap)
{
    struct native_ww_test test;
    struct ww_acquire_ctx ctx;
    bool held[3] = { false, false, false };
    int result = 0;
    native_ww_init(&test, wait_die,
                   wait_die ? NATIVE_WD_INVERSION : NATIVE_WW_WOUNDED, true);
    if (wrap) atomic_long_set(&test.class.stamp, -2);
    ww_acquire_init(&ctx, &test.class);
    unsigned long stamp = ctx.stamp;
    if (ww_mutex_lock(&test.locks[0], &ctx)) { result = -EIO; goto out; }
    held[0] = true;
    if (!wait_die) {
        if (ww_mutex_lock(&test.locks[2], &ctx)) { result = -EIO; goto out; }
        held[2] = true;
    }
    if (native_ww_start(&test)) { result = -EIO; goto out; }
    if ((long)(test.stamp - stamp) <= 0) result = -EIO;
    complete(&test.go);
    if (!wait_die && native_ww_parked(test.task, TASK_UNINTERRUPTIBLE)) result = -EIO;
    if (ww_mutex_lock(&test.locks[1], &ctx)) { result = -EIO; goto out; }
    held[1] = true;
    if (!wait_for_completion_timeout(&test.backed_off, 500) ||
        test.lock_result != -EDEADLK || ctx.stamp != stamp ||
        ctx.acquired != (wait_die ? 2U : 3U)) result = -EIO;
    ww_acquire_done(&ctx);
out:
    /* Drop every owned object before the younger context's slow retry can
     * finish, retaining its original stamp and the fixture through join. */
    /* Release the original contending object last. Otherwise Wait-Die's
     * slow retry could immediately die again on our still-held object 1. */
    if (held[1]) ww_mutex_unlock(&test.locks[1]);
    if (held[0]) ww_mutex_unlock(&test.locks[0]);
    if (held[2]) ww_mutex_unlock(&test.locks[2]);
    if (ctx.acquired) result = -EIO;
    ww_acquire_fini(&ctx);
    if (native_ww_finish(&test)) result = -EIO;
    return result;
}

static int native_ww_first(bool wait_die)
{
    struct native_ww_test test;
    struct ww_acquire_ctx ctx;
    bool held = false;
    int result = 0;
    native_ww_init(&test, wait_die, NATIVE_WW_FIRST, true);
    /* Wait-Die: younger first-lock waiter behind an older holder cannot die.
     * Wound-Wait: an older first-lock waiter cannot wound a younger holder. */
    if (wait_die) ww_acquire_init(&ctx, &test.class);
    if (native_ww_start(&test)) {
        if (!wait_die) ww_acquire_init(&ctx, &test.class);
        result = -EIO;
        goto out;
    }
    if (!wait_die) ww_acquire_init(&ctx, &test.class);
    long age = (long)(test.stamp - ctx.stamp);
    if (wait_die ? age <= 0 : age >= 0) result = -EIO;
    if (ww_mutex_lock(&test.locks[0], &ctx)) { result = -EIO; goto out; }
    held = true;
    complete(&test.go);
    if (native_ww_parked(test.task, TASK_UNINTERRUPTIBLE) || completion_done(&test.done) ||
        __atomic_load_n(&ctx.wounded, __ATOMIC_ACQUIRE)) result = -EIO;
out:
    if (held) ww_mutex_unlock(&test.locks[0]);
    if (ctx.acquired) result = -EIO;
    ww_acquire_fini(&ctx);
    if (native_ww_finish(&test)) result = -EIO;
    return result;
}

static int native_ww_single(bool interruptible, bool use_context)
{
    struct native_ww_test test;
    int result = 0;
    bool held = false;
    native_ww_init(&test, true,
                   interruptible ? NATIVE_WW_INTERRUPT : NATIVE_WW_NULL, use_context);
    if (ww_mutex_lock(&test.locks[0], NULL)) { result = -EIO; goto out; }
    held = true;
    if (native_ww_start(&test)) { result = -EIO; goto out; }
    complete(&test.go);
    unsigned int state = interruptible ? TASK_INTERRUPTIBLE : TASK_UNINTERRUPTIBLE;
    if (native_ww_parked(test.task, state) || completion_done(&test.done)) result = -EIO;
    if (interruptible) {
        vinix_linuxkpi_test_task_signal(test.task->vinix_thread, 1ULL << 14);
        if (!wait_for_completion_timeout(&test.done, 500) || test.lock_result != -EINTR)
            result = -EIO;
        /* The owner remains held while the interrupted waiter's stack can
         * retire. Cancellation must remove it without transferring owner. */
        unsigned long flags;
        raw_spin_lock_irqsave(&test.locks[0].base.wait_lock, flags);
        if (!list_empty(&test.locks[0].base.wait_list) ||
            atomic_long_read(&test.locks[0].base.owner) != (long)current)
            result = -EIO;
        raw_spin_unlock_irqrestore(&test.locks[0].base.wait_lock, flags);
    }
out:
    if (held) ww_mutex_unlock(&test.locks[0]);
    if (native_ww_finish(&test)) result = -EIO;
    return result;
}

static int native_ww_repeated(void)
{
    struct ww_class class = __WW_CLASS_INITIALIZER(native_ww_repeated, 1);
    struct ww_mutex a, b;
    int result = 0;
    ww_mutex_init(&a, &class);
    ww_mutex_init(&b, &class);
    for (unsigned int i = 0; i < 256; i++) {
        struct ww_acquire_ctx ctx;
        ww_acquire_init(&ctx, &class);
        if (ww_mutex_lock(&a, &ctx)) { result = -EIO; ww_acquire_fini(&ctx); break; }
        if (ctx.acquired != 1 || ww_mutex_lock(&a, &ctx) != -EALREADY ||
            ww_mutex_trylock(&a, &ctx) || ctx.acquired != 1) result = -EIO;
        if (!ww_mutex_trylock(&b, &ctx)) result = -EIO;
        else {
            if (ctx.acquired != 2 || a.ctx != &ctx || b.ctx != &ctx) result = -EIO;
            ww_acquire_done(&ctx);
            ww_mutex_unlock(&b);
        }
        ww_mutex_unlock(&a);
        if (ctx.acquired) result = -EIO;
        ww_acquire_fini(&ctx);
        if (ww_mutex_lock(&a, NULL)) result = -EIO;
        else {
            if (a.ctx || ww_mutex_trylock(&a, NULL)) result = -EIO;
            ww_mutex_unlock(&a);
        }
        if (!vinix_linuxkpi_may_sleep()) result = -EIO;
    }
    ww_mutex_destroy(&a);
    ww_mutex_destroy(&b);
    return result;
}

int vinix_linuxkpi_ww_mutex_native_selftest(void)
{
    extern int kprintf(const char *, ...);
    int result = 0;
    if (native_ww_repeated()) { kprintf("linuxkpi: WW repeated/context counts failed\n"); result = -EIO; }
    if (native_ww_inversion(true, false)) { kprintf("linuxkpi: Wait-Die inversion failed\n"); result = -EIO; }
    if (native_ww_inversion(true, true)) { kprintf("linuxkpi: Wait-Die wrapped stamp failed\n"); result = -EIO; }
    if (native_ww_inversion(false, false)) { kprintf("linuxkpi: Wound-Wait cross-lock wake failed\n"); result = -EIO; }
    if (native_ww_first(true)) { kprintf("linuxkpi: Wait-Die first-lock exemption failed\n"); result = -EIO; }
    if (native_ww_first(false)) { kprintf("linuxkpi: Wound-Wait first-lock exemption failed\n"); result = -EIO; }
    if (native_ww_single(true, true)) { kprintf("linuxkpi: WW context signal abort failed\n"); result = -EIO; }
    if (native_ww_single(true, false)) { kprintf("linuxkpi: WW context-free signal abort failed\n"); result = -EIO; }
    if (native_ww_single(false, false)) { kprintf("linuxkpi: WW context-free handoff failed\n"); result = -EIO; }
    return result;
}
#endif
