// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module hostport

#include "host_model_v_contract.h"

@[typedef]
struct C.vmh_u64 {}
@[typedef]
struct C.vmh_const_void_p {}
@[typedef]
struct C.vmh_const_char_p {}
@[typedef]
struct C.pthread_mutex_t {}
@[typedef]
struct C.pthread_cond_t {}
@[typedef]
struct C.atomic_t { counter i32 }
struct C.native_task_model {
mut:
    storage [8]u64
    pid i32
    tgid i32
    name &char
    pending u64
    masked u64
    must_exit bool
    exiting bool
    yields u32
    pins u32
    dead bool
    queued bool
    iowait_cpu_plus_one u32
    reject_enqueue bool
    heap_owned bool
    queue_lock C.pthread_mutex_t
    queue_changed C.pthread_cond_t
    iteration u32
    dequeued u32
    parked u32
}
struct C.task_struct {
mut:
    vinix_thread voidptr
    pid i32
    tgid i32
    flags u32
    __state u32
    comm [16]char
    vinix_initial_comm [16]char
    in_iowait u32
}
@[c_extern] __global C.vmh_mutex_initializer C.pthread_mutex_t
@[c_extern] __global C.vmh_condition_initializer C.pthread_cond_t
@[c_extern] __global C.vmh_interrupts bool
@[c_extern] __global C.vmh_preempt_depth u32
@[c_extern] __global C.vmh_current_cpu u32
@[c_extern] __global C.vmh_current_worker_nice i32
@[c_extern] __global C.vmh_host_irq_restore_hook fn ()
@[c_extern] __global C.vmh_timer_sync_spins &u32
@[c_extern] __global C.vmh_host_clock_read_hook fn ()
@[c_extern] __global C.vmh_native_task &C.native_task_model
@[c_extern] __global C.vmh_resched_pending bool
@[typedef] struct C.pthread_t {}
@[c_extern] __global C.vmh_live_pages usize
@[c_extern] __global C.vmh_permanent_pages usize
@[c_extern] __global C.vmh_fail_allocation bool
@[c_extern] __global C.vmh_last_reclaim bool
@[c_extern] __global C.vmh_usleep_boundary_check bool
@[c_extern] __global C.vmh_allocation_failure_after i32
@[c_extern] __global C.vmh_worker_bind_failure_after i32
@[c_extern] __global C.vmh_worker_bind_failures u32
@[c_extern] __global C.vmh_refcount_warnings C.atomic_t
@[c_extern] __global C.vmh_time_warnings C.atomic_t
@[c_extern] __global C.vmh_host_clock_ns u64
@[c_extern] __global C.vmh_wait_bit_test_current voidptr
@[c_extern] __global C.vmh_mutex_io_current voidptr
@[c_extern] __global C.vmh_io_test_current voidptr
@[c_extern] __global C.vmh_expiry_test voidptr
@[c_extern] __global C.vmh_usleep_host_current voidptr
@[c_extern] __global C.vmh_host_iowait_before_block fn (&C.native_task_model)
@[c_extern] __global C.current &C.task_struct
fn C.vmh_model_queue_init(&C.native_task_model)
fn C.vmh_sync_model_init(&C.native_task_model, u32)
fn C.vmh_sync_model_destroy(&C.native_task_model)
fn C.vmh_iowait_end_locked(&C.native_task_model)
fn C.assert(bool)
fn C.__atomic_load_n(voidptr, i32) u64
fn C.__atomic_store_n(voidptr, ...)
fn C.__atomic_fetch_add(voidptr, ...) u64
fn C.__atomic_fetch_sub(voidptr, ...) u64
fn C.__atomic_add_fetch(voidptr, ...) u64
fn C.__atomic_compare_exchange_n(voidptr, voidptr, ...) bool
fn C.__atomic_signal_fence(i32)
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.pthread_mutex_lock(&C.pthread_mutex_t) i32
fn C.pthread_mutex_unlock(&C.pthread_mutex_t) i32
fn C.pthread_mutex_destroy(&C.pthread_mutex_t) i32
fn C.pthread_cond_destroy(&C.pthread_cond_t) i32
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.strcmp(&char, &char) i32
fn C.strlen(&char) usize
fn C.sched_yield() i32
fn C.vinix_linuxkpi_task_init(voidptr, voidptr, i32, i32, &char, usize)
fn C.vinix_linuxkpi_task_view(voidptr, voidptr, i32, i32, &char, usize, bool) voidptr
fn C.vinix_linuxkpi_task_inherit(voidptr, voidptr, i32, i32, voidptr)
fn C.vinix_linuxkpi_task_dead(voidptr)
fn C.vinix_linuxkpi_task_selftest() i32
fn C.vinix_linuxkpi_task_queued(voidptr) bool
fn C.vinix_linuxkpi_task_enqueue(voidptr) bool
fn C.vinix_linuxkpi_may_sleep() bool
fn C.vinix_linuxkpi_spin_wait()
fn C.get_task_struct(&C.task_struct) &C.task_struct
fn C.put_task_struct(&C.task_struct)
fn C.task_is_running(&C.task_struct) bool
fn C.set_current_state(u32)
fn C.schedule()
fn C.wake_up_process(&C.task_struct) i32
fn C.wake_up_state(&C.task_struct, u32) i32
