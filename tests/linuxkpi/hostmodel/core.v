// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module hostmodel

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
struct C.task_struct {}
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
@[export: 'vmh_live_pages'] __global live_pages usize
@[export: 'vmh_permanent_pages'] __global permanent_pages usize
@[export: 'vmh_fail_allocation'] __global fail_allocation bool
@[export: 'vmh_last_reclaim'] __global last_reclaim bool
@[export: 'vmh_usleep_boundary_check'] __global usleep_boundary_check bool
@[export: 'vmh_allocation_failure_after'] __global allocation_failure_after i32 = -1
@[export: 'vmh_worker_bind_failure_after'] __global worker_bind_failure_after i32 = -1
@[export: 'vmh_worker_bind_failures'] __global worker_bind_failures u32
@[export: 'vmh_refcount_warnings'] __global refcount_warnings C.atomic_t
@[export: 'vmh_time_warnings'] __global time_warnings C.atomic_t
@[export: 'vmh_host_clock_ns'] __global host_clock_ns C.vmh_u64
fn C.assert(bool)
fn C.__atomic_load_n(voidptr, i32) u64
fn C.__atomic_store_n(voidptr, ...)
fn C.__atomic_fetch_add(voidptr, ...) u64
fn C.__atomic_fetch_sub(voidptr, ...) u64
fn C.__atomic_compare_exchange_n(voidptr, voidptr, ...) bool
fn C.__atomic_signal_fence(i32)
fn C.pthread_mutex_lock(&C.pthread_mutex_t) i32
fn C.pthread_mutex_unlock(&C.pthread_mutex_t) i32
fn C.pthread_mutex_destroy(&C.pthread_mutex_t) i32
fn C.pthread_cond_destroy(&C.pthread_cond_t) i32
fn C.pthread_cond_signal(&C.pthread_cond_t) i32
fn C.pthread_cond_wait(&C.pthread_cond_t, &C.pthread_mutex_t) i32
fn C.free(voidptr)
fn C.posix_memalign(&voidptr, usize, usize) i32
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.strlen(&char) usize
@[noreturn]
fn C.abort()
fn C.fputs(&char, voidptr) i32
fn C.fprintf(voidptr, &char, ...) i32
@[c_extern] __global C.stderr voidptr
fn C.atomic_inc(&C.atomic_t)
@[c_extern] __global C.REFCOUNT_ADD_NOT_ZERO_OVF i32
@[c_extern] __global C.REFCOUNT_DEC_LEAK i32
@[c_extern] __global C.EWOULDBLOCK i32
@[c_extern] __global C.EINVAL i32
@[c_extern] __global C.EIO i32
fn C.vmh_iowait_end_locked(&C.native_task_model)
fn C.vinix_linuxkpi_task_view(voidptr, voidptr, i32, i32, &char, usize, bool) voidptr
fn C.vinix_linuxkpi_task_init(voidptr, voidptr, i32, i32, &char, usize)
fn C.vinix_linuxkpi_workqueue_task_sleep(voidptr)
fn C.vinix_linuxkpi_workqueue_task_resume(voidptr)
fn C.vinix_linuxkpi_time_waiters() usize
fn C.vinix_linuxkpi_percpu_count() u32

fn native_u64(bits u64) C.vmh_u64 {
    mut result := C.vmh_u64{}
    unsafe { C.memcpy(&result, &bits, 8) }
    return result
}

@[export: 'vmh_model_queue_init']
pub fn queue_init(model &C.native_task_model) {
    unsafe {
        model.queued = true
        model.queue_lock = C.vmh_mutex_initializer
        model.queue_changed = C.vmh_condition_initializer
    }
}

@[export: 'vmh_sync_model_init']
pub fn sync_init(model &C.native_task_model, index u32) {
    unsafe {
        *model = C.native_task_model{
            pid: i32(500 + index)
            tgid: 500
            name: c'sync-worker'
            queued: true
            queue_lock: C.vmh_mutex_initializer
            queue_changed: C.vmh_condition_initializer
        }
        C.vinix_linuxkpi_task_init(&model.storage[0], model, model.pid, model.tgid, model.name, 11)
    }
}

