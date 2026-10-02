/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>
#include <asm/unaligned.h>
#include <linux/atomic.h>
#include <linux/err.h>
#include <linux/errno.h>
#include <linux/kernel.h>
#include <linux/kref.h>
#include <linux/bits.h>
#include <linux/bitmap.h>
#include <linux/percpu.h>
#include <linux/sched.h>
#include <linux/sched/signal.h>
#include <linux/sched/task.h>
#include <linux/smp.h>
#include <linux/list.h>
#include <linux/list_sort.h>
#include <linux/rbtree_augmented.h>
#include <linux/slab.h>
#include <linux/spinlock.h>
#include <linux/string.h>
#include <vinix/runtime.h>

static size_t live_pages;
static size_t permanent_pages;
static bool fail_allocation;
static int allocation_failure_after = -1;
static int worker_bind_failure_after = -1;
static unsigned int worker_bind_failures;
static bool last_reclaim;
static _Thread_local bool interrupts = true;
static _Thread_local unsigned int preempt_depth;
static _Thread_local unsigned int current_cpu;
static _Thread_local int current_worker_nice;
static _Thread_local void (*host_irq_restore_hook)(void);
static _Thread_local unsigned int *timer_sync_spins;
static atomic_t refcount_warnings = ATOMIC_INIT(0);
static atomic_t time_warnings = ATOMIC_INIT(0);
static u64 host_clock_ns;
u64 vinix_linuxkpi_clock_ns(void) { return __atomic_load_n(&host_clock_ns, __ATOMIC_ACQUIRE); }
u32 vinix_linuxkpi_clock_resolution_ns(void) { return 1000000; }
void vinix_linuxkpi_warn(const char *file, int line) { atomic_inc(&time_warnings); }
struct native_task_model {
    u64 storage[8];
    int pid, tgid;
    const char *name;
    u64 pending, masked;
    bool must_exit, exiting;
    unsigned int yields;
    unsigned int pins;
    bool dead, queued;
    unsigned int iowait_cpu_plus_one;
    bool reject_enqueue;
    bool heap_owned;
    pthread_mutex_t queue_lock;
    pthread_cond_t queue_changed;
    unsigned int iteration, dequeued, parked;
};
static _Thread_local struct native_task_model *native_task;
static _Thread_local bool resched_pending;

#define HOST_TASK_QUEUE_INIT .queued = true, .queue_lock = PTHREAD_MUTEX_INITIALIZER, \
                             .queue_changed = PTHREAD_COND_INITIALIZER

void vinix_linuxkpi_task_get(void *thread)
{
    struct native_task_model *task = thread;
    __atomic_fetch_add(&task->pins, 1, __ATOMIC_RELAXED);
}
void vinix_linuxkpi_task_put(void *thread)
{
    struct native_task_model *task = thread;
    unsigned int pins = __atomic_fetch_sub(&task->pins, 1, __ATOMIC_ACQ_REL);
    assert(pins != 0);
    if (pins == 1 && task->heap_owned && __atomic_load_n(&task->dead, __ATOMIC_ACQUIRE)) {
        assert(!pthread_mutex_destroy(&task->queue_lock));
        assert(!pthread_cond_destroy(&task->queue_changed));
        free(task);
    }
}
bool vinix_linuxkpi_task_is_dead(const void *thread)
{
    return __atomic_load_n(&((const struct native_task_model *)thread)->dead, __ATOMIC_ACQUIRE);
}
bool vinix_linuxkpi_task_queued(const void *thread)
{
    struct native_task_model *task = (void *)thread;
    assert(!pthread_mutex_lock(&task->queue_lock));
    bool queued = task->queued;
    assert(!pthread_mutex_unlock(&task->queue_lock));
    return queued;
}
static void host_iowait_end_locked(struct native_task_model *task);
bool vinix_linuxkpi_task_enqueue(void *thread)
{
    struct native_task_model *task = thread;
    assert(!pthread_mutex_lock(&task->queue_lock));
    bool alive = !vinix_linuxkpi_task_is_dead(task) && !task->reject_enqueue;
    if (alive) {
        host_iowait_end_locked(task);
        task->queued = true;
        assert(!pthread_cond_signal(&task->queue_changed));
    }
    assert(!pthread_mutex_unlock(&task->queue_lock));
    return alive;
}
void vinix_linuxkpi_task_dequeue(void *thread)
{
    struct native_task_model *task = thread;
    assert(task == native_task && !pthread_mutex_lock(&task->queue_lock));
    task->queued = false;
    if (vinix_linuxkpi_task_is_dead(task)) host_iowait_end_locked(task);
    __atomic_store_n(&task->dequeued, task->iteration, __ATOMIC_RELEASE);
    assert(!pthread_mutex_unlock(&task->queue_lock));
}
void vinix_linuxkpi_task_park(void)
{
    struct native_task_model *task = native_task;
    assert(task && vinix_linuxkpi_may_sleep());
    __atomic_store_n(&task->parked, task->iteration, __ATOMIC_RELEASE);
    vinix_linuxkpi_workqueue_task_sleep(task->storage);
    assert(!pthread_mutex_lock(&task->queue_lock));
    while (!task->queued) assert(!pthread_cond_wait(&task->queue_changed, &task->queue_lock));
    assert(!pthread_mutex_unlock(&task->queue_lock));
    vinix_linuxkpi_workqueue_task_resume(task->storage);
}

struct task_struct *vinix_linuxkpi_current_task(void)
{
    assert(native_task);
    return vinix_linuxkpi_task_view(native_task->storage, native_task, native_task->pid,
        native_task->tgid, native_task->name, strlen(native_task->name),
        native_task->must_exit || native_task->exiting);
}
bool vinix_linuxkpi_task_signal_pending(const void *thread, bool fatal)
{
    const struct native_task_model *task = thread;
    u64 pending = __atomic_load_n(&task->pending, __ATOMIC_RELAXED);
    if (task->must_exit || (pending & (1ULL << 8))) return true;
    return !fatal && (pending & ~task->masked);
}
bool vinix_linuxkpi_need_resched(void) { return resched_pending; }
int vinix_linuxkpi_cond_resched(void)
{
    if (!vinix_linuxkpi_may_sleep()) return 0;
    assert(native_task);
    native_task->yields++;
    resched_pending = false;
    return 1;
}

