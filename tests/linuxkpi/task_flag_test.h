/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_TASK_FLAG_TEST_H
#define VINIX_LINUXKPI_TASK_FLAG_TEST_H
#include <linux/vtime.h>

_Static_assert(PF_VCPU == 0x00000001, "Linux 6.6 guest-task flag");
_Static_assert(PF_EXITING == 0x00000004, "Linux 6.6 terminal exit flag");
_Static_assert(sizeof(struct task_struct) <= 64, "native embedded task view");
#define TASK_FLAG_TEST_SENTINEL 0x40000000U

static unsigned int task_flag_test_flags(const struct task_struct *task)
{
    return __atomic_load_n(&task->flags, __ATOMIC_RELAXED);
}

static void task_flag_test_current(void)
{
    struct native_task_model model = {
        .pid = 731, .tgid = 731, .name = "guest-task", HOST_TASK_QUEUE_INIT,
    };
    struct native_task_model child = { .pid = 732, .tgid = 731 };
    struct native_task_model *previous = native_task;
    native_task = &model;
    memset(model.storage, 0xa5, sizeof(model.storage));
    vinix_linuxkpi_task_init(model.storage, &model, model.pid, model.tgid, "initial", 7);
    struct task_struct *task = get_task_struct(current);
    assert(!task_flag_test_flags(task) && model.pins == 1);
    task->flags = TASK_FLAG_TEST_SENTINEL;
    /* These are unchanged upstream's real !VIRT_CPU_ACCOUNTING helpers. */
    assert(!vtime_accounting_enabled_this_cpu());
    vtime_account_guest_enter();
    for (unsigned int i = 0; i < 512; i++) {
        model.name = i & 1 ? "guest-new-name" : "";
        assert(current == task);
        assert(task_flag_test_flags(task) == (TASK_FLAG_TEST_SENTINEL | PF_VCPU));
        assert(!strcmp(task->comm, i & 1 ? "guest-new-name" : "initial"));
        assert(cond_resched() == 1);
        assert(vinix_linuxkpi_task_selftest() == 0);
        assert(task_flag_test_flags(current) == (TASK_FLAG_TEST_SENTINEL | PF_VCPU));
    }
    memset(child.storage, 0xa5, sizeof(child.storage));
    vinix_linuxkpi_task_inherit(child.storage, &child, child.pid, child.tgid, task);
    struct task_struct *inherited = vinix_linuxkpi_task_view(child.storage, &child,
        child.pid, child.tgid, NULL, 0, false);
    assert(!task_flag_test_flags(inherited) && !strcmp(inherited->comm, task->comm));

    model.must_exit = true;
    assert(task_flag_test_flags(current) == (TASK_FLAG_TEST_SENTINEL | PF_VCPU | PF_EXITING));
    model.must_exit = false;
    for (unsigned int i = 0; i < 32; i++) {
        assert(cond_resched() == 1);
        assert(task_flag_test_flags(current) == (TASK_FLAG_TEST_SENTINEL | PF_VCPU | PF_EXITING));
    }
    vtime_account_guest_exit();
    assert(task_flag_test_flags(current) == (TASK_FLAG_TEST_SENTINEL | PF_EXITING));
    vtime_account_guest_enter();
    __atomic_store_n(&model.dead, true, __ATOMIC_RELEASE);
    vinix_linuxkpi_task_dead(task);
    assert(__atomic_load_n(&task->__state, __ATOMIC_ACQUIRE) == TASK_DEAD);
    assert(task_flag_test_flags(task) == (TASK_FLAG_TEST_SENTINEL | PF_VCPU | PF_EXITING));
    assert(current == task && task_flag_test_flags(task) == (TASK_FLAG_TEST_SENTINEL | PF_VCPU | PF_EXITING));
    put_task_struct(task);
    assert(!model.pins);
    /* Reusing storage for a newly constructed task clears inherited/old flags. */
    __atomic_store_n(&model.dead, false, __ATOMIC_RELAXED);
    vinix_linuxkpi_task_init(model.storage, &model, model.pid, model.tgid, "reused", 6);
    assert(!task_flag_test_flags(current) && task_is_running(current));
    assert(!pthread_mutex_destroy(&model.queue_lock));
    assert(!pthread_cond_destroy(&model.queue_changed));
    native_task = previous;
}

struct task_flag_test_late_view {
    struct native_task_model model;
    unsigned int started, proceed;
};

static void *task_flag_test_late_view_worker(void *argument)
{
    struct task_flag_test_late_view *test = argument;
    __atomic_store_n(&test->started, 1, __ATOMIC_RELEASE);
    while (!__atomic_load_n(&test->proceed, __ATOMIC_ACQUIRE)) vinix_linuxkpi_spin_wait();
    for (unsigned int i = 0; i < 256; i++) {
        struct task_struct *task = vinix_linuxkpi_task_view(test->model.storage, &test->model,
            test->model.pid, test->model.tgid, "late-view", 9, false);
        assert((task_flag_test_flags(task) & TASK_FLAG_TEST_SENTINEL) == TASK_FLAG_TEST_SENTINEL);
    }
    return NULL;
}