@[export: 'vmh_sync_model_destroy']
pub fn sync_destroy(model &C.native_task_model) {
    unsafe {
        C.assert(model.pins == 0)
        C.assert(C.pthread_mutex_destroy(&model.queue_lock) == 0)
        C.assert(C.pthread_cond_destroy(&model.queue_changed) == 0)
    }
}

@[export: 'vinix_linuxkpi_clock_ns']
pub fn clock_ns() C.vmh_u64 {
    unsafe {
        now := C.__atomic_load_n(&host_clock_ns, 2)
        hook := C.vmh_host_clock_read_hook
        C.vmh_host_clock_read_hook = nil
        if hook != unsafe { nil } { hook() }
        return native_u64(now)
    }
}
@[export: 'vinix_linuxkpi_clock_resolution_ns']
pub fn clock_resolution_ns() u32 { return 1000000 }
@[export: 'vinix_linuxkpi_test_warn_note']
pub fn warn_note(file C.vmh_const_char_p, line i32) { unsafe { C.atomic_inc(&time_warnings) } }

@[export: 'vinix_linuxkpi_task_get']
pub fn task_get(thread voidptr) { unsafe { C.__atomic_fetch_add(&(&C.native_task_model(thread)).pins, u32(1), i32(0)) } }
@[export: 'vinix_linuxkpi_task_put']
pub fn task_put(thread voidptr) {
    unsafe {
        task := &C.native_task_model(thread)
        pins := u32(C.__atomic_fetch_sub(&task.pins, u32(1), i32(4)))
        C.assert(pins != 0)
        if pins == 1 && task.heap_owned && C.__atomic_load_n(&task.dead, 2) != 0 {
            C.assert(C.pthread_mutex_destroy(&task.queue_lock) == 0)
            C.assert(C.pthread_cond_destroy(&task.queue_changed) == 0)
            C.free(task)
        }
    }
}
@[export: 'vinix_linuxkpi_task_is_dead']
pub fn task_is_dead(thread C.vmh_const_void_p) bool {
    return unsafe { C.__atomic_load_n(&(&C.native_task_model(thread)).dead, 2) != 0 }
}
@[export: 'vinix_linuxkpi_task_queued']
pub fn task_queued(thread C.vmh_const_void_p) bool {
    unsafe {
        task := &C.native_task_model(thread)
        C.assert(C.pthread_mutex_lock(&task.queue_lock) == 0)
        queued := task.queued
        C.assert(C.pthread_mutex_unlock(&task.queue_lock) == 0)
        return queued
    }
}
@[export: 'vinix_linuxkpi_task_enqueue']
pub fn task_enqueue(thread voidptr) bool {
    unsafe {
        task := &C.native_task_model(thread)
        C.assert(C.pthread_mutex_lock(&task.queue_lock) == 0)
        alive := C.__atomic_load_n(&task.dead, 2) == 0 && !task.reject_enqueue
        if alive {
            C.vmh_iowait_end_locked(task)
            task.queued = true
            C.assert(C.pthread_cond_signal(&task.queue_changed) == 0)
        }
        C.assert(C.pthread_mutex_unlock(&task.queue_lock) == 0)
        return alive
    }
}
@[export: 'vinix_linuxkpi_task_dequeue']
pub fn task_dequeue(thread voidptr) {
    unsafe {
        task := &C.native_task_model(thread)
        C.assert(usize(task) == usize(C.vmh_native_task) && C.pthread_mutex_lock(&task.queue_lock) == 0)
        task.queued = false
        if C.__atomic_load_n(&task.dead, 2) != 0 { C.vmh_iowait_end_locked(task) }
        C.__atomic_store_n(&task.dequeued, task.iteration, i32(3))
        C.assert(C.pthread_mutex_unlock(&task.queue_lock) == 0)
    }
}
@[export: 'vinix_linuxkpi_task_park']
pub fn task_park() {
    unsafe {
        task := C.vmh_native_task
        C.assert(task != nil && may_sleep())
        C.__atomic_store_n(&task.parked, task.iteration, i32(3))
        C.vinix_linuxkpi_workqueue_task_sleep(&task.storage[0])
        C.assert(C.pthread_mutex_lock(&task.queue_lock) == 0)
        for !task.queued { C.assert(C.pthread_cond_wait(&task.queue_changed, &task.queue_lock) == 0) }
        C.assert(C.pthread_mutex_unlock(&task.queue_lock) == 0)
        C.vinix_linuxkpi_workqueue_task_resume(&task.storage[0])
    }
}
@[export: 'vinix_linuxkpi_current_task']
pub fn current_task() &C.task_struct {
    unsafe {
        task := C.vmh_native_task
        C.assert(task != nil)
        return &C.task_struct(C.vinix_linuxkpi_task_view(&task.storage[0], task, task.pid, task.tgid,
            task.name, C.strlen(task.name), task.must_exit || task.exiting))
    }
}
@[export: 'vinix_linuxkpi_task_signal_pending']
pub fn signal_pending(thread C.vmh_const_void_p, fatal bool) bool {
    unsafe {
        task := &C.native_task_model(thread)
        pending := C.__atomic_load_n(&C.vmh_u64(&task.pending), 0)
        if task.must_exit || pending & (u64(1) << 8) != 0 { return true }
        return !fatal && pending & ~task.masked != 0
    }
}
@[export: 'vinix_linuxkpi_need_resched']
pub fn need_resched() bool { return C.vmh_resched_pending }
@[export: 'vinix_linuxkpi_cond_resched']
pub fn cond_resched() i32 {
    if !may_sleep() { return 0 }
    unsafe { C.assert(C.vmh_native_task != nil); C.vmh_native_task.yields++; C.vmh_resched_pending = false }
    return 1
}

