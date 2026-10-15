// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module irqworkfixture

#include "linuxkpi_irq_work_fixture_v_contract.h"

struct C.irq_work {}
struct C.callback_head {}
type Callback = fn (&C.irq_work)
fn C.init_irq_work(&C.irq_work, Callback)
fn C.IRQ_WORK_INIT_LAZY(Callback) C.irq_work
fn C.IRQ_WORK_INIT_HARD(Callback) C.irq_work
fn C.irq_work_queue(&C.irq_work) bool
fn C.irq_work_queue_on(&C.irq_work, i32) bool
fn C.irq_work_sync(&C.irq_work)
fn C.irq_work_is_pending(&C.irq_work) bool
fn C.irq_work_is_busy(&C.irq_work) bool
fn C.kvfree_call_rcu(&C.callback_head, voidptr)

@[export: 'vinix_linuxkpi_irqwork_fixture_bytes']
pub fn work_bytes() u32 { return u32(sizeof(C.irq_work)) }
@[export: 'vinix_linuxkpi_irqwork_fixture_init']
pub fn work_init(storage voidptr, callback Callback, flags u32) i32 {
	unsafe {
		mut work := &C.irq_work(storage)
		if flags == 0 { C.init_irq_work(work, callback) }
		else if flags == 4 { *work = C.IRQ_WORK_INIT_LAZY(callback) }
		else if flags == 8 { *work = C.IRQ_WORK_INIT_HARD(callback) }
		else { return -22 }
		return 0
	}
}
@[export: 'vinix_linuxkpi_irqwork_fixture_queue']
pub fn work_queue(storage voidptr, target i32) bool {
	unsafe { return if target < 0 { C.irq_work_queue(&C.irq_work(storage)) }
		else { C.irq_work_queue_on(&C.irq_work(storage), target) } }
}
@[export: 'vinix_linuxkpi_irqwork_fixture_sync']
pub fn work_sync(storage voidptr) { unsafe { C.irq_work_sync(&C.irq_work(storage)) } }
@[export: 'vinix_linuxkpi_irqwork_fixture_pending']
pub fn work_pending(storage voidptr) bool { unsafe { return C.irq_work_is_pending(&C.irq_work(storage)) } }
@[export: 'vinix_linuxkpi_irqwork_fixture_busy']
pub fn work_busy(storage voidptr) bool { unsafe { return C.irq_work_is_busy(&C.irq_work(storage)) } }
@[export: 'vinix_linuxkpi_irqwork_fixture_defer']
pub fn work_defer(storage voidptr, head voidptr) { unsafe { C.kvfree_call_rcu(&C.callback_head(head), storage) } }
