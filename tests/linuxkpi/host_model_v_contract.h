/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_HOST_MODEL_V_CONTRACT_H
#define VINIX_LINUXKPI_HOST_MODEL_V_CONTRACT_H
/* Native typedef names differ from the V backend's fixed-width aliases. */
#undef atomic_fetch_add
#undef atomic_fetch_sub
#undef atomic_fetch_and
#undef atomic_fetch_or
#undef atomic_fetch_xor
#undef atomic_exchange
#undef atomic_compare_exchange_strong
#undef atomic_compare_exchange_weak
#define u64 vmh_linux_u64
#define timezone vmh_linux_timezone
#define ffs vmh_linux_ffs
#define fls vmh_linux_fls
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmacro-redefined"
#endif
/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>
#undef static_assert
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


typedef u64 vmh_u64;
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
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
#undef fls
#undef ffs
#undef timezone
#undef u64
typedef const void *vmh_const_void_p;
typedef const char *vmh_const_char_p;
/* Native initialization constants describe storage, not algorithms. */
#define vmh_mutex_initializer ((pthread_mutex_t)PTHREAD_MUTEX_INITIALIZER)
#define vmh_condition_initializer ((pthread_cond_t)PTHREAD_COND_INITIALIZER)
extern size_t vmh_live_pages, vmh_permanent_pages;
extern bool vmh_fail_allocation, vmh_last_reclaim, vmh_usleep_boundary_check;
extern int vmh_allocation_failure_after, vmh_worker_bind_failure_after;
extern unsigned int vmh_worker_bind_failures;
extern atomic_t vmh_refcount_warnings, vmh_time_warnings;
extern vmh_u64 vmh_host_clock_ns;
/* Architecture TLS data uses these exact native declarations and initializer
 * values. The V backend's Vinix target currently cannot emit thread-local
 * storage itself; libc retains the original per-thread ownership/lifetime. */
extern _Thread_local bool vmh_interrupts, vmh_resched_pending;
extern _Thread_local unsigned int vmh_preempt_depth, vmh_current_cpu;
extern _Thread_local int vmh_current_worker_nice;
extern _Thread_local void (*vmh_host_irq_restore_hook)(void);
extern _Thread_local unsigned int *vmh_timer_sync_spins;
extern _Thread_local void (*vmh_host_clock_read_hook)(void);
extern _Thread_local struct native_task_model *vmh_native_task;
extern _Thread_local void *vmh_wait_bit_test_current, *vmh_mutex_io_current;
extern _Thread_local void *vmh_io_test_current, *vmh_expiry_test, *vmh_usleep_host_current;
extern _Thread_local void (*vmh_host_iowait_before_block)(struct native_task_model *);
_Static_assert(sizeof(vmh_u64) == 8, "original host clock word");
_Static_assert(sizeof(((struct native_task_model *)0)->storage) == 64,
               "original embedded task-view storage");
void vmh_model_queue_init(struct native_task_model *);
void vmh_sync_model_init(struct native_task_model *, unsigned int);
void vmh_sync_model_destroy(struct native_task_model *);
/* Implemented by the independent I/O fixture; the caller holds queue_lock. */
void vmh_iowait_end_locked(struct native_task_model *);
#endif
