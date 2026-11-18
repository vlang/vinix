// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import gpu.agx.fw
import gpu.agx.event
import katomic
import aarch64.timer

// WorkError information remains attached to retained jobs until firmware
// actually retires them. A failure notification alone never frees GPU backing.
pub struct G13JobError {
pub:
	status u32
	fault_type u32
	unit u32
	sideband u32
	level u8
	is_read u8
	extra u32
	address u64
	vm_slot u32
}

pub fn (failure &G13JobError) fence_error() int {
	return match failure.status {
		2 { -61 } // ENODATA
		3 { -110 } // ETIMEDOUT
		5 { -125 } // ECANCELED
		6 { -19 } // ENODEV
		else { -5 } // EIO, including hardware faults and channel errors
	}
}

fn g13_error_at_stamp(expected u32, wait_value u32) bool {
	return i32(wait_value - expected) >= 0
}

fn (mut mgr GpuManager) mark_g13_slot_error_locked(slot u32, wait_value u32, failure G13JobError) {
	if slot >= event.max_stamps { return }
	for job in mgr.g13_compute_jobs {
		if job.submitted && !job.released && job.event_slot == slot
			&& g13_error_at_stamp(job.stamp_value, wait_value) && !event.stamp_value_completed(slot, job.stamp_value) {
			mut owned := unsafe { job }
			owned.error = if failure.status == 4 && owned.vm_slot != failure.vm_slot {
				G13JobError{status: 5}
			} else {
				failure
			}
		}
	}
	for job in mgr.g13_render_jobs {
		if !job.submitted || job.released { continue }
		if (job.vertex_event_slot == slot && g13_error_at_stamp(job.vertex_stamp_value, wait_value)
			&& !event.stamp_value_completed(slot, job.vertex_stamp_value))
			|| (job.fragment_event_slot == slot && g13_error_at_stamp(job.fragment_stamp_value, wait_value)
				&& !event.stamp_value_completed(slot, job.fragment_stamp_value)) {
			mut owned := unsafe { job }
			classified := if failure.status == 4 && owned.vm_slot != failure.vm_slot {
				G13JobError{status: 5}
			} else {
				failure
			}
			// A fault in either stage is the render pass's primary failure.
			// A later killed dependency must not hide the fault diagnostics.
			if owned.error.status == 0 || owned.error.status == 5 { owned.error = classified }
		}
	}
}

fn (mgr &GpuManager) g13_fault_error(default_status u32) G13JobError {
	if info := mgr.res.get_g13_fault_info() {
		return G13JobError{
			status: 4
			fault_type: u32(info.reason_code)
			unit: u32(info.unit_code)
			sideband: u32(info.sideband)
			level: info.level
			is_read: if info.read { u8(1) } else { u8(0) }
			extra: u32(info.unknown_5)
			address: info.address
			vm_slot: info.vm_slot
		}
	}
	return G13JobError{status: default_status}
}

// Caller holds mgr.lock. This is Asahi's mark_pending_events + recover:
// classify the firmware's pending stamp records, clear them, wait for the
// halt handshake, then acknowledge resume. Jobs stay mapped until their
// completion stamps advance after recovery.
fn (mut mgr GpuManager) recover_g13_fault_locked(culprit i32, default_status u32) bool {
	if mgr.state != .running || mgr.hw_config.gpu_gen != .g13 || mgr.g13_channels == unsafe { nil } {
		return false
	}
	graph := mgr.g13_channels
	offset := fw.g13_globals_pending_stamps_offset(mgr.hw_config.firmware_abi) or { return false }
	if graph.fw_status.phys == 0 || graph.globals.phys == 0
		|| graph.globals.size < offset + u64(fw.g13_pending_stamp_count) * sizeof(fw.G13PendingStamp) {
		return false
	}
	failure := mgr.g13_fault_error(default_status)
	if default_status == 2 {
		if failure.status == 4 {
			C.kprintf(c'agx: Fault addr=0x%llx unit=%llu vm=%llu reason=%llu %s\n',
				failure.address, u64(failure.unit), u64(failure.vm_slot), u64(failure.fault_type),
				if failure.is_read != 0 { c'read' } else { c'write' })
		} else {
			println('agx: fault event without a valid G13 fault register')
		}
	}
	mut pending := unsafe { &fw.G13PendingStamp(graph.globals.phys + higher_half + offset) }
	shift := if mgr.hw_config.firmware_abi == .v13_5_partial { u32(4) } else { u32(3) }
	for index := u32(0); index < fw.g13_pending_stamp_count; index++ {
		info := unsafe { katomic.load(&pending[index].info) }
		if info & 1 == 0 { continue }
		slot := (info >> shift) & 0x7f
		wait_value := unsafe { katomic.load(&pending[index].wait_value) }
		classified := if culprit >= 0 && u32(culprit) != slot {
			G13JobError{status: 5}
		} else { failure }
		mgr.mark_g13_slot_error_locked(slot, wait_value, classified)
		unsafe {
			katomic.store(mut &pending[index].info, u32(0))
			katomic.store(mut &pending[index].wait_value, u32(0))
		}
	}
	mut status := unsafe { &fw.G13FwStatus(graph.fw_status.cpu_address()) }
	started := timer.get_ns()
	for katomic.load(&status.halted) == 0 {
		if timer.get_ns() - started >= u64(100_000_000) { return false }
		katomic.sync()
	}
	katomic.store(mut &status.halted, u32(0))
	katomic.sync()
	katomic.store(mut &status.resume, u32(1))
	return true
}

fn (mut mgr GpuManager) recover_g13_fault(culprit i32, default_status u32) bool {
	mgr.lock.acquire()
	defer { mgr.lock.release() }
	return mgr.recover_g13_fault_locked(culprit, default_status)
}

fn (mut mgr GpuManager) recover_g13_channel(pipe_type u32, slot u32, value u32, error_type u32) bool {
	if pipe_type >= 3 || slot >= event.max_stamps { return false }
	mgr.lock.acquire()
	defer { mgr.lock.release() }
	if mgr.state != .running { return false }
	mut owner := &G13QueueResources(unsafe { nil })
	for job in mgr.g13_compute_jobs {
		if pipe_type == 2 && job.submitted && !job.released && job.event_slot == slot {
			owner = unsafe { job.queue }
			break
		}
	}
	if owner == unsafe { nil } {
		for job in mgr.g13_render_jobs {
			if job.submitted && !job.released && ((pipe_type == 0 && job.vertex_event_slot == slot)
				|| (pipe_type == 1 && job.fragment_event_slot == slot)) {
				owner = unsafe { job.queue }
				break
			}
		}
	}
	if owner == unsafe { nil } || owner.released || owner.subqueues[pipe_type].info.va == 0 { return false }
	mgr.mark_g13_slot_error_locked(slot, value, G13JobError{status: 7, extra: error_type})
	message := fw.make_recover_channel(pipe_type, owner.subqueues[pipe_type].info.va, value)
	token := mgr.channels.device_ctrl.enqueue_with_token(voidptr(&message)) or { return false }
	if !mgr.ring_device_control() { return false }
	started := timer.get_ns()
	for mgr.channels.device_ctrl.read_pointer() != token {
		if mgr.channels.device_ctrl.has_fault() || timer.get_ns() - started >= u64(1_000_000_000) { return false }
		katomic.sync()
	}
	return true
}
