// SPDX-License-Identifier: GPL-2.0-or-later
// Typed original IRQ-work ABI; native record ownership lives in compatcore.
@[translated]
module headercore

#include "linuxkpi_irq_work_v_contract.h"

struct C.irq_work {}
fn C.vkiw_queue(voidptr, i32) bool
fn C.vkiw_drain(u32)
fn C.vkiw_tick(u32)
fn C.vkiw_needs_cpu() bool
fn C.vkiw_single(voidptr)
fn C.vkiw_sync(voidptr)
fn C.vkiw_raise()

@[export: 'irq_work_queue']
pub fn irq_work_queue(work &C.irq_work) bool { return C.vkiw_queue(work, -1) }
@[export: 'irq_work_queue_on']
pub fn irq_work_queue_on(work &C.irq_work, cpu i32) bool {
	// The local sentinel belongs only to the private helper. Every negative
	// public explicit CPU must fail validation before claiming the object.
	return C.vkiw_queue(work, if cpu < 0 { i32(-2) } else { cpu })
}
@[export: 'irq_work_run']
pub fn irq_work_run() { C.vkiw_drain(C.vinix_linuxkpi_cpu_id()) }
@[export: 'irq_work_tick']
pub fn irq_work_tick() { C.vkiw_tick(C.vinix_linuxkpi_cpu_id()) }
@[export: 'irq_work_needs_cpu']
pub fn irq_work_needs_cpu() bool { return C.vkiw_needs_cpu() }
@[export: 'irq_work_single']
pub fn irq_work_single(work voidptr) { C.vkiw_single(work) }
@[export: 'irq_work_sync']
pub fn irq_work_sync(work &C.irq_work) { C.vkiw_sync(work) }
@[export: 'arch_irq_work_raise']
pub fn irq_work_raise() { C.vkiw_raise() }
