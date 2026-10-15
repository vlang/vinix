// SPDX-License-Identifier: GPL-2.0-or-later
// Typed original Linux/pthread ownership at the native ordinary-RCU boundary.
@[translated]
module headercore

#include "linuxkpi_rcu_v_contract.h"

fn C.vkr_rcu_call(voidptr, fn (&C.callback_head))
fn C.vkr_kvfree(voidptr)
fn C.vkr_kvfree_call_rcu(voidptr, voidptr)
fn C.vkr_rcu_synchronize(bool)
fn C.vkr_rcu_barrier()
fn C.vkr_rcu_get_state() u64
fn C.vkr_rcu_start_poll() u64
fn C.vkr_rcu_poll(u64) bool
fn C.vkr_rcu_cond(u64)
fn C.vkr_rcu_gp_worker(voidptr) voidptr
fn C.vkr_rcu_callback_worker(voidptr) voidptr
fn C.vinix_linuxkpi_test_thread_reap_ready(voidptr) bool
fn C.vkr_rcu_host_worker_enter()
fn C.vkr_rcu_host_worker_leave()
fn C.vkr_rcu_host_create_error() i32

@[export: 'call_rcu']
pub fn rcu_call(head &C.callback_head, callback fn (&C.callback_head)) {
	C.vkr_rcu_call(head, callback)
}
@[export: 'kvfree']
pub fn rcu_kvfree(base C.vhp_const_voidp) { C.vkr_kvfree(voidptr(base)) }
@[export: 'kvfree_call_rcu']
pub fn rcu_kvfree_call(head &C.callback_head, base voidptr) { C.vkr_kvfree_call_rcu(head, base) }
@[export: 'synchronize_rcu']
pub fn rcu_synchronize() { C.vkr_rcu_synchronize(false) }
@[export: 'synchronize_rcu_expedited']
pub fn rcu_synchronize_expedited() { C.vkr_rcu_synchronize(true) }
@[export: 'rcu_barrier']
pub fn rcu_callbacks_barrier() { C.vkr_rcu_barrier() }
@[export: 'get_state_synchronize_rcu']
pub fn rcu_get_state() usize { return usize(C.vkr_rcu_get_state()) }
@[export: 'start_poll_synchronize_rcu']
pub fn rcu_start_poll() usize { return usize(C.vkr_rcu_start_poll()) }
@[export: 'poll_state_synchronize_rcu']
pub fn rcu_poll_state(cookie usize) bool { return C.vkr_rcu_poll(u64(cookie)) }
@[export: 'cond_synchronize_rcu']
pub fn rcu_cond_synchronize(cookie usize) { C.vkr_rcu_cond(u64(cookie)) }

@[export: 'vkr_rcu_worker_function']
pub fn rcu_worker_function(callback bool) voidptr {
	return if callback { voidptr(C.vkr_rcu_callback_worker) } else { voidptr(C.vkr_rcu_gp_worker) }
}
@[export: 'vkr_rcu_pthread_create']
pub fn rcu_pthread_create(storage voidptr, callback voidptr, argument voidptr) i32 {
	$if linuxkpi_host_test ? {
		injected := C.vkr_rcu_host_create_error()
		if injected != 0 { return injected }
	}
	return unsafe { C.pthread_create(storage, nil, HeaderThreadFn(callback), argument) }
}
@[export: 'vkr_rcu_pthread_join']
pub fn rcu_pthread_join(id u64) i32 {
	mut native_id := C.pthread_t{}
	unsafe { C.memcpy(&native_id, &id, sizeof(C.pthread_t)) }
	return unsafe { C.pthread_join(native_id, nil) }
}
@[export: 'vkr_rcu_worker_enter']
pub fn rcu_worker_enter() {
	$if linuxkpi_host_test ? { C.vkr_rcu_host_worker_enter() }
}
@[export: 'vkr_rcu_thread_exit']
pub fn rcu_thread_exit() {
	$if linuxkpi_host_test ? { C.vkr_rcu_host_worker_leave() }
	unsafe { C.pthread_exit(nil) }
}
@[export: 'vkr_rcu_get_current']
pub fn rcu_get_current() voidptr { return C.get_task_struct(C.current) }
@[export: 'vkr_rcu_put_task']
pub fn rcu_put_task(task voidptr) { unsafe { C.put_task_struct(&C.task_struct(task)) } }
@[export: 'vkr_rcu_task_retired']
pub fn rcu_task_retired(task voidptr) bool {
	unsafe {
		retained := &C.task_struct(task)
		return C.__atomic_load_n(&retained.__state, 2) == C.TASK_DEAD
			&& C.vinix_linuxkpi_test_thread_reap_ready(retained.vinix_thread)
	}
}