@[export: 'vinix_linuxkpi_alloc_pages']
pub fn alloc_pages(pages usize, reclaim bool) voidptr {
    unsafe {
        C.__atomic_store_n(&last_reclaim, reclaim, i32(0))
        if fail_allocation { return nil }
        mut remaining := i32(C.__atomic_load_n(&allocation_failure_after, 0))
        for remaining >= 0 {
            if remaining == 0 { return nil }
            if C.__atomic_compare_exchange_n(&allocation_failure_after, &remaining, remaining - 1, false, i32(0), i32(0)) { break }
        }
        mut ptr := voidptr(nil)
        if C.posix_memalign(&ptr, 4096, pages * 4096) != 0 { return nil }
        C.memset(ptr, 0xa5, pages * 4096)
        C.__atomic_fetch_add(&live_pages, pages, i32(0))
        return ptr
    }
}
@[export: 'vinix_linuxkpi_free_pages']
pub fn free_pages(base voidptr, pages usize) {
    unsafe { C.assert(C.__atomic_fetch_sub(&live_pages, pages, i32(0)) >= pages); C.free(base) }
}
@[export: 'vinix_linuxkpi_page_size']
pub fn page_size() usize { return 4096 }
@[noreturn; export: 'vinix_linuxkpi_bug']
pub fn bug(file C.vmh_const_char_p, line i32) {
    unsafe {
        if usleep_boundary_check {
            C.assert(C.vinix_linuxkpi_time_waiters() == 0 && live_pages == 0)
            C.fputs(c'usleep boundary BUG with no published records or pages\n', C.stderr)
        }
        C.fprintf(C.stderr, c'Linux compatibility BUG at %s:%d\n', file, line)
        C.abort()
    }
}

