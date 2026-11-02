// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Telling an NVMe controller that power is about to go.
//
// A flush makes the data durable; the shutdown notification lets the drive
// finish its own bookkeeping -- the mapping tables it keeps in volatile
// memory -- so that it does not have to rebuild them from its journal the
// next time it is powered, and does not count an unsafe shutdown against
// itself. The controller is asked with CC.SHN and says it is done in
// CSTS.SHST; the specification lets it take as long as its RTD3 entry
// latency, which is seconds on a slow drive.
module nvme

import devcore

// CC.SHN, bits 15:14: 01 asks for a normal shutdown.
const cc_shutdown_mask = u32(3) << 14
const cc_shutdown_normal = u32(1) << 14
// CSTS.SHST, bits 3:2: 10 says shutdown processing is complete.
const csts_shutdown_mask = u32(3) << 2
const csts_shutdown_complete = u32(2) << 2

const shutdown_timeout_ns = 10 * devcore.second

fn shutdown_complete(context voidptr) bool {
	mut volatile regs := unsafe { &NVMERegisters(context) }
	// All ones is a controller that is gone, which is as shut down as it gets.
	return regs.csts == 0xffffffff || regs.csts & csts_shutdown_mask == csts_shutdown_complete
}

// Before power off or reset. The caller has flushed the filesystems; from
// here on the controller takes no more requests.
fn controller_shutdown(mut dev devcore.Device) {
	mut controller := unsafe { &NVMEController(dev.driver_data) }
	if controller == unsafe { nil } || controller.regs == unsafe { nil } {
		return
	}
	controller.l.acquire()
	controller.failed = true
	controller.l.release()
	mut volatile regs := controller.regs
	regs.cc = (regs.cc & ~cc_shutdown_mask) | cc_shutdown_normal
	if !devcore.sleep_until(shutdown_complete, voidptr(controller.regs), shutdown_timeout_ns, 1) {
		print('nvme: the controller did not finish shutting down in time\n')
	}
}

// ── Across a sleep ──────────────────────────────────────────────────────────
//
// Going down is the shutdown above with one difference: the controller is
// wanted back. Its caches are flushed, requests are held from then on
// (NVMEController.wait_awake()) and it is given the shutdown notification, so
// that a suspend to RAM that cuts its power costs it no more than a power
// off would.
//
// Coming back, it is set up from nothing whatever the sleep was -- a
// controller that has been told to shut down has to be reset before it takes
// another command in any case. The queues' memory and the namespaces are the
// driver's and are still there: the controller is disabled, the queues are
// emptied, it is told where the admin queue is and enabled, and the I/O
// queues are created again.

const ready_poll_ms = u64(1)

fn controller_not_ready(context voidptr) bool {
	mut volatile regs := unsafe { &NVMERegisters(context) }
	return regs.csts == 0xffffffff || regs.csts & 1 == 0
}

fn controller_ready_or_dead(context voidptr) bool {
	mut volatile regs := unsafe { &NVMERegisters(context) }
	return regs.csts & 3 != 0
}

// Hold a request until the controller is awake again. Called before its lock
// is taken.
fn (c &NVMEController) wait_awake() {
	for c.asleep {
		devcore.sleep_ms(10)
	}
}

// Empty a queue pair: what the controller knew of it is gone.
fn (mut pair NVMEQueuePair) rewind() {
	unsafe {
		C.memset(voidptr(pair.submission_queue), 0, uint(pair.entry_cnt * sizeof(NVMECommand)))
		C.memset(voidptr(pair.completion_queue), 0, uint(pair.entry_cnt * sizeof(NVMECompletion)))
	}
	pair.sq_head = 0
	pair.sq_tail = 0
	pair.cq_head = 0
	pair.cq_tail = 0
	pair.phase = true
}