static void *task_worker(void *argument)
{
    unsigned int index = *(unsigned int *)argument;
    struct native_task_model model = { .pid = 100 + index, .tgid = 100,
        .name = "long-task-name-needs-truncation", HOST_TASK_QUEUE_INIT };
    native_task = &model;
    current_cpu = index;
    char initial_name[] = "initial-name";
    vinix_linuxkpi_task_init(model.storage, &model, model.pid, model.tgid, initial_name, 12);
    memset(initial_name, 'x', sizeof(initial_name));
    struct task_struct *task = current;
    assert(get_task_struct(task) == task && model.pins == 1);
    put_task_struct(task);
    assert(!model.pins && task_is_running(task));
    assert(task_pid_nr(task) == model.pid && task_tgid_nr(task) == 100);
    assert(!strcmp(task->comm, "long-task-name-") && !task->flags);
    for (unsigned int i = 0; i < 1000; i++) {
        assert(vinix_linuxkpi_task_selftest() == 0);
        current_cpu = (current_cpu + 1) % 4;
        assert(current == task && task_pid_nr(task) == model.pid);
    }
    model.name = "short";
    assert(!strcmp(current->comm, "short") && !memchr_inv(task->comm + 5, 0, TASK_COMM_LEN - 5));
    struct native_task_model child = { .pid = 200 + index, .tgid = 200 };
    vinix_linuxkpi_task_inherit(child.storage, &child, child.pid, child.tgid, task);
    struct task_struct *child_view = vinix_linuxkpi_task_view(child.storage, &child,
        child.pid, child.tgid, NULL, 0, false);
    assert(!strcmp(child_view->comm, "short") && child_view != task);
    model.name = "";
    assert(!strcmp(current->comm, "initial-name"));
    assert(!signal_pending(task) && !fatal_signal_pending(task));
    model.pending = 1ULL << 14; /* SIGTERM */
    assert(signal_pending(task) && !fatal_signal_pending(task));
    set_current_state(TASK_INTERRUPTIBLE);
    schedule();
    assert(task_is_running(task) && vinix_linuxkpi_task_queued(&model));
    set_current_state(TASK_KILLABLE);
    assert(!signal_pending_state(TASK_KILLABLE, task));
    __set_current_state(TASK_RUNNING);
    model.masked = model.pending;
    assert(!signal_pending(task) && !fatal_signal_pending(task));
    model.pending |= 1ULL << 8; /* SIGKILL */
    assert(signal_pending(task) && fatal_signal_pending(task));
    set_current_state(TASK_KILLABLE);
    schedule();
    assert(task_is_running(task) && vinix_linuxkpi_task_queued(&model));
    model.pending = model.masked = 0;
    model.must_exit = true;
    assert(signal_pending(task) && fatal_signal_pending(task) && (current->flags & PF_EXITING));
    model.must_exit = false;
    model.exiting = true;
    assert(current->flags & PF_EXITING);
    model.exiting = false;
    assert(current->flags == PF_EXITING);
    resched_pending = true;
    preempt_disable();
    assert(need_resched() && !cond_resched() && need_resched());
    preempt_enable_no_resched();
    assert(need_resched() && cond_resched() == 1 && !need_resched());
    assert(preempt_depth == 0 && interrupts && model.yields == 1001);
    assert(!pthread_mutex_destroy(&model.queue_lock) && !pthread_cond_destroy(&model.queue_changed));
    native_task = NULL;
    return NULL;
}

struct wait_worker_test {
    struct native_task_model model;
    struct task_struct *task;
    unsigned int armed, proceed, completed;
};

static void *wait_worker(void *argument)
{
    struct wait_worker_test *test = argument;
    native_task = &test->model;
    struct task_struct *task = current;
    test->task = get_task_struct(task);
    for (unsigned int i = 1; i <= 1000; i++) {
        test->model.iteration = i;
        static const unsigned int states[] = {
            TASK_INTERRUPTIBLE, TASK_UNINTERRUPTIBLE, TASK_KILLABLE, TASK_IDLE
        };
        set_current_state(states[i % ARRAY_SIZE(states)]);
        __atomic_store_n(&test->armed, i, __ATOMIC_RELEASE);
        if (i % 3 == 0)
            while (__atomic_load_n(&test->proceed, __ATOMIC_ACQUIRE) < i) vinix_linuxkpi_spin_wait();
        schedule();
        assert(task_is_running(task) && vinix_linuxkpi_task_queued(native_task));
        __atomic_store_n(&test->completed, i, __ATOMIC_RELEASE);
    }
    __atomic_store_n(&test->model.dead, true, __ATOMIC_RELEASE);
    vinix_linuxkpi_task_dead(test->model.storage);
    native_task = NULL;
    return NULL;
}

static void task_wait_tests(void)
{
    struct wait_worker_test test = { .model = {
        .pid = 123, .tgid = 123, .name = "waiter", HOST_TASK_QUEUE_INIT
    }};
    vinix_linuxkpi_task_init(test.model.storage, &test.model, 123, 123, "waiter", 6);
    pthread_t thread;
    assert(!pthread_create(&thread, NULL, wait_worker, &test));
    for (unsigned int i = 1; i <= 1000; i++) {
        while (__atomic_load_n(&test.armed, __ATOMIC_ACQUIRE) < i) vinix_linuxkpi_spin_wait();
        if (i % 3 == 1)
            while (__atomic_load_n(&test.model.dequeued, __ATOMIC_ACQUIRE) < i) vinix_linuxkpi_spin_wait();
        if (i % 3 == 2)
            while (__atomic_load_n(&test.model.parked, __ATOMIC_ACQUIRE) < i) vinix_linuxkpi_spin_wait();
        if (i % 4 != 0) assert(!wake_up_state(test.task, TASK_INTERRUPTIBLE));
        if (i % 3 != 0 && i % 4 != 0) {
            /* Vinix's signal delivery uses native enqueue regardless of the
             * Linux state. SIGTERM cannot end these three wait modes. */
            __atomic_store_n(&test.model.pending, 1ULL << 14, __ATOMIC_RELAXED);
            assert(vinix_linuxkpi_task_enqueue(&test.model));
            while (vinix_linuxkpi_task_queued(&test.model)) vinix_linuxkpi_spin_wait();
            assert(__atomic_load_n(&test.completed, __ATOMIC_ACQUIRE) < i);
            assert(!task_is_running(test.task));
            __atomic_store_n(&test.model.pending, 0, __ATOMIC_RELAXED);
        }
        if (i % 4 == 2) assert(wake_up_state(test.task, TASK_WAKEKILL) == 1);
        else if (i % 4 == 3) assert(wake_up_state(test.task, TASK_NOLOAD) == 1);
        else assert(wake_up_process(test.task) == 1);
        /* In the early-wake case, hold the worker until the wake has finished. */
        if (i % 3 == 0) __atomic_store_n(&test.proceed, i, __ATOMIC_RELEASE);
        while (__atomic_load_n(&test.completed, __ATOMIC_ACQUIRE) < i) vinix_linuxkpi_spin_wait();
    }
    assert(!pthread_join(thread, NULL));
    assert(test.model.pins == 1 && task_is_running(test.task) == false);
    assert(test.task->__state == TASK_DEAD && (test.task->flags & PF_EXITING));
    assert(!wake_up_process(test.task) && !vinix_linuxkpi_task_enqueue(&test.model));
    put_task_struct(test.task);
    assert(!test.model.pins);
    assert(!pthread_mutex_destroy(&test.model.queue_lock) && !pthread_cond_destroy(&test.model.queue_changed));
}

