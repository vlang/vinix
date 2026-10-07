// SPDX-License-Identifier: GPL-2.0-only
// Independent task flag, late-view and wake/exit observations.
@[translated]
module hosttaskflag
#include "hosttaskflag_v_contract.h"
fn C.vtime_accounting_enabled_this_cpu() bool
fn C.vtime_account_guest_enter()
fn C.vtime_account_guest_exit()
fn C.cond_resched() i32
fn C.vmh_task_flag_late_view_worker(voidptr) voidptr
fn C.vmh_task_flag_wake_worker(voidptr) voidptr
@[c_extern] __global C.PF_VCPU u32
@[c_extern] __global C.PF_EXITING u32
@[c_extern] __global C.TASK_DEAD u32
@[c_extern] __global C.TASK_RUNNING u32
@[c_extern] __global C.TASK_UNINTERRUPTIBLE u32
const sentinel = u32(0x40000000)
fn flags(task &C.task_struct) u32 { return unsafe { u32(C.__atomic_load_n(&task.flags, 0)) } }
fn current_flags() {
    unsafe {
        mut model := C.native_task_model{pid: 731, tgid: 731, name: c'guest-task'}
        C.vmh_model_queue_init(&model)
        mut child := C.native_task_model{pid: 732, tgid: 731}
        previous := C.vmh_native_task
        C.vmh_native_task = &model
        C.memset(&model.storage[0], 0xa5, sizeof(model.storage))
        C.vinix_linuxkpi_task_init(&model.storage[0], &model, model.pid, model.tgid, c'initial', 7)
        task := C.get_task_struct(C.current)
        C.assert(flags(task) == 0 && model.pins == 1)
        task.flags = sentinel
        C.assert(!C.vtime_accounting_enabled_this_cpu())
        C.vtime_account_guest_enter()
        for i in 0 .. 512 {
            model.name = if i & 1 != 0 { c'guest-new-name' } else { c'' }
            C.assert(usize(C.current) == usize(task))
            C.assert(flags(task) == (sentinel | C.PF_VCPU))
            C.assert(C.strcmp(&task.comm[0], if i & 1 != 0 { c'guest-new-name' } else { c'initial' }) == 0)
            C.assert(C.cond_resched() == 1)
            C.assert(C.vinix_linuxkpi_task_selftest() == 0)
            C.assert(flags(C.current) == (sentinel | C.PF_VCPU))
        }
        C.memset(&child.storage[0], 0xa5, sizeof(child.storage))
        C.vinix_linuxkpi_task_inherit(&child.storage[0], &child, child.pid, child.tgid, task)
        inherited := &C.task_struct(C.vinix_linuxkpi_task_view(&child.storage[0], &child, child.pid, child.tgid, nil, 0, false))
        C.assert(flags(inherited) == 0 && C.strcmp(&inherited.comm[0], &task.comm[0]) == 0)
        model.must_exit = true
        C.assert(flags(C.current) == (sentinel | C.PF_VCPU | C.PF_EXITING))
        model.must_exit = false
        for i in 0 .. 32 {
            C.assert(C.cond_resched() == 1)
            C.assert(flags(C.current) == (sentinel | C.PF_VCPU | C.PF_EXITING))
        }
        C.vtime_account_guest_exit()
        C.assert(flags(C.current) == (sentinel | C.PF_EXITING))
        C.vtime_account_guest_enter()
        C.__atomic_store_n(&model.dead, true, i32(3))
        C.vinix_linuxkpi_task_dead(task)
        C.assert(C.__atomic_load_n(&task.__state, 2) == C.TASK_DEAD)
        C.assert(flags(task) == (sentinel | C.PF_VCPU | C.PF_EXITING))
        C.assert(usize(C.current) == usize(task) && flags(C.current) == (sentinel | C.PF_VCPU | C.PF_EXITING))
        C.put_task_struct(task)
        C.assert(model.pins == 0)
        C.__atomic_store_n(&model.dead, false, i32(0))
        C.vinix_linuxkpi_task_init(&model.storage[0], &model, model.pid, model.tgid, c'reused', 6)
        C.assert(flags(C.current) == 0 && C.task_is_running(C.current))
        C.assert(C.pthread_mutex_destroy(&model.queue_lock) == 0)
        C.assert(C.pthread_cond_destroy(&model.queue_changed) == 0)
        C.vmh_native_task = previous
    }
}
struct LateView {
mut:
    model C.native_task_model
    started u32
    proceed u32
}
@[export: 'vmh_task_flag_late_view_worker']
pub fn late_view_worker(argument voidptr) voidptr {
    unsafe {
        test := &LateView(argument)
        C.__atomic_store_n(&test.started, u32(1), i32(3))
        for C.__atomic_load_n(&test.proceed, 2) == 0 { C.vinix_linuxkpi_spin_wait() }
        for i in 0 .. 256 {
            task := &C.task_struct(C.vinix_linuxkpi_task_view(&test.model.storage[0], &test.model,
                test.model.pid, test.model.tgid, c'late-view', 9, false))
            C.assert(flags(task) & sentinel == sentinel)
        }
        return nil
    }
}
fn late_exit() {
    unsafe {
        for iteration in 0 .. 64 {
            mut test := LateView{model: C.native_task_model{pid: 741, tgid: 741}}
            C.vmh_model_queue_init(&test.model)
            C.vinix_linuxkpi_task_init(&test.model.storage[0], &test.model, 741, 741, c'initial', 7)
            task := C.get_task_struct(&C.task_struct(&test.model.storage[0]))
            task.flags = sentinel | C.PF_VCPU
            mut native_thread := C.pthread_t{}
            C.assert(C.pthread_create(&native_thread, nil, C.vmh_task_flag_late_view_worker, &test) == 0)
            for C.__atomic_load_n(&test.started, 2) == 0 { C.vinix_linuxkpi_spin_wait() }
            C.__atomic_store_n(&test.proceed, u32(1), i32(3))
            C.vinix_linuxkpi_task_dead(task)
            C.assert(C.pthread_join(native_thread, nil) == 0)
            C.assert(C.__atomic_load_n(&task.__state, 2) == C.TASK_DEAD)
            C.assert(flags(task) == (sentinel | C.PF_VCPU | C.PF_EXITING))
            C.assert(usize(C.vinix_linuxkpi_task_view(&test.model.storage[0], &test.model, 741, 741, nil, 0, false)) == usize(task))
            C.assert(flags(task) == (sentinel | C.PF_VCPU | C.PF_EXITING))
            C.put_task_struct(task)
            C.assert(test.model.pins == 0)
            C.assert(C.pthread_mutex_destroy(&test.model.queue_lock) == 0)
            C.assert(C.pthread_cond_destroy(&test.model.queue_changed) == 0)
        }
    }
}
struct Wake {
mut:
    task &C.task_struct = unsafe { nil }
    result i32
}
@[export: 'vmh_task_flag_wake_worker']
pub fn wake_worker(argument voidptr) voidptr {
    unsafe {
        test := &Wake(argument)
        test.result = C.wake_up_process(test.task)
        C.assert(C.vmh_interrupts && C.vmh_preempt_depth == 0)
        return nil
    }
}
fn exit_during_wake() {
    unsafe {
        for iteration in 0 .. 64 {
            mut model := C.native_task_model{pid: 751, tgid: 751}
            C.vmh_model_queue_init(&model)
            C.vinix_linuxkpi_task_init(&model.storage[0], &model, 751, 751, c'wake-exit', 9)
            task := C.get_task_struct(&C.task_struct(&model.storage[0]))
            task.flags = sentinel | C.PF_VCPU
            C.__atomic_store_n(&task.__state, C.TASK_UNINTERRUPTIBLE, i32(0))
            mut test := Wake{task: task, result: -1}
            C.assert(C.pthread_mutex_lock(&model.queue_lock) == 0)
            mut native_thread := C.pthread_t{}
            C.assert(C.pthread_create(&native_thread, nil, C.vmh_task_flag_wake_worker, &test) == 0)
            for C.__atomic_load_n(&task.__state, 0) != C.TASK_RUNNING { C.vinix_linuxkpi_spin_wait() }
            C.__atomic_store_n(&model.dead, true, i32(3))
            C.assert(C.pthread_mutex_unlock(&model.queue_lock) == 0)
            C.assert(C.pthread_join(native_thread, nil) == 0)
            C.assert(test.result == 0)
            C.assert(C.__atomic_load_n(&task.__state, 2) == C.TASK_DEAD)
            C.assert(flags(task) == (sentinel | C.PF_VCPU | C.PF_EXITING))
            C.vinix_linuxkpi_task_dead(task)
            C.assert(flags(task) == (sentinel | C.PF_VCPU | C.PF_EXITING))
            C.assert(C.wake_up_process(task) == 0)
            C.put_task_struct(task)
            C.assert(model.pins == 0)
            C.assert(C.pthread_mutex_destroy(&model.queue_lock) == 0)
            C.assert(C.pthread_cond_destroy(&model.queue_changed) == 0)
        }
    }
}
@[export: 'vmh_task_flag_tests']
pub fn tests() {
    before := C.vmh_live_pages
    previous_failure := C.vmh_fail_allocation
    unsafe {
        C.vmh_fail_allocation = true
        current_flags()
        late_exit()
        exit_during_wake()
        C.vmh_fail_allocation = previous_failure
        C.assert(C.vmh_live_pages == before && C.vmh_interrupts && C.vmh_preempt_depth == 0)
    }
}
