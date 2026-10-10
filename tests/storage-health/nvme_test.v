// SPDX-License-Identifier: GPL-2.0-or-later
module nvme

import memory
import resource
import errno
import klock
import x86.hpet as hpet_clock

__global health_pair &NVMEQueuePair
__global health_mode int
__global health_warning u8
__global health_commands int
__global health_page u64

// Real production submission/completion code runs against these doorbells.
// Only hardware DMA, time and reset acknowledgement are simulated.
fn health_tick() {
	assert klock.depth == 1
	mut pair := health_pair
	mut regs := pair.parent_controller.regs
	if regs.cc & 1 == 0 {
		if health_mode in [2, 4, 6]! { regs.csts = 0 }
		return
	}
	if health_mode in [2, 3, 4, 5, 6, 7]! {
		// Modes 4/5 time out after a successful IDENTIFY; 6/7 return CFS.
		if health_commands != 0 || health_mode in [2, 3, 6, 7]! {
			if health_mode in [6, 7]! { regs.csts |= 2 }
			if health_mode in [2, 4, 6]! && regs.cc & 1 == 0 { regs.csts = 0 }
			return
		}
	}
	if unsafe { *pair.submission_doorbell } != u32(pair.sq_tail) { return }
	previous := if pair.sq_tail == 0 { pair.entry_cnt - 1 } else { pair.sq_tail - 1 }
	command := unsafe { pair.submission_queue[previous] }
	mut bytes := unsafe { &u8(command.private.identify.prp1) }
	assert u64(bytes) % 4096 == 0
	health_page = u64(bytes)
	for i in 0 .. 4096 { assert unsafe { bytes[i] } == 0 }
	assert command.flags == 0
	if command.opcode == opcode_identify {
		assert unsafe { command.private.identify.nsid == 0 && command.private.identify.cns == 1
			&& command.private.identify.prp2 == 0 }
		unsafe { bytes[24] = `M`; bytes[511] = 0xa5; bytes[4095] = 0xee }
	} else {
		assert command.opcode == 2
		assert unsafe { command.private.get_log.nsid == u32(-1)
			&& command.private.get_log.prp2 == 0
			&& command.private.get_log.cdw10 == 2 | (1 << 15) | (127 << 16)
			&& command.private.get_log.cdw11 == 0 && command.private.get_log.cdw12 == 0
			&& command.private.get_log.cdw13 == 0 && command.private.get_log.cdw14 == 0
			&& command.private.get_log.cdw15 == 0 }
		unsafe { bytes[0] = health_warning; bytes[32] = 0x12; bytes[47] = 0xfa; bytes[511] = 0x81 }
	}
	health_commands++
	unsafe {
		pair.completion_queue[pair.cq_head] = NVMECompletion{
			cid: if health_mode == 10 { command.cid + 1 } else { command.cid }
			sq_id: if health_mode == 11 { u16(pair.qid + 1) } else { u16(pair.qid) }
			sq_head: u16(pair.sq_tail)
			status: (if health_mode == 8 || (health_mode == 9 && command.opcode == 2) { u16(2) } else { u16(0) })
				| if pair.phase { u16(1) } else { u16(0) }
		}
	}
}

fn health_setup(mode int) &NVMENamespace {
	mut controller := &NVMEController{regs: &NVMERegisters{cc:1,csts:1},
		controller_id: &NVMEControllerID{}, admin_queue: unsafe { nil }}
	mut pair := &NVMEQueuePair{qid:0,entry_cnt:2,phase:true,parent_controller:controller,
		submission_queue:unsafe { &NVMECommand(calloc(2,sizeof(NVMECommand))) },
		completion_queue:unsafe { &NVMECompletion(calloc(2,sizeof(NVMECompletion))) },
		submission_doorbell:unsafe { &u32(calloc(1,4)) },
		completion_doorbell:unsafe { &u32(calloc(1,4)) }}
	pair.cid_bitmap.initialise(2)
	controller.admin_queue=pair
	mut ns := &NVMENamespace{parent_controller:controller,identity:unsafe { nil },nsid:42}
	ns.stat.rdev=99
	health_pair = pair
	health_mode = mode
	health_warning = 0
	health_commands = 0
	health_page = 0
	memory.fail_alloc = false
	hpet_clock.set_hook(health_tick)
	return ns
}