static void task_tests(void)
{
    pthread_t threads[4];
    unsigned int indexes[4] = {0, 1, 2, 3};
    for (unsigned int i = 0; i < 4; i++) assert(!pthread_create(&threads[i], NULL, task_worker, &indexes[i]));
    for (unsigned int i = 0; i < 4; i++) assert(!pthread_join(threads[i], NULL));
    assert(live_pages == permanent_pages);
}

void *vinix_linuxkpi_alloc_pages(size_t pages, bool reclaim)
{
    __atomic_store_n(&last_reclaim, reclaim, __ATOMIC_RELAXED);
    if (fail_allocation) return NULL;
    int remaining = __atomic_load_n(&allocation_failure_after, __ATOMIC_RELAXED);
    while (remaining >= 0) {
        if (!remaining) return NULL;
        if (__atomic_compare_exchange_n(&allocation_failure_after, &remaining,
                remaining - 1, false, __ATOMIC_RELAXED, __ATOMIC_RELAXED)) break;
    }
    void *ptr = NULL;
    if (posix_memalign(&ptr, 4096, pages * 4096)) return NULL;
    memset(ptr, 0xa5, pages * 4096);
    __atomic_fetch_add(&live_pages, pages, __ATOMIC_RELAXED);
    return ptr;
}

void vinix_linuxkpi_free_pages(void *base, size_t pages)
{
    assert(__atomic_fetch_sub(&live_pages, pages, __ATOMIC_RELAXED) >= pages);
    free(base);
}

size_t vinix_linuxkpi_page_size(void) { return 4096; }
void vinix_linuxkpi_bug(const char *file, int line)
{
    fprintf(stderr, "Linux compatibility BUG at %s:%d\n", file, line);
    abort();
}

unsigned long vinix_linuxkpi_irq_save(void)
{
    unsigned long flags = interrupts ? 1UL << 9 : 0;
    interrupts = false;
    return flags;
}

void vinix_linuxkpi_irq_restore(unsigned long flags)
{
    interrupts = !!(flags & (1UL << 9));
    if (interrupts && host_irq_restore_hook) {
        void (*hook)(void) = host_irq_restore_hook;
        host_irq_restore_hook = NULL;
        hook();
    }
}
unsigned long vinix_linuxkpi_irq_flags(void) { return interrupts ? 1UL << 9 : 0; }
void vinix_linuxkpi_spin_wait(void)
{
    if (timer_sync_spins) __atomic_fetch_add(timer_sync_spins, 1, __ATOMIC_RELEASE);
    __asm__ volatile("" ::: "memory");
}
void vinix_linuxkpi_preempt_disable(void) { preempt_depth++; }
void vinix_linuxkpi_preempt_enable(void) { assert(preempt_depth); preempt_depth--; }
void vinix_linuxkpi_preempt_enable_no_resched(void) { assert(preempt_depth); preempt_depth--; }
unsigned int vinix_linuxkpi_preempt_count(void) { return preempt_depth; }
void vinix_linuxkpi_preempt_check_resched(void) { }
unsigned int vinix_linuxkpi_cpu_id(void) { return current_cpu; }
int vinix_linuxkpi_worker_bind(unsigned int cpu)
{
    if (!vinix_linuxkpi_may_sleep()) return -EWOULDBLOCK;
    if (cpu >= vinix_linuxkpi_percpu_count() || cpu >= 64) return -EINVAL;
    int remaining = __atomic_load_n(&worker_bind_failure_after, __ATOMIC_RELAXED);
    while (remaining >= 0) {
        if (!remaining) {
            __atomic_fetch_add(&worker_bind_failures, 1, __ATOMIC_RELEASE);
            return -EIO;
        }
        if (__atomic_compare_exchange_n(&worker_bind_failure_after, &remaining,
                remaining - 1, false, __ATOMIC_RELAXED, __ATOMIC_RELAXED)) break;
    }
    current_cpu = cpu;
    return 0;
}
bool vinix_linuxkpi_may_sleep(void) { return interrupts && !preempt_depth; }
int vinix_linuxkpi_worker_set_nice(int nice)
{
    if (!vinix_linuxkpi_may_sleep()) return -EWOULDBLOCK;
    if (nice < -20 || nice > 19) return -EINVAL;
    current_worker_nice = nice;
    return 0;
}
int vinix_linuxkpi_worker_nice(void) { return current_worker_nice; }
u64 vinix_linuxkpi_worker_timeslice(void) { return 5000 * (20 - current_worker_nice) / 20; }
void vinix_linuxkpi_refcount_warning(int kind)
{
    assert(kind >= REFCOUNT_ADD_NOT_ZERO_OVF && kind <= REFCOUNT_DEC_LEAK);
    atomic_inc(&refcount_warnings);
}