// Create an I/O queue pair on the controller again, as NVMEQueuePair's
// initialise() did. With the controller's lock.
fn (mut pair NVMEQueuePair) create_again() bool {
	mut controller := pair.parent_controller
	mut create_cq := unsafe { &NVMECommand(C.vinix_stack_alloc(sizeof(NVMECommand))) }
	unsafe {
		*create_cq = NVMECommand{}
		create_cq.opcode = opcode_create_cq
		create_cq.private.create_cq.prp1 = u64(pair.completion_queue) - higher_half
		create_cq.private.create_cq.cqid = u16(pair.qid)
		create_cq.private.create_cq.qsize = u16(pair.entry_cnt - 1)
		create_cq.private.create_cq.irq_vector = u16(pair.irq)
		create_cq.private.create_cq.cq_flags = 1 << 0
	}
	if controller.admin_queue.exchange(mut create_cq, -1) != 0 {
		return false
	}
	mut create_sq := unsafe { &NVMECommand(C.vinix_stack_alloc(sizeof(NVMECommand))) }
	unsafe {
		*create_sq = NVMECommand{}
		create_sq.opcode = opcode_create_sq
		create_sq.private.create_sq.prp1 = u64(pair.submission_queue) - higher_half
		create_sq.private.create_sq.cqid = u16(pair.qid)
		create_sq.private.create_sq.sqid = u16(pair.qid)
		create_sq.private.create_sq.qsize = u16(pair.entry_cnt - 1)
		create_sq.private.create_sq.sq_flags = (1 << 0) | (1 << 1)
	}
	return controller.admin_queue.exchange(mut create_sq, -1) == 0
}

fn controller_suspend(mut dev devcore.Device) bool {
	mut controller := unsafe { &NVMEController(dev.driver_data) }
	if controller == unsafe { nil } || controller.regs == unsafe { nil } {
		return true
	}
	// A controller that had failed is left as it is; resume tries it afresh.
	if !controller.failed {
		for mut namespace in controller.namespace_list {
			namespace.sync(unsafe { nil }) or {}
		}
	}
	controller.l.acquire()
	controller.asleep = true
	controller.l.release()
	mut volatile regs := controller.regs
	regs.cc = (regs.cc & ~cc_shutdown_mask) | cc_shutdown_normal
	if !devcore.sleep_until(shutdown_complete, voidptr(controller.regs), shutdown_timeout_ns, ready_poll_ms) {
		print('nvme: the controller did not finish shutting down before the sleep\n')
	}
	return true
}

fn controller_resume(mut dev devcore.Device) bool {
	mut controller := unsafe { &NVMEController(dev.driver_data) }
	if controller == unsafe { nil } || controller.regs == unsafe { nil } {
		return true
	}
	// Memory decoding and bus mastering, which a loss of power clears.
	dev.pci.update_command(0, 0x6)
	ok := controller.restart()
	controller.l.acquire()
	controller.failed = !ok
	// Awake either way: with the controller failed, held requests fail
	// instead of waiting for ever.
	controller.asleep = false
	controller.l.release()
	return ok
}

// Disable, empty the queues, enable, create the I/O queues. Nothing else
// reaches the controller meanwhile: it is asleep to everyone else.
fn (mut c NVMEController) restart() bool {
	mut volatile regs := c.regs
	timeout := c.ready_timeout_ns()
	regs.intms = u32(-1)
	regs.cc = regs.cc & ~(u32(1) | cc_shutdown_mask)
	if !devcore.sleep_until(controller_not_ready, voidptr(c.regs), timeout, ready_poll_ms) {
		print('nvme: the controller would not be disabled after the sleep\n')
		return false
	}
	c.admin_queue.rewind()
	for mut pair in c.queue_list {
		pair.rewind()
	}
	regs.aqa = u32((c.queue_entries - 1) << 16 | (c.queue_entries - 1))
	regs.asq = u64(c.admin_queue.submission_queue) - higher_half
	regs.acq = u64(c.admin_queue.completion_queue) - higher_half
	// As initialise() sets it: the NVM command set, round robin, 64-byte
	// submission and 16-byte completion entries, enabled.
	regs.cc = (6 << 16) | (4 << 20) | (1 << 0)
	if !devcore.sleep_until(controller_ready_or_dead, voidptr(c.regs), timeout, ready_poll_ms)
		|| regs.csts & 2 != 0 {
		print('nvme: the controller did not come back from the sleep\n')
		return false
	}
	c.l.acquire()
	c.failed = false
	mut created := true
	for mut pair in c.queue_list {
		if !pair.create_again() {
			created = false
			break
		}
	}
	c.l.release()
	if !created {
		print('nvme: the I/O queues could not be created again after the sleep\n')
	}
	return created
}