@[export: 'vinix_linuxkpi_irq_save']
pub fn irq_save() usize {
    flags := if C.vmh_interrupts { usize(1) << 9 } else { usize(0) }
    unsafe { C.vmh_interrupts = false }
    return flags
}
@[export: 'vinix_linuxkpi_irq_restore']
pub fn irq_restore(flags usize) {
    unsafe {
        C.vmh_interrupts = flags & (usize(1) << 9) != 0
        if C.vmh_interrupts && C.vmh_host_irq_restore_hook != nil {
            hook := C.vmh_host_irq_restore_hook
            C.vmh_host_irq_restore_hook = nil
            hook()
        }
    }
}
@[export: 'vinix_linuxkpi_irq_flags']
pub fn irq_flags() usize { return if C.vmh_interrupts { usize(1) << 9 } else { usize(0) } }
@[export: 'vinix_linuxkpi_spin_wait']
pub fn spin_wait() {
    unsafe {
        if C.vmh_timer_sync_spins != nil { C.__atomic_fetch_add(C.vmh_timer_sync_spins, u32(1), i32(3)) }
        C.__atomic_signal_fence(5)
    }
}
@[export: 'vinix_linuxkpi_preempt_disable']
pub fn preempt_disable() { unsafe { C.vmh_preempt_depth++ } }
@[export: 'vinix_linuxkpi_preempt_enable']
pub fn preempt_enable() { unsafe { C.assert(C.vmh_preempt_depth != 0); C.vmh_preempt_depth-- } }
@[export: 'vinix_linuxkpi_preempt_enable_no_resched']
pub fn preempt_enable_no_resched() { unsafe { C.assert(C.vmh_preempt_depth != 0); C.vmh_preempt_depth-- } }
@[export: 'vinix_linuxkpi_preempt_count']
pub fn preempt_count() u32 { return C.vmh_preempt_depth }
@[export: 'vinix_linuxkpi_preempt_check_resched']
pub fn preempt_check_resched() {}
@[export: 'vinix_linuxkpi_cpu_id']
pub fn cpu_id() u32 { return C.vmh_current_cpu }
@[export: 'vinix_linuxkpi_worker_bind']
pub fn worker_bind(cpu u32) i32 {
    unsafe {
        if !may_sleep() { return -C.EWOULDBLOCK }
        if cpu >= C.vinix_linuxkpi_percpu_count() || cpu >= 64 { return -C.EINVAL }
        mut remaining := i32(C.__atomic_load_n(&worker_bind_failure_after, 0))
        for remaining >= 0 {
            if remaining == 0 { C.__atomic_fetch_add(&worker_bind_failures, u32(1), i32(3)); return -C.EIO }
            if C.__atomic_compare_exchange_n(&worker_bind_failure_after, &remaining, remaining - 1, false, i32(0), i32(0)) { break }
        }
        C.vmh_current_cpu = cpu
        return 0
    }
}
@[export: 'vinix_linuxkpi_may_sleep']
pub fn may_sleep() bool { return C.vmh_interrupts && C.vmh_preempt_depth == 0 }
@[export: 'vinix_linuxkpi_worker_set_nice']
pub fn worker_set_nice(nice i32) i32 {
    if !may_sleep() { return -C.EWOULDBLOCK }
    if nice < -20 || nice > 19 { return -C.EINVAL }
    unsafe { C.vmh_current_worker_nice = nice }
    return 0
}
@[export: 'vinix_linuxkpi_worker_nice']
pub fn worker_nice() i32 { return C.vmh_current_worker_nice }
@[export: 'vinix_linuxkpi_worker_timeslice']
pub fn worker_timeslice() C.vmh_u64 { return native_u64(u64(5000 * (20 - C.vmh_current_worker_nice) / 20)) }
@[export: 'vinix_linuxkpi_test_refcount_note']
pub fn refcount_note(kind i32) {
    unsafe { C.assert(kind >= C.REFCOUNT_ADD_NOT_ZERO_OVF && kind <= C.REFCOUNT_DEC_LEAK); C.atomic_inc(&refcount_warnings) }
}