static void allocation_tests(void)
{
    assert(type_max(s8) == 127 && type_max(u8) == 255);
    assert(type_max(s64) == 0x7fffffffffffffffLL && type_max(u64) == ~0ULL);
    assert(GENMASK_ULL(39, 21) == 0x000000ffffe00000ULL);
    assert(vinix_linuxkpi_selftest() == 0);
    assert(live_pages == permanent_pages);
    assert(kmalloc(0, GFP_KERNEL) == ZERO_SIZE_PTR);
    assert(ksize(ZERO_SIZE_PTR) == 0);
    kfree(NULL);
    kfree(ZERO_SIZE_PTR);
    assert(kmalloc(SIZE_MAX, GFP_KERNEL) == NULL);
    assert(kmalloc_array(SIZE_MAX, 2, GFP_KERNEL) == NULL);
    assert(kcalloc(2, SIZE_MAX, GFP_KERNEL) == NULL);
    const gfp_t non_reclaiming[] = { GFP_ATOMIC, GFP_NOWAIT, GFP_NOFS, GFP_NOIO };
    for (size_t i = 0; i < ARRAY_SIZE(non_reclaiming); i++) {
        void *ptr = kmalloc(32, non_reclaiming[i]);
        assert(ptr && !last_reclaim);
        kfree(ptr);
    }
    interrupts = false;
    void *atomic_ptr = kmalloc(32, GFP_KERNEL);
    assert(atomic_ptr && !last_reclaim);
    kfree(atomic_ptr);
    interrupts = true;
    assert(kmalloc(32, GFP_KERNEL | __GFP_DMA32) == NULL);
    assert(kmalloc(32, GFP_KERNEL | __GFP_NOFAIL) == NULL);
    assert(kmalloc(32, GFP_KERNEL | __GFP_ACCOUNT) == NULL);
    for (size_t n = 16; n <= 16384; n *= 2) {
        void *ptr = kmalloc(n, GFP_KERNEL);
        assert(ptr && (uintptr_t)ptr % n == 0 && last_reclaim);
        kfree(ptr);
    }
    for (size_t n = 1; n < 25000; n = n * 2 + 1) {
        unsigned char *ptr = kcalloc(n, 1, GFP_KERNEL);
        assert(ptr && (uintptr_t)ptr % 16 == 0 && ksize(ptr) == n);
        for (size_t i = 0; i < n; i++) assert(ptr[i] == 0);
        memset(ptr, 0x6f, n);
        fail_allocation = true;
        assert(krealloc(ptr, n + 17, GFP_KERNEL) == NULL);
        for (size_t i = 0; i < n; i++) assert(ptr[i] == 0x6f);
        fail_allocation = false;
        unsigned char *grown = krealloc(ptr, n + 17, GFP_KERNEL | __GFP_ZERO);
        assert(grown && ksize(grown) == n + 17);
        for (size_t i = 0; i < n + 17; i++) assert(grown[i] == (i < n ? 0x6f : 0));
        unsigned char *duplicate = kmemdup(grown, n + 17, GFP_KERNEL);
        assert(duplicate && !memcmp(duplicate, grown, n + 17));
        kfree(duplicate);
        assert(krealloc(grown, 0, GFP_KERNEL) == ZERO_SIZE_PTR);
        assert(live_pages == permanent_pages);
    }
    assert(PTR_ERR(ERR_PTR(-ENOMEM)) == -ENOMEM);
    assert(IS_ERR(ERR_PTR(-ENOMEM)) && IS_ERR_OR_NULL(NULL));
    assert(!IS_ERR((void *)4096) && PTR_ERR_OR_ZERO((void *)4096) == 0);
}

#ifdef __APPLE__
extern const unsigned char host_percpu_start[] __asm__("section$start$__DATA$vinixpcpu");
extern const unsigned char host_percpu_end[] __asm__("section$end$__DATA$vinixpcpu");
#else
extern const unsigned char __start_vinixpcpu[], __stop_vinixpcpu[];
#define host_percpu_start __start_vinixpcpu
#define host_percpu_end __stop_vinixpcpu
#endif
void vinix_linuxkpi_percpu_destroy_for_test(void);
static DEFINE_PER_CPU(u8, cpu_byte) = 0x37;
static DEFINE_PER_CPU(u16, cpu_half) = 0x1234;
static DEFINE_PER_CPU(u32, cpu_word) = 0x12345678;
static DEFINE_PER_CPU(u64, cpu_wide) = 0x123456789abcdef0ULL;
struct cpu_record { unsigned long counter; unsigned char bytes[15]; } __aligned(64);
static DEFINE_PER_CPU_ALIGNED(struct cpu_record, cpu_record) = { .counter = 17, .bytes = { 1, 2, 3 } };

struct cpu_worker { unsigned int cpu; struct cpu_record *dynamic; };

static void *percpu_worker(void *argument)
{
    struct cpu_worker *worker = argument;
    current_cpu = worker->cpu;
    assert(preemptible() && preempt_count() == 0);
    assert(this_cpu_read(cpu_byte) == 0x37 && this_cpu_read(cpu_half) == 0x1234);
    assert(this_cpu_read(cpu_word) == 0x12345678);
    assert(this_cpu_read(cpu_wide) == 0x123456789abcdef0ULL);
    unsigned long *pinned = get_cpu_ptr(&cpu_record.counter);
    assert(preempt_count() == 1 && !preemptible() && *pinned == 17);
    preempt_disable();
    assert(preempt_count() == 2);
    preempt_enable_no_resched();
    assert(preempt_count() == 1);
    put_cpu_ptr(pinned);
    assert(preemptible());
    for (unsigned int i = 0; i < 20000; i++) {
        this_cpu_inc(cpu_wide);
        this_cpu_add(cpu_record.counter, 3);
        this_cpu_inc(worker->dynamic->counter);
        this_cpu_write(cpu_byte, (u8)i);
        assert(preempt_count() == 0 && interrupts);
    }
    u32 expected = 0;
    assert(!this_cpu_try_cmpxchg(cpu_word, &expected, 1) && expected == 0x12345678);
    assert(this_cpu_try_cmpxchg(cpu_word, &expected, worker->cpu + 1));
    assert(this_cpu_xchg(cpu_half, 7) == 0x1234 && this_cpu_read_stable(cpu_half) == 7);
    get_cpu_var(cpu_half) = 9;
    assert(preempt_count() == 1);
    put_cpu_var(cpu_half);
    unsigned long flags;
    local_irq_save(flags);
    this_cpu_or(cpu_byte, 0x80);
    assert(irqs_disabled() && preempt_count() == 0);
    local_irq_restore(flags);
    preempt_disable();
    this_cpu_ptr(&worker->dynamic->bytes[3])[0] = (unsigned char)(worker->cpu + 1);
    preempt_enable();
    return NULL;
}

