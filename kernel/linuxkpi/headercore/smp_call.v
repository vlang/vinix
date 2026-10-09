// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module headercore

#include "linuxkpi_smp_call_v_contract.h"

type HeaderSmpCallFn = fn (voidptr)
type HeaderSmpCondFn = fn (i32, voidptr) bool
struct C.llist_node {
mut:
	next &C.llist_node
}
struct C.__call_single_node {
mut:
	llist C.llist_node
	u_flags u32
}
struct C.__call_single_data {
mut:
	node C.__call_single_node
	func HeaderSmpCallFn
	info voidptr
}
@[typedef]
struct C.call_single_data_t {}
@[typedef]
struct C.vks_smp_const_void {}
@[typedef]
struct C.vks_smp_const_cpumask {}

fn C.vks_smp_stack_init(&C.call_single_data_t)
fn C.vks_smp_borrow_mask(C.vks_smp_const_cpumask) C.vks_smp_const_void
fn C.vks_smp_original_online_mask() C.vks_smp_const_void
fn C.vks_smp_single(u32, i32, HeaderSmpCallFn, voidptr, voidptr) i32
fn C.vks_smp_async(i32, voidptr) i32
fn C.vks_smp_many(C.vks_smp_const_void, HeaderSmpCallFn, voidptr, bool, bool, HeaderSmpCondFn)
fn C.vinix_linuxkpi_preempt_disable()
fn C.vinix_linuxkpi_preempt_enable()

@[export: 'vks_smp_csd_flags']
pub fn smp_csd_flags(csd voidptr) &u32 {
	return unsafe { &(&C.__call_single_data(csd)).node.u_flags }
}
@[export: 'vks_smp_csd_next']
pub fn smp_csd_next(csd voidptr) voidptr {
	return unsafe { (&C.__call_single_data(csd)).node.llist.next }
}
@[export: 'vks_smp_csd_set_next']
pub fn smp_csd_set_next(csd voidptr, next voidptr) {
	unsafe { (&C.__call_single_data(csd)).node.llist.next = &C.llist_node(next) }
}
@[export: 'vks_smp_csd_function']
pub fn smp_csd_function(csd voidptr) HeaderSmpCallFn {
	return unsafe { (&C.__call_single_data(csd)).func }
}
@[export: 'vks_smp_csd_info']
pub fn smp_csd_info(csd voidptr) voidptr {
	return unsafe { (&C.__call_single_data(csd)).info }
}
@[export: 'vks_smp_csd_set_callback']
pub fn smp_csd_set_callback(csd voidptr, callback HeaderSmpCallFn, info voidptr) {
	unsafe {
		mut original := &C.__call_single_data(csd)
		original.func = callback
		original.info = info
	}
}
@[export: 'vks_smp_mask_has']
pub fn smp_mask_has(mask C.vks_smp_const_void, cpu u32) bool {
	return unsafe { C.cpumask_test_cpu(i32(cpu), &C.cpumask(mask)) }
}
@[export: 'vks_smp_online_mask']
pub fn smp_online_mask() C.vks_smp_const_void {
	return C.vks_smp_original_online_mask()
}

@[export: 'smp_call_function_single']
pub fn smp_call_function_single(cpu i32, callback HeaderSmpCallFn, info voidptr, wait i32) i32 {
	// The original typedef makes this actual stack object 32-byte aligned.
	// Its unsafe direct address is borrowed only until the synchronous wait ends.
	mut stack_csd := C.call_single_data_t{}
	unsafe { C.vks_smp_stack_init(&stack_csd) }
	return unsafe { C.vks_smp_single(u32(wait != 0), cpu, callback, info, &stack_csd) }
}
@[export: 'smp_call_function_single_async']
pub fn smp_call_function_single_async(cpu i32, csd &C.__call_single_data) i32 {
	return C.vks_smp_async(cpu, csd)
}
@[export: 'smp_call_function_many']
pub fn smp_call_function_many(mask C.vks_smp_const_cpumask, callback HeaderSmpCallFn, info voidptr, wait bool) {
	C.vks_smp_many(C.vks_smp_borrow_mask(mask), callback, info, wait, false, unsafe { nil })
}
@[export: 'smp_call_function']
pub fn smp_call_function(callback HeaderSmpCallFn, info voidptr, wait i32) {
	C.vinix_linuxkpi_preempt_disable()
	C.vks_smp_many(smp_online_mask(), callback, info, wait != 0, false, unsafe { nil })
	C.vinix_linuxkpi_preempt_enable()
}
@[export: 'on_each_cpu_cond_mask']
pub fn on_each_cpu_cond_mask(condition HeaderSmpCondFn, callback HeaderSmpCallFn, info voidptr, wait bool, mask C.vks_smp_const_cpumask) {
	C.vinix_linuxkpi_preempt_disable()
	C.vks_smp_many(C.vks_smp_borrow_mask(mask), callback, info, wait, true, condition)
	C.vinix_linuxkpi_preempt_enable()
}
