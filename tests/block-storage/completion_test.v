module nvme

import memory
import stat
import x86.hpet as hpet_clock

__global simulated_pair &NVMEQueuePair
__global simulated_mode int
__global completion_code u16

fn hardware_tick() {
	mut pair := simulated_pair
	mut regs := pair.parent_controller.regs
	if simulated_mode >= 2 {
		if simulated_mode == 2 && regs.cc & 1 == 0 { regs.csts = 0 }
		return
	}
	if unsafe { *pair.submission_doorbell } == u32(pair.sq_tail) {
		tail := if pair.sq_tail == 0 { pair.entry_cnt - 1 } else { pair.sq_tail - 1 }
		command := unsafe { pair.submission_queue[tail] }
		unsafe {
			pair.completion_queue[pair.cq_head] = NVMECompletion{
				cid:     command.cid
				sq_id:   u16(pair.qid)
				sq_head: u16(pair.sq_tail)
				status:  (completion_code << 1) | if pair.phase { u16(1) } else { u16(0) }
			}
		}
	}
}

fn setup(mode int) &NVMEQueuePair {
	mut controller := &NVMEController{
		regs:          &NVMERegisters{ cc: 1, csts: 1 }
		controller_id: unsafe { nil }
		admin_queue:   unsafe { nil }
	}
	mut pair := &NVMEQueuePair{
		qid:                 7
		entry_cnt:           2
		phase:               true
		parent_controller:   controller
		submission_queue:    unsafe { &NVMECommand(malloc(int(2 * sizeof(NVMECommand)))) }
		completion_queue:    unsafe { &NVMECompletion(calloc(2, sizeof(NVMECompletion))) }
		submission_doorbell: unsafe { &u32(calloc(1, 4)) }
		completion_doorbell: unsafe { &u32(calloc(1, 4)) }
	}
	pair.cid_bitmap.initialise(2)
	controller.queue_list << pair
	simulated_pair = pair
	simulated_mode = mode
	completion_code = 0
	hpet_clock.set_hook(hardware_tick)
	return pair
}

fn test_completions_release_cids_wrap_phase_and_ring_cq() {
	mut pair := setup(0)
	for _ in 0 .. 8 {
		mut command := NVMECommand{}
		assert pair.send_cmd_and_wait(mut command, -1) == 0
		assert command.cid == 0
		assert unsafe { *pair.completion_doorbell } == pair.cq_head
		assert !pair.parent_controller.failed
	}
	assert pair.phase
	// A failed command still consumes the CQ entry and returns its status.
	completion_code = 0x80
	mut failed := NVMECommand{}
	assert pair.send_cmd_and_wait(mut failed, -1) == 0x80
	assert pair.cq_head == 1
	completion_code = 0
	mut next := NVMECommand{}
	assert pair.send_cmd_and_wait(mut next, -1) == 0
	assert next.cid == 0
}

fn namespace(pair &NVMEQueuePair) &NVMENamespace {
	return &NVMENamespace{
		parent_controller: pair.parent_controller
		identity:          unsafe { nil }
		nsid:              42
		max_prps:          32
		stat:              stat.Stat{ blksize: 512, size: 1024 * 1024 }
	}
}

fn test_flush_uses_namespace_and_propagates_device_error() {
	pair := setup(0)
	mut ns := namespace(pair)
	ns.sync(unsafe { nil }) or { assert false }
	command := unsafe { pair.submission_queue[0] }
	assert command.opcode == 0
	assert unsafe { command.private.rw.nsid } == 42
	assert unsafe { command.private.rw.prp1 } == 0
	assert unsafe { command.private.rw.prp2 } == 0
	completion_code = 2
	mut failed := false
	ns.sync(unsafe { nil }) or { failed = true }
	assert failed
}

fn test_timeout_quiescence_releases_dma_and_offline_refuses_late_completion() {
	pair := setup(2)
	mut ns := namespace(pair)
	buffer := unsafe { malloc(12288) }
	before := memory.allocated_pages()
	mut failed := false
	ns.transfer(buffer, 0, 12288, false) or { failed = true }
	assert failed
	assert pair.parent_controller.failed
	assert pair.parent_controller.dma_quiesced
	assert memory.allocated_pages() == before
	tail := pair.sq_tail
	// A late completion must never make an offline queue usable again.
	simulated_mode = 0
	failed = false
	ns.transfer(buffer, 0, 12288, false) or { failed = true }
	assert failed
	assert pair.sq_tail == tail
	assert memory.allocated_pages() == before
	unsafe { free(buffer) }
}

fn test_failed_disable_quarantines_only_submitted_dma() {
	pair := setup(3)
	mut ns := namespace(pair)
	buffer := unsafe { malloc(12288) }
	before := memory.allocated_pages()
	mut failed := false
	ns.transfer(buffer, 0, 12288, true) or { failed = true }
	assert failed
	assert pair.parent_controller.failed
	assert !pair.parent_controller.dma_quiesced
	// Three bounce pages and one PRP list remain owned by the device.
	assert memory.allocated_pages() == before + 4
	tail := pair.sq_tail
	failed = false
	ns.transfer(buffer, 0, 12288, true) or { failed = true }
	assert failed
	assert pair.sq_tail == tail
	assert memory.allocated_pages() == before + 4
	unsafe { free(buffer) }
}

fn test_read_write_errors_release_prp_and_bounce() {
	pair := setup(0)
	mut ns := namespace(pair)
	buffer := unsafe { malloc(12288) }
	before := memory.allocated_pages()
	completion_code = 1
	mut failed := false
	ns.transfer(buffer, 0, 12288, false) or { failed = true }
	assert failed
	assert memory.allocated_pages() == before
	assert !pair.parent_controller.failed
	completion_code = 0
	assert ns.transfer(buffer, 0, 12288, true) or { i64(-1) } == 12288
	assert memory.allocated_pages() == before
	unsafe { free(buffer) }
}
