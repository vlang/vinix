// SPDX-License-Identifier: GPL-2.0-only
@[translated]
module headercore

#include "linuxkpi_workqueue_v_contract.h"

struct C.workqueue_struct {}
struct C.timer_list {}
@[export: 'vkwq_running']
@[cinit]
__global vkh_work_running C.vkw_list = C.vkw_list{next: unsafe { &vkh_work_running }, prev: unsafe { &vkh_work_running }}
@[export: 'vkwq_canceling']
@[cinit]
__global vkh_work_canceling C.vkw_list = C.vkw_list{next: unsafe { &vkh_work_canceling }, prev: unsafe { &vkh_work_canceling }}
@[export: 'vkwq_all']
@[cinit]
__global vkh_work_all C.vkw_list = C.vkw_list{next: unsafe { &vkh_work_all }, prev: unsafe { &vkh_work_all }}
@[export: 'system_wq']
__global vkh_system_wq &C.workqueue_struct
@[export: 'system_highpri_wq']
__global vkh_system_highpri_wq &C.workqueue_struct
@[export: 'system_unbound_wq']
__global vkh_system_unbound_wq &C.workqueue_struct
fn C.vinix_linuxkpi_work_worker(voidptr) voidptr
fn C.vinix_linuxkpi_pool_manager(voidptr) voidptr
fn C.vinix_linuxkpi_work_barrier(voidptr)
fn C.delayed_work_timer_fn(&C.timer_list)
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.pthread_exit(voidptr)
fn C.get_task_struct(&C.task_struct) &C.task_struct
fn C.put_task_struct(&C.task_struct)
fn C.__atomic_load_n(&u32, i32) u32
fn C.task_is_running(&C.task_struct) bool
fn C.vinix_linuxkpi_host_worker_enter()
fn C.vinix_linuxkpi_host_worker_leave()
fn C.vinix_linuxkpi_host_delayed_timer_gate(&C.timer_list)
fn C.vinix_linuxkpi_host_pool_publish_gate(&C.workqueue_struct, u32)
fn C.vinix_linuxkpi_workqueue_allocate(u32, i32) voidptr
fn C.vinix_linuxkpi_workqueue_name(voidptr) &char
fn C.vinix_linuxkpi_workqueue_start(voidptr) voidptr
fn C.vkr_format_entry(&char, usize, &char, voidptr, &u32) i32
fn C.vp_snprintf(&char, usize, C.vkh_const_char_p, voidptr) i32

@[export: 'vkwq_worker_callback']
pub fn workqueue_worker_callback() voidptr { return voidptr(C.vinix_linuxkpi_work_worker) }
@[export: 'vkwq_manager_callback']
pub fn workqueue_manager_callback() voidptr { return voidptr(C.vinix_linuxkpi_pool_manager) }
@[export: 'vkwq_barrier_callback']
pub fn workqueue_barrier_callback() voidptr { return voidptr(C.vinix_linuxkpi_work_barrier) }
@[export: 'vkwq_delayed_callback']
pub fn workqueue_delayed_callback() voidptr { return voidptr(C.delayed_work_timer_fn) }
@[export: 'vkwq_pthread_create']
pub fn workqueue_pthread_create(storage voidptr, callback voidptr, argument voidptr) i32 { return unsafe { C.pthread_create(storage, nil, HeaderThreadFn(callback), argument) } }
@[export: 'vkwq_pthread_join']
pub fn workqueue_pthread_join(id u64) i32 {
	mut native_id := C.pthread_t{}
	unsafe { C.memcpy(&native_id, &id, sizeof(C.pthread_t)) }
	return unsafe { C.pthread_join(native_id, nil) }
}
@[export: 'vkwq_get_current']
pub fn workqueue_get_current() voidptr { return C.get_task_struct(C.current) }
@[export: 'vkwq_put_task']
pub fn workqueue_put_task(task voidptr) { unsafe { C.put_task_struct(&C.task_struct(task)) } }
@[export: 'vkwq_task_state']
pub fn workqueue_task_state(task voidptr) u32 { return unsafe { C.__atomic_load_n(&(&C.task_struct(task)).__state, 2) } }
@[export: 'vkwq_current_running']
pub fn workqueue_current_running() bool { return C.task_is_running(C.current) }
@[export: 'vkwq_worker_enter']
pub fn workqueue_worker_enter() { $if linuxkpi_host_test ? { C.vinix_linuxkpi_host_worker_enter() } }
@[export: 'vkwq_worker_leave']
pub fn workqueue_worker_leave() { $if linuxkpi_host_test ? { C.vinix_linuxkpi_host_worker_leave() } $else { unsafe { C.pthread_exit(nil) } } }
@[export: 'vkwq_delayed_gate']
pub fn workqueue_delayed_gate(timer voidptr) { $if linuxkpi_host_test ? { unsafe { C.vinix_linuxkpi_host_delayed_timer_gate(&C.timer_list(timer)) } } }
@[export: 'vkwq_publish_gate']
pub fn workqueue_publish_gate(queue voidptr, cpu u32) { $if linuxkpi_host_test ? { unsafe { C.vinix_linuxkpi_host_pool_publish_gate(&C.workqueue_struct(queue), cpu) } } }
@[export: 'vkwq_warn_queue_cpu']
pub fn workqueue_warn_queue_cpu(invalid bool) { C.WARN_ON_ONCE(invalid) }
@[export: 'vkwq_warn_delayed_cpu']
pub fn workqueue_warn_delayed_cpu(invalid bool) { C.WARN_ON_ONCE(invalid) }
@[export: 'vkwq_warn_mod_cpu']
pub fn workqueue_warn_mod_cpu(invalid bool) { C.WARN_ON_ONCE(invalid) }
@[export: 'vkwq_warn_limit']
pub fn workqueue_warn_limit() { C.WARN_ON_ONCE(true) }

// The instruction-only native variadic prologue passes an addressable cursor.
// Name formatting borrows it synchronously before queue startup/rollback.
@[export: 'vinix_linuxkpi_alloc_workqueue_entry']
pub fn workqueue_allocate_entry(fmt C.vkh_const_char_p, flags u32, max_active i32, args voidptr) voidptr {
	unsafe {
		queue := C.vinix_linuxkpi_workqueue_allocate(flags, max_active)
		if queue == nil { return nil }
		name := C.vinix_linuxkpi_workqueue_name(queue)
		$if linuxkpi_host_test ? { C.vkr_format_entry(name, 32, &char(fmt), args, nil) } $else { C.vp_snprintf(name, 32, fmt, args) }
		return C.vinix_linuxkpi_workqueue_start(queue)
	}
}