static void percpu_tests(void)
{
    assert(vinix_linuxkpi_percpu_init(4, host_percpu_start, host_percpu_end) == -EBUSY);
    assert(!__alloc_percpu(0, 8) && !__alloc_percpu(8, 0) && !__alloc_percpu(8, 3));
    assert(!__alloc_percpu(8, 8192) && !__alloc_percpu(SIZE_MAX, 8));
    assert(!__alloc_percpu(SIZE_MAX / 2, 8));
    assert(!__alloc_percpu_gfp(8, 8, GFP_KERNEL | __GFP_DMA32));
    fail_allocation = true;
    assert(!alloc_percpu(struct cpu_record));
    fail_allocation = false;
    free_percpu(NULL);
    assert(!per_cpu_ptr((u8 *)NULL, 0));
    for (size_t align = 1; align <= 4096; align *= 2) {
        unsigned char *buffer = __alloc_percpu_gfp(align + 1, align, GFP_ATOMIC);
        assert(buffer && !last_reclaim);
        for (unsigned int cpu = 0; cpu < 4; cpu++) {
            unsigned char *slot = per_cpu_ptr(buffer, cpu);
            assert((uintptr_t)slot % align == 0 && !memchr_inv(slot, 0, align + 1));
            memset(slot, cpu + 1, align + 1);
        }
        for (unsigned int cpu = 0; cpu < 4; cpu++) {
            assert(!memchr_inv(per_cpu_ptr(buffer, cpu), cpu + 1, align + 1));
        }
        free_percpu(buffer);
    }
    struct cpu_record *dynamic = alloc_percpu(struct cpu_record);
    assert(dynamic);
    struct cpu_worker workers[4];
    pthread_t threads[4];
    for (unsigned int cpu = 0; cpu < 4; cpu++) {
        assert((uintptr_t)per_cpu_ptr(&cpu_record, cpu) % 64 == 0);
        assert(!memchr_inv(per_cpu_ptr(dynamic, cpu), 0, sizeof(*dynamic)));
        assert(per_cpu_ptr(&cpu_record.bytes[3], cpu) == &per_cpu(cpu_record, cpu).bytes[3]);
        workers[cpu] = (struct cpu_worker){ cpu, dynamic };
        assert(!pthread_create(&threads[cpu], NULL, percpu_worker, &workers[cpu]));
    }
    for (unsigned int cpu = 0; cpu < 4; cpu++) assert(!pthread_join(threads[cpu], NULL));
    for (unsigned int cpu = 0; cpu < 4; cpu++) {
        assert(per_cpu(cpu_wide, cpu) == 0x123456789abcdef0ULL + 20000);
        assert(per_cpu(cpu_record.counter, cpu) == 17 + 60000);
        assert(per_cpu(cpu_word, cpu) == cpu + 1 && per_cpu(cpu_half, cpu) == 9);
        assert(per_cpu_ptr(dynamic, cpu)->counter == 20000);
        assert(*per_cpu_ptr(&dynamic->bytes[3], cpu) == cpu + 1);
    }
    free_percpu(dynamic);
    assert(live_pages == permanent_pages && preemptible());
}