static void task_flag_test_late_exit(void)
{
    for (unsigned int iteration = 0; iteration < 64; iteration++) {
        struct task_flag_test_late_view test = {
            .model = { .pid = 741, .tgid = 741, HOST_TASK_QUEUE_INIT },
        };
        vinix_linuxkpi_task_init(test.model.storage, &test.model, 741, 741, "initial", 7);
        struct task_struct *task = get_task_struct((void *)test.model.storage);
        task->flags = TASK_FLAG_TEST_SENTINEL | PF_VCPU;
        pthread_t worker;
        assert(!pthread_create(&worker, NULL, task_flag_test_late_view_worker, &test));
        while (!__atomic_load_n(&test.started, __ATOMIC_ACQUIRE)) vinix_linuxkpi_spin_wait();
        __atomic_store_n(&test.proceed, 1, __ATOMIC_RELEASE);
        vinix_linuxkpi_task_dead(task);
        assert(!pthread_join(worker, NULL));
        assert(__atomic_load_n(&task->__state, __ATOMIC_ACQUIRE) == TASK_DEAD);
        assert(task_flag_test_flags(task) == (TASK_FLAG_TEST_SENTINEL | PF_VCPU | PF_EXITING));
        /* Deterministically test a stale false snapshot after terminal exit. */
        assert(vinix_linuxkpi_task_view(test.model.storage, &test.model, 741, 741,
            NULL, 0, false) == task);
        assert(task_flag_test_flags(task) == (TASK_FLAG_TEST_SENTINEL | PF_VCPU | PF_EXITING));
        put_task_struct(task);
        assert(!test.model.pins);
        assert(!pthread_mutex_destroy(&test.model.queue_lock));
        assert(!pthread_cond_destroy(&test.model.queue_changed));
    }
}

struct task_flag_test_wake {
    struct task_struct *task;
    int result;
};

static void *task_flag_test_wake_worker(void *argument)
{
    struct task_flag_test_wake *test = argument;
    test->result = wake_up_process(test->task);
    assert(interrupts && !preempt_depth);
    return NULL;
}

static void task_flag_test_exit_during_wake(void)
{
    for (unsigned int iteration = 0; iteration < 64; iteration++) {
        struct native_task_model model = { .pid = 751, .tgid = 751, HOST_TASK_QUEUE_INIT };
        vinix_linuxkpi_task_init(model.storage, &model, 751, 751, "wake-exit", 9);
        struct task_struct *task = get_task_struct((void *)model.storage);
        task->flags = TASK_FLAG_TEST_SENTINEL | PF_VCPU;
        __atomic_store_n(&task->__state, TASK_UNINTERRUPTIBLE, __ATOMIC_RELAXED);
        struct task_flag_test_wake test = { .task = task, .result = -1 };
        /* Hold the real queue-admission lock. The waker first passes its
         * native alive check, publishes RUNNING, then blocks in enqueue. */
        assert(!pthread_mutex_lock(&model.queue_lock));
        pthread_t worker;
        assert(!pthread_create(&worker, NULL, task_flag_test_wake_worker, &test));
        while (__atomic_load_n(&task->__state, __ATOMIC_RELAXED) != TASK_RUNNING)
            vinix_linuxkpi_spin_wait();
        __atomic_store_n(&model.dead, true, __ATOMIC_RELEASE);
        assert(!pthread_mutex_unlock(&model.queue_lock));
        assert(!pthread_join(worker, NULL));
        assert(!test.result);
        /* No task_dead call has published Linux exit flags yet: failed wake
         * alone must provide DEAD-acquire => EXITING visibility. */
        assert(__atomic_load_n(&task->__state, __ATOMIC_ACQUIRE) == TASK_DEAD);
        assert(task_flag_test_flags(task) == (TASK_FLAG_TEST_SENTINEL | PF_VCPU | PF_EXITING));
        vinix_linuxkpi_task_dead(task);
        assert(task_flag_test_flags(task) == (TASK_FLAG_TEST_SENTINEL | PF_VCPU | PF_EXITING));
        assert(!wake_up_process(task));
        put_task_struct(task);
        assert(!model.pins);
        assert(!pthread_mutex_destroy(&model.queue_lock));
        assert(!pthread_cond_destroy(&model.queue_changed));
    }
}

static void task_flag_tests(void)
{
    size_t before = live_pages;
    bool previous_failure = fail_allocation;
    fail_allocation = true;
    task_flag_test_current();
    task_flag_test_late_exit();
    task_flag_test_exit_during_wake();
    fail_allocation = previous_failure;
    assert(live_pages == before && interrupts && !preempt_depth);
}
#endif
