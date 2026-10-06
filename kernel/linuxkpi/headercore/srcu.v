// SPDX-License-Identifier: GPL-2.0-or-later
// Native V calls the unchanged upstream work/SRCU header primitives directly.
// The separate object keeps those headers out of the main generated kernel.
@[translated]
module headercore

#include "linuxkpi_srcu_v_contract.h"

struct C.work_struct {}
struct C.delayed_work {}
struct C.srcu_data {}
struct C.vks_data_alignment_probe { prefix u8, data C.srcu_data }
type HeaderWorkFn = fn (&C.work_struct)
fn C.INIT_WORK(&C.work_struct, HeaderWorkFn)
fn C.INIT_DELAYED_WORK(&C.delayed_work, HeaderWorkFn)
fn C.vinix_linuxkpi_srcu_gp_work(&C.work_struct)
fn C.vinix_linuxkpi_srcu_callback_work(&C.work_struct)
@[c_extern]
__global C.system_unbound_wq voidptr
fn C.preempt_disable()
fn C.preempt_enable()
fn C.preempt_count() u32
fn C.vinix_linuxkpi_cpu_id() u32
fn C.queue_work(voidptr, voidptr) bool
fn C.queue_delayed_work(voidptr, voidptr, usize) bool

@[export: 'vks_init_work']
pub fn srcu_init_work(storage voidptr, callback voidptr) {
	unsafe { C.INIT_WORK(&C.work_struct(storage), HeaderWorkFn(callback)) }
}
@[export: 'vks_init_delayed_work']
pub fn srcu_init_delayed_work(storage voidptr, callback voidptr) {
	unsafe { C.INIT_DELAYED_WORK(&C.delayed_work(storage), HeaderWorkFn(callback)) }
}
@[export: 'vks_gp_callback']
pub fn srcu_gp_callback() voidptr { return voidptr(C.vinix_linuxkpi_srcu_gp_work) }
@[export: 'vks_cblist_callback']
pub fn srcu_cblist_callback() voidptr { return voidptr(C.vinix_linuxkpi_srcu_callback_work) }
@[export: 'vks_unbound_ready']
pub fn srcu_unbound_ready() bool { return C.system_unbound_wq != unsafe { nil } }
@[export: 'vks_preempt_disable']
pub fn srcu_preempt_disable() { C.preempt_disable() }
@[export: 'vks_preempt_enable']
pub fn srcu_preempt_enable() { C.preempt_enable() }
@[export: 'vks_preempt_count']
pub fn srcu_preempt_count() u32 { return C.preempt_count() }
@[export: 'vks_cpu_id']
pub fn srcu_cpu_id() u32 { return C.vinix_linuxkpi_cpu_id() }
@[export: 'vks_data_alignment']
pub fn srcu_data_alignment() usize { return __offsetof(C.vks_data_alignment_probe, data) }
@[export: 'vks_queue_work']
pub fn srcu_queue_work(queue voidptr, work voidptr) bool { return C.queue_work(queue, work) }
@[export: 'vks_queue_delayed_work']
pub fn srcu_queue_delayed_work(queue voidptr, work voidptr, delay usize) bool { return C.queue_delayed_work(queue, work, delay) }