static void string_tests(void)
{
    /* Function pointers keep the compiler from replacing these calls with
     * host libc builtins, so the compatibility implementation is exercised. */
    void *(*volatile scan)(const void *, int, size_t) = memchr;
    size_t (*volatile bounded_length)(const char *, size_t) = strnlen;
    unsigned char bytes[] = { 0xff, 0x80, 0, 0xff, 0x42 };
    assert(scan(bytes, 0x1ff, sizeof(bytes)) == bytes);
    assert(scan(bytes, 0x42, sizeof(bytes)) == bytes + 4);
    assert(!scan(bytes, 1, sizeof(bytes)) && !scan(NULL, 0, 0));
    assert(memchr_inv(bytes, 0xff, sizeof(bytes)) == bytes + 1);
    assert(!memchr_inv(bytes, 0xff, 1) && !memchr_inv(NULL, 0, 0));
    assert(bounded_length("", 1) == 0 && bounded_length("abc", 2) == 2);

    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    char *source = mmap(NULL, page * 2, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    char *destination = mmap(NULL, page * 2, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    assert(source != MAP_FAILED && destination != MAP_FAILED);
    assert(!mprotect(source + page, page, PROT_NONE));
    assert(!mprotect(destination + page, page, PROT_NONE));
    assert(!scan(source + page, 0, 0) && !bounded_length(source + page, 0));
    assert(strscpy(destination + page, source + page, 0) == -E2BIG);
    assert(strscpy(destination + page, source + page, (size_t)INT_MAX + 1) == -E2BIG);
    for (size_t n = 1; n <= 32; n++) {
        char *src = source + page - n, *dst = destination + page - n;
        memset(src, 'a', n);
        memset(dst, 0x5a, n);
        assert(bounded_length(src, n) == n && !scan(src, 0, n));
        assert(strscpy(dst, src, n) == -E2BIG && !dst[n - 1]);
        for (size_t i = 0; i < n - 1; i++) assert(dst[i] == 'a');
        src[n - 1] = '\0';
        assert(strscpy(dst, src, n) == (ssize_t)n - 1 && !memcmp(src, dst, n));
        char *copy = kstrdup(src, GFP_KERNEL);
        assert(copy && !memcmp(copy, src, n));
        kfree(copy);
    }
    assert(!munmap(source, page * 2) && !munmap(destination, page * 2));
    char padded[12];
    memset(padded, 0x5a, sizeof(padded));
    assert(strscpy_pad(padded, "abc", sizeof(padded)) == 3);
    assert(!memcmp(padded, "abc", 3) && !memchr_inv(padded + 3, 0, sizeof(padded) - 3));
    memset(padded, 0x5a, sizeof(padded));
    assert(strscpy_pad(padded, "abcdefghijklm", 3) == -E2BIG);
    assert(!memcmp(padded, "ab\0", 3) && !memchr_inv(padded + 3, 0x5a, sizeof(padded) - 3));
    char *copy = kstrndup("abcd", 2, GFP_KERNEL);
    assert(copy && !strcmp(copy, "ab"));
    kfree(copy);
    copy = kmemdup_nul((const char *)bytes, sizeof(bytes), GFP_KERNEL);
    assert(copy && !memcmp(copy, bytes, sizeof(bytes)) && !copy[sizeof(bytes)]);
    kfree(copy);
    copy = kmemdup_nul(NULL, 0, GFP_KERNEL);
    assert(copy && !copy[0]);
    kfree(copy);
    assert(!kmemdup_nul(NULL, SIZE_MAX, GFP_KERNEL));
    assert(!kstrdup(NULL, GFP_KERNEL) && !kstrndup(NULL, 1, GFP_KERNEL));
    fail_allocation = true;
    assert(!kstrdup("failed", GFP_KERNEL) && !kstrndup("failed", 3, GFP_KERNEL));
    assert(!kmemdup_nul("failed", 6, GFP_KERNEL));
    fail_allocation = false;
    assert(live_pages == permanent_pages);
}

static unsigned long scalar_next(const unsigned long *map, unsigned long size,
                                 unsigned long start, bool value)
{
    for (unsigned long bit = start; bit < size; bit++) {
        if (!!(map[bit / BITS_PER_LONG] & BIT(bit % BITS_PER_LONG)) == value) return bit;
    }
    return size;
}

static void bitmap_tests(void)
{
    DECLARE_BITMAP(map, 256);
    DECLARE_BITMAP(other, 256);
    DECLARE_BITMAP(both, 256);
    DECLARE_BITMAP(either, 256);
    DECLARE_BITMAP(except, 256);
    for (unsigned int pattern = 0; pattern < 12; pattern++) {
        for (unsigned int word = 0; word < ARRAY_SIZE(map); word++) {
            map[word] = pattern == 0 ? 0 : pattern == 1 ? ~0UL :
                0x8421084210842108UL ^ (0x9e3779b97f4a7c15UL * (pattern + word));
            other[word] = 0x1248124812481248UL * (pattern + word + 1);
            both[word] = map[word] & other[word];
            either[word] = map[word] | other[word];
            except[word] = map[word] & ~other[word];
            unsigned int weight = 0;
            for (unsigned int bit = 0; bit < BITS_PER_LONG; bit++) weight += !!(map[word] & BIT(bit));
            assert(hweight_long(map[word]) == weight);
        }
        for (unsigned long size = 0; size <= 256; size++) {
            assert(find_first_bit(map, size) == scalar_next(map, size, 0, true));
            assert(find_first_zero_bit(map, size) == scalar_next(map, size, 0, false));
            assert(find_first_and_bit(map, other, size) == scalar_next(both, size, 0, true));
            unsigned long last = size, rank = 0;
            for (unsigned long start = 0; start <= size + 1; start++) {
                assert(find_next_bit(map, size, start) == scalar_next(map, size, start, true));
                assert(find_next_zero_bit(map, size, start) == scalar_next(map, size, start, false));
                assert(find_next_and_bit(map, other, size, start) == scalar_next(both, size, start, true));
                assert(find_next_or_bit(map, other, size, start) == scalar_next(either, size, start, true));
                assert(find_next_andnot_bit(map, other, size, start) == scalar_next(except, size, start, true));
                if (start < size && test_bit(start, map)) {
                    assert(find_nth_bit(map, size, rank++) == start);
                    last = start;
                }
            }
            assert(find_nth_bit(map, size, rank) == size && find_last_bit(map, size) == last);
        }
    }
    bitmap_zero(map, 256);
    for (unsigned long bit = 0; bit < 256; bit++) {
        assert(!test_and_set_bit(bit, map) && test_and_set_bit(bit, map));
        assert(test_bit(bit, map) && test_bit_acquire(bit, map));
        assert(test_and_clear_bit(bit, map) && !test_and_clear_bit(bit, map));
        __set_bit(bit, map);
        assert(__test_and_change_bit(bit, map) && !test_bit(bit, map));
        assert(!test_and_change_bit(bit, map) && test_and_change_bit(bit, map));
    }
    assert(bitmap_empty(map, 256));
    assert(!test_and_set_bit_lock(65, map));
    assert(test_and_set_bit_lock(65, map));
    clear_bit_unlock(65, map);
    assert(!test_bit(65, map));
    set_bit(7, map);
    set_bit(0, map);
    assert(clear_bit_unlock_is_negative_byte(0, map) && test_bit(7, map));
    clear_bit(7, map);
    assert(!clear_bit_unlock_is_negative_byte(0, map));
    bitmap_fill(map, 65);
    assert(bitmap_full(map, 65));
    assert(hweight8(0xff) == 8 && hweight16(0xffff) == 16 && hweight32(~0U) == 32);
}

static DECLARE_BITMAP(shared_bits, 128);
static unsigned int bit_lock_count;

static void *bit_worker(void *argument)
{
    unsigned long index = *(unsigned long *)argument;
    for (unsigned int i = 0; i < 20000; i++) {
        set_bit(index, shared_bits);
        while (test_and_set_bit_lock(65, shared_bits)) vinix_linuxkpi_spin_wait();
        bit_lock_count++;
        clear_bit_unlock(65, shared_bits);
    }
    return NULL;
}

static void bit_concurrency_tests(void)
{
    unsigned long indexes[] = { 0, 1, 62, 63 };
    pthread_t threads[ARRAY_SIZE(indexes)];
    for (size_t i = 0; i < ARRAY_SIZE(threads); i++) {
        assert(!pthread_create(&threads[i], NULL, bit_worker, &indexes[i]));
    }
    for (size_t i = 0; i < ARRAY_SIZE(threads); i++) assert(!pthread_join(threads[i], NULL));
    assert(bit_lock_count == 20000 * ARRAY_SIZE(threads) && !test_bit(65, shared_bits));
    for (size_t i = 0; i < ARRAY_SIZE(indexes); i++) assert(test_bit(indexes[i], shared_bits));
}

static void byteorder_tests(void)
{
    unsigned char bytes[18];
    memset(bytes, 0xa5, sizeof(bytes));
    put_unaligned_le16(0x1234, bytes + 1);
    assert(bytes[1] == 0x34 && bytes[2] == 0x12 && get_unaligned_le16(bytes + 1) == 0x1234);
    put_unaligned_be24(0x123456, bytes + 1);
    assert(bytes[1] == 0x12 && bytes[3] == 0x56 && get_unaligned_be24(bytes + 1) == 0x123456);
    put_unaligned_le32(0x12345678, bytes + 1);
    assert(bytes[1] == 0x78 && bytes[4] == 0x12 && get_unaligned_le32(bytes + 1) == 0x12345678);
    put_unaligned_be48(0x123456789abcULL, bytes + 1);
    assert(bytes[1] == 0x12 && bytes[6] == 0xbc && get_unaligned_be48(bytes + 1) == 0x123456789abcULL);
    put_unaligned_be64(0x123456789abcdef0ULL, bytes + 1);
    assert(bytes[1] == 0x12 && bytes[8] == 0xf0 && get_unaligned_be64(bytes + 1) == 0x123456789abcdef0ULL);
    assert(bytes[0] == 0xa5 && bytes[9] == 0xa5);
    assert(be32_to_cpu(cpu_to_be32(0x12345678)) == 0x12345678);
    assert(le64_to_cpu(cpu_to_le64(0x123456789abcdef0ULL)) == 0x123456789abcdef0ULL);
}

static void raw_lock_tests(void)
{
    DEFINE_RAW_SPINLOCK(lock);
    unsigned long flags, nested;
    assert(!raw_spin_is_locked(&lock) && !irqs_disabled());
    assert(raw_spin_trylock_irqsave(&lock, flags));
    assert(raw_spin_is_locked(&lock) && irqs_disabled() && preempt_depth == 1);
    assert(!raw_spin_trylock_irqsave(&lock, nested));
    assert(irqs_disabled() && preempt_depth == 1 && irqs_disabled_flags(nested));
    raw_spin_unlock_irqrestore(&lock, flags);
    assert(!irqs_disabled() && preempt_depth == 0);
    raw_spin_lock(&lock);
    /* Ordinary caller names must not collide with the macro's temporary. */
    unsigned long acquired;
    assert(!raw_spin_trylock_irqsave(&lock, acquired));
    assert(!irqs_disabled() && preempt_depth == 1);
    raw_spin_unlock(&lock);
    local_irq_save(flags);
    raw_spin_lock_irqsave(&lock, nested);
    raw_spin_unlock_irqrestore(&lock, nested);
    assert(irqs_disabled() && preempt_depth == 0);
    local_irq_restore(flags);
    raw_spin_lock_irq(&lock);
    assert(irqs_disabled() && preempt_depth == 1);
    raw_spin_unlock_irq(&lock);
    assert(!irqs_disabled() && preempt_depth == 0);
}

struct entry { int key, order; struct list_head link; struct rb_node tree; };
#define COUNT 4096
static struct entry entries[COUNT];

static int compare_list(void *priv, const struct list_head *a, const struct list_head *b)
{
    (void)priv;
    const struct entry *x = list_entry(a, struct entry, link);
    const struct entry *y = list_entry(b, struct entry, link);
    return (x->key > y->key) - (x->key < y->key);
}

static void list_tests(void)
{
    LIST_HEAD(head);
    list_sort(NULL, &head, compare_list);
    assert(list_empty(&head));
    for (int i = 0; i < COUNT; i++) {
        entries[i].key = (i * 73) % 127;
        entries[i].order = i;
        list_add_tail(&entries[i].link, &head);
    }
    list_sort(NULL, &head, compare_list);
    int count = 0;
    struct entry *entry, *previous = NULL;
    list_for_each_entry(entry, &head, link) {
        assert(entry->link.next->prev == &entry->link && entry->link.prev->next == &entry->link);
        if (previous) {
            assert(previous->key <= entry->key);
            if (previous->key == entry->key) assert(previous->order < entry->order);
        }
        previous = entry;
        count++;
    }
    assert(count == COUNT);
    struct entry *next;
    list_for_each_entry_safe(entry, next, &head, link) list_del_init(&entry->link);
    assert(list_empty(&head));
}

static int tree_height(const struct rb_node *node)
{
    if (!node) return 1;
    if (node->rb_left) assert(rb_parent(node->rb_left) == node);
    if (node->rb_right) assert(rb_parent(node->rb_right) == node);
    bool black = node->__rb_parent_color & 1;
    if (!black) {
        assert(!node->rb_left || (node->rb_left->__rb_parent_color & 1));
        assert(!node->rb_right || (node->rb_right->__rb_parent_color & 1));
    }
    int left = tree_height(node->rb_left), right = tree_height(node->rb_right);
    assert(left == right);
    return left + black;
}

static void tree_tests(void)
{
    struct rb_root root = RB_ROOT;
    for (int i = 0; i < COUNT; i++) {
        entries[i].key = (i * 73) % COUNT;
        struct rb_node **link = &root.rb_node, *parent = NULL;
        while (*link) {
            parent = *link;
            struct entry *other = rb_entry(parent, struct entry, tree);
            link = entries[i].key < other->key ? &parent->rb_left : &parent->rb_right;
        }
        rb_link_node(&entries[i].tree, parent, link);
        rb_insert_color(&entries[i].tree, &root);
        assert(root.rb_node->__rb_parent_color & 1);
        tree_height(root.rb_node);
    }
    int expected = 0;
    for (struct rb_node *p = rb_first(&root); p; p = rb_next(p)) {
        assert(rb_entry(p, struct entry, tree)->key == expected++);
    }
    assert(expected == COUNT);
    for (int i = 0; i < COUNT; i++) {
        rb_erase(&entries[(i * 61) % COUNT].tree, &root);
        tree_height(root.rb_node);
    }
    assert(RB_EMPTY_ROOT(&root));
}

static atomic_t counter = ATOMIC_INIT(0);
static spinlock_t lock = __SPIN_LOCK_UNLOCKED(lock);
static unsigned int locked_count;

static void *concurrent_worker(void *arg)
{
    (void)arg;
    for (int i = 0; i < 50000; i++) {
        unsigned long flags;
        atomic_inc(&counter);
        spin_lock_irqsave(&lock, flags);
        assert(!interrupts && preempt_depth == 1);
        locked_count++;
        spin_unlock_irqrestore(&lock, flags);
        assert(interrupts && preempt_depth == 0);
    }
    return NULL;
}

static void concurrency_tests(void)
{
    pthread_t threads[4];
    for (size_t i = 0; i < ARRAY_SIZE(threads); i++) assert(!pthread_create(&threads[i], NULL, concurrent_worker, NULL));
    for (size_t i = 0; i < ARRAY_SIZE(threads); i++) assert(!pthread_join(threads[i], NULL));
    assert(atomic_read(&counter) == 200000 && locked_count == 200000);
    assert(atomic_cmpxchg(&counter, 0, 7) == 200000);
    assert(atomic_cmpxchg(&counter, 200000, 7) == 200000);
    assert(atomic_xchg(&counter, 1) == 7 && atomic_dec_and_test(&counter));
    atomic64_t big = ATOMIC64_INIT(1LL << 40);
    assert(atomic64_inc_return(&big) == (1LL << 40) + 1);
    spinlock_t outer, inner;
    spin_lock_init(&outer);
    spin_lock_init(&inner);
    unsigned long outer_flags, inner_flags;
    spin_lock_irqsave(&outer, outer_flags);
    assert(!spin_trylock(&outer) && preempt_depth == 1);
    spin_lock_irqsave(&inner, inner_flags);
    assert(preempt_depth == 2 && !interrupts);
    spin_unlock_irqrestore(&inner, inner_flags);
    assert(preempt_depth == 1 && !interrupts);
    spin_unlock_irqrestore(&outer, outer_flags);
    assert(preempt_depth == 0 && interrupts);
}

static void atomic_api_tests(void)
{
    atomic_t value = ATOMIC_INIT(INT_MAX);
    assert(atomic_fetch_inc_relaxed(&value) == INT_MAX);
    assert(atomic_read(&value) == INT_MIN);
    int old = 7;
    assert(!atomic_try_cmpxchg_acquire(&value, &old, 4) && old == INT_MIN);
    assert(atomic_try_cmpxchg_release(&value, &old, 4));
    assert(atomic_fetch_andnot(1, &value) == 4 && atomic_read(&value) == 4);
    atomic_or(3, &value);
    assert(atomic_fetch_xor_acquire(2, &value) == 7 && atomic_read(&value) == 5);
    assert(atomic_add_unless(&value, -1, 0) && atomic_read(&value) == 4);
    atomic_set(&value, 0);
    assert(!atomic_inc_not_zero(&value));
    atomic64_t big = ATOMIC64_INIT(S64_MAX);
    assert(atomic64_add_return_relaxed(1, &big) == S64_MIN);
    s64 previous = 0;
    assert(!atomic64_try_cmpxchg_relaxed(&big, &previous, 0) && previous == S64_MIN);
    assert(atomic64_try_cmpxchg(&big, &previous, 0));
    atomic_long_t wide = ATOMIC_LONG_INIT(1L << 40);
    assert(atomic_long_fetch_add_release(1L << 40, &wide) == 1L << 40);
    assert(atomic_long_read_acquire(&wide) == 1L << 41);
    unsigned long bits = 7;
    assert(xchg(&bits, 9) == 7);
    assert(cmpxchg_acquire(&bits, 9, 11) == 9 && bits == 11);
    unsigned long expected = 0;
    assert(!try_cmpxchg_release(&bits, &expected, 0) && expected == 11);
    assert(try_cmpxchg(&bits, &expected, 0) && bits == 0);
}

static atomic_t published = ATOMIC_INIT(0);
static u64 message[2];

static void *message_writer(void *unused)
{
    (void)unused;
    for (u64 i = 1; i <= 20000; i++) {
        atomic_cond_read_acquire(&published, VAL == 0);
        message[0] = i;
        message[1] = ~i;
        atomic_set_release(&published, 1);
    }
    return NULL;
}

static void *message_reader(void *unused)
{
    (void)unused;
    for (u64 i = 1; i <= 20000; i++) {
        atomic_cond_read_acquire(&published, VAL == 1);
        assert(message[0] == i && message[1] == ~i);
        atomic_set_release(&published, 0);
    }
    return NULL;
}

struct shared_object {
    struct kref refs;
    unsigned int completed[4];
};
struct reference_worker { struct shared_object *object; unsigned int index; };
static atomic_t releases = ATOMIC_INIT(0);

static void release_object(struct kref *refs)
{
    struct shared_object *object = container_of(refs, struct shared_object, refs);
    /* Each worker publishes this before dropping its final reference. The
     * final release must acquire all prior writes and happen exactly once. */
    for (size_t i = 0; i < ARRAY_SIZE(object->completed); i++) assert(object->completed[i] == i + 1);
    assert(atomic_fetch_inc(&releases) == 0);
    kfree(object);
}

static void *reference_worker(void *argument)
{
    struct reference_worker *worker = argument;
    struct shared_object *object = worker->object;
    for (int i = 0; i < 30000; i++) {
        kref_get(&object->refs);
        assert(!kref_put(&object->refs, release_object));
    }
    object->completed[worker->index] = worker->index + 1;
    kref_put(&object->refs, release_object);
    return NULL;
}

static void reference_tests(void)
{
    refcount_t refs = REFCOUNT_INIT(0);
    assert(!refcount_inc_not_zero(&refs) && atomic_read(&refcount_warnings) == 0);
    refcount_inc(&refs);
    assert(refcount_read(&refs) == (unsigned)REFCOUNT_SATURATED);
    assert(!refcount_dec_and_test(&refs));
    refcount_set(&refs, 1);
    refcount_add(INT_MAX, &refs);
    assert(refcount_read(&refs) == (unsigned)REFCOUNT_SATURATED);
    refcount_set(&refs, 1);
    assert(!refcount_sub_and_test(2, &refs));
    assert(refcount_read(&refs) == (unsigned)REFCOUNT_SATURATED);
    assert(atomic_read(&refcount_warnings) == 4);
    refcount_set(&refs, 1);
    assert(refcount_dec_if_one(&refs) && !refcount_dec_if_one(&refs));
    spinlock_t lock;
    spin_lock_init(&lock);
    unsigned long flags = 0;
    refcount_set(&refs, 2);
    assert(!refcount_dec_and_lock_irqsave(&refs, &lock, &flags));
    assert(interrupts && preempt_depth == 0 && refcount_read(&refs) == 1);
    assert(refcount_dec_and_lock_irqsave(&refs, &lock, &flags));
    assert(!interrupts && preempt_depth == 1 && refcount_read(&refs) == 0);
    spin_unlock_irqrestore(&lock, flags);
    assert(interrupts && preempt_depth == 0);
    struct shared_object *object = kzalloc(sizeof(*object), GFP_KERNEL);
    assert(object);
    kref_init(&object->refs);
    struct reference_worker workers[4];
    pthread_t threads[4];
    for (size_t i = 0; i < ARRAY_SIZE(workers); i++) {
        workers[i] = (struct reference_worker){ object, (unsigned)i };
        kref_get(&object->refs);
        assert(!pthread_create(&threads[i], NULL, reference_worker, &workers[i]));
    }
    kref_put(&object->refs, release_object);
    for (size_t i = 0; i < ARRAY_SIZE(threads); i++) assert(!pthread_join(threads[i], NULL));
    assert(atomic_read(&releases) == 1 && live_pages == permanent_pages);
    pthread_t writer, reader;
    assert(!pthread_create(&writer, NULL, message_writer, NULL));
    assert(!pthread_create(&reader, NULL, message_reader, NULL));
    assert(!pthread_join(writer, NULL) && !pthread_join(reader, NULL));
}

#include "sync_test.h"
#include "ww_mutex_test.h"
#include "time_test.h"
#include "timer_test.h"
#include "workqueue_test.h"
#include "delayed_work_test.h"
#include "unbound_work_test.h"
#include "bound_work_test.h"
#include "bitmap_runtime_test.h"
#include "srcu_test.h"
#include "wait_bit_test.h"
#include "io_test.h"
#include "cache_test.h"
#include "task_flag_test.h"
#include "seqcount_test.h"

int main(void)
{
    assert(vinix_linuxkpi_percpu_init(0, host_percpu_start, host_percpu_end) == -EINVAL);
    assert(vinix_linuxkpi_percpu_init(NR_CPUS + 1, host_percpu_start, host_percpu_end) == -EINVAL);
    assert(vinix_linuxkpi_percpu_init(4, host_percpu_end, host_percpu_start) == -EINVAL);
    fail_allocation = true;
    assert(vinix_linuxkpi_percpu_init(4, host_percpu_start, host_percpu_end) == -ENOMEM);
    assert(live_pages == 0);
    fail_allocation = false;
    assert(vinix_linuxkpi_percpu_init(4, host_percpu_start, host_percpu_end) == 0);
    permanent_pages = live_pages;
    allocation_tests();
    cache_tests();
    string_tests();
    bitmap_tests();
    test_bitmap_runtime();
    bit_concurrency_tests();
    byteorder_tests();
    raw_lock_tests();
    percpu_tests();
    task_tests();
    task_flag_tests();
    task_wait_tests();
    sync_tests();
    ww_mutex_tests();
    seqcount_tests();
    time_tests();
    wait_bit_tests();
    io_tests();
    timer_tests();
    workqueue_tests();
    delayed_work_tests();
    unbound_work_tests();
    bound_work_tests();
    srcu_tests();
    list_tests();
    tree_tests();
    concurrency_tests();
    atomic_api_tests();
    reference_tests();
    vinix_linuxkpi_percpu_destroy_for_test();
    assert(live_pages == 0);
    puts("LinuxKPI: PASS (Linux helpers, allocation/OOM, packed object caches, strings, bitmaps, SMP/IRQ locks, per-CPU storage, task references, wake races, synchronization, sequence counters, wound/wait mutexes, clocks, bit/variable and I/O waits, timers, ordered/delayed/unbound/bound work, runnable concurrency, priority, system queues and SRCU)");
    return 0;
}