fn test_health_real_command_encoding_payload_and_200_cycles_release_page() {
	mut ns := health_setup(0)
	before := memory.allocated_pages()
	for _ in 0 .. 200 {
		report := ns.block_health() or { panic('health failed') }
		assert report.version == 1 && report.protocol == 2 && report.flags == 15 && report.disk_id == 99
		assert report.identify[24] == `M` && report.identify[511] == 0xa5
		assert report.data[0] == 0 && report.data[32] == 0x12 && report.data[47] == 0xfa && report.data[511] == 0x81
		for value in report.reserved { assert value == 0 }
		assert memory.allocated_pages() == before && klock.depth == 0
	}
	assert health_commands == 400 && ns.metrics.failures == 0
	for warning in [u8(1), 2, 4, 8, 16, 32, 64, 128, 255]! {
		health_warning = warning
		report := ns.block_health() or { panic('warning query failed') }
		assert report.flags == 31 && report.data[0] == warning && memory.allocated_pages() == before
	}
	// The optional Resource interface dispatches the production NVMe backend.
	mut boxed := resource.Resource(ns)
	assert (resource.block_health(mut boxed) or { panic('dispatch failed') }).protocol == 2
}

fn test_health_completion_failures_stop_sequence_and_release_page() {
	for mode in [8, 9]! {
		mut ns := health_setup(mode)
		before := memory.allocated_pages()
		assert ns.block_health() == none && errno.get() == errno.eio
		assert memory.allocated_pages() == before && ns.metrics.failures == 1 && klock.depth == 0
		assert health_commands == if mode == 8 { 1 } else { 2 }
		assert !ns.parent_controller.failed
		// Failed completions were consumed; the queue can service the next query.
		health_mode = 0
		assert (ns.block_health() or { panic('completion not consumed') }).flags == 15
		assert memory.allocated_pages() == before
	}
}

fn test_health_timeout_fatal_and_wrong_completion_quarantine_only_owned_page() {
	for mode in [2, 3, 4, 5, 6, 7, 10, 11]! {
		mut ns := health_setup(mode)
		before := memory.allocated_pages()
		assert ns.block_health() == none && errno.get() == errno.eio
		assert ns.parent_controller.failed && ns.metrics.failures == 1 && klock.depth == 0
		// Wrong completions leave this model RDY=1, as does a refused disable.
		owned := mode in [3, 5, 7, 10, 11]!
		assert ns.parent_controller.dma_quiesced == !owned
		assert memory.allocated_pages() == before + if owned { u64(1) } else { u64(0) }
		tail := ns.parent_controller.admin_queue.sq_tail
		for _ in 0 .. 200 {
			assert ns.block_health() == none && errno.get() == errno.enodev
			assert ns.parent_controller.admin_queue.sq_tail == tail
			assert memory.allocated_pages() == before + if owned { u64(1) } else { u64(0) }
		}
		if owned {
			// Hardware stopped by the test owner, outside production's quarantine.
			ns.parent_controller.regs.csts = 0
			if health_page == 0 {
				previous := if tail == 0 { ns.parent_controller.admin_queue.entry_cnt - 1 } else { tail - 1 }
				health_page = unsafe { ns.parent_controller.admin_queue.submission_queue[previous].private.identify.prp1 }
			}
			memory.pmm_free(voidptr(health_page), 1)
		}
	}
}

fn test_health_allocation_failure_does_not_submit() {
	mut ns := health_setup(0)
	before := memory.allocated_pages()
	memory.fail_alloc = true
	assert ns.block_health() == none && errno.get() == errno.enomem
	assert health_commands == 0 && ns.parent_controller.admin_queue.sq_tail == 0
	assert ns.metrics.failures == 1 && memory.allocated_pages() == before
	memory.fail_alloc = false
}
