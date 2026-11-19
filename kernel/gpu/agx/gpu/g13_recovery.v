// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import gpu.agx.fw
import gpu.agx.event
import katomic
import gpu.agx.channel
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
		if timer.get_ns() - started >= u64(100_000_000) {
			// Asahi's recover() logs "Cannot recover" and keeps the device: the
			// pending work is already marked failed, there is nothing to resume,
			// and a later unexplained halt still fails the firmware health check.
			C.kprintf(c'agx: GPU firmware did not halt (count=%llu); cannot recover\n',
				katomic.load[u64](&status.halt_count))
			return true
		}
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

// One entry per device-control slot that can hold an unconsumed command:
// fw.device_control_size - 1, because one ring entry always stays empty.
const g13_recovery_capacity = 255

// A published RecoverChannel and the queue it pins until the firmware
// consumes it or stops.
struct G13PendingRecovery {
	ticket channel.TxTicket
	owner  &G13QueueResources = unsafe { nil }
}

// Caller holds mgr.lock. Remove the entry before dropping its reference,
// which can let the file reaper free the queue record.
fn (mut mgr GpuManager) release_g13_recovery_locked(index u32) {
	if index >= mgr.g13_recovery_count { return }
	mut owner := unsafe { mgr.g13_recoveries[index].owner }
	mgr.g13_recovery_count--
	mgr.g13_recoveries[index] = mgr.g13_recoveries[mgr.g13_recovery_count]
	mgr.g13_recoveries[mgr.g13_recovery_count] = G13PendingRecovery{}
	owner.release_file_reference()
}

// Caller holds mgr.lock. Unpin each queue whose RecoverChannel the firmware has
// consumed. A corrupt ring keeps every pin: ticket_consumed latches the channel
// fault, and the health check stops the device before teardown releases them.
fn (mut mgr GpuManager) release_consumed_g13_recoveries_locked() {
	mut index := u32(0)
	for index < mgr.g13_recovery_count {
		consumed := mgr.channels.device_ctrl.ticket_consumed(mgr.g13_recoveries[index].ticket) or { return }
		if consumed {
			mgr.release_g13_recovery_locked(index)
		} else {
			index++
		}
	}
}

// Caller holds mgr.lock and has stopped the firmware, so no published
// RecoverChannel can still read its workqueue.
fn (mut mgr GpuManager) release_g13_recoveries_locked() {
	for mgr.g13_recovery_count > 0 {
		mgr.release_g13_recovery_locked(mgr.g13_recovery_count - 1)
	}
}

// As in Asahi's handle_channel_error, the slot's work is marked failed before
// its queue is looked up, and a missing queue is not fatal: the error can name
// work that has already retired. A command the firmware has not consumed after
// a second is logged and the device keeps running, as in Asahi. Its queue stays
// pinned until the firmware consumes the command or stops, because the command
// can still dereference the workqueue. A corrupt ring stops the device.
fn (mut mgr GpuManager) recover_g13_channel(pipe_type u32, slot u32, value u32, error_type u32) bool {
	mgr.lock.acquire()
	defer { mgr.lock.release() }
	if mgr.state != .running { return false }
	if slot < event.max_stamps {
		mgr.mark_g13_slot_error_locked(slot, value, G13JobError{status: 7, extra: error_type})
	}
	if pipe_type >= 3 || slot >= event.max_stamps {
		C.kprintf(c'agx: channel error names pipe %llu slot %llu; nothing to recover\n',
			u64(pipe_type), u64(slot))
		return true
	}
	mut owner := unsafe { &G13QueueResources(nil) }
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
	if owner == unsafe { nil } || owner.released || owner.subqueues[pipe_type].info.va == 0 {
		C.kprintf(c'agx: no workqueue for channel error slot %llu\n', u64(slot))
		return true
	}
	// Every pinned command still occupies a device-control entry, so once the
	// consumed ones are released, a command the ring accepts has a table entry.
	mgr.release_consumed_g13_recoveries_locked()
	if mgr.g13_recovery_count >= g13_recovery_capacity { return false }
	// Stage the command in manager storage. The ticket that names a stack local
	// would reach the table, and V would move that local to the heap for good.
	mgr.g13_recover_message = fw.make_recover_channel(mgr.hw_config.firmware_abi, pipe_type,
		owner.subqueues[pipe_type].info.va, value) or { return false }
	ticket := mgr.channels.device_ctrl.enqueue_tracked(voidptr(&mgr.g13_recover_message)) or { return false }
	// The published command can still dereference the workqueue. Keep its
	// backing until consumption or stopped-firmware teardown, even on timeout.
	owner.retain_file_reference()
	mgr.g13_recoveries[mgr.g13_recovery_count] = G13PendingRecovery{ticket: ticket, owner: owner}
	mgr.g13_recovery_count++
	sent := mgr.ring_g13_doorbell_locked(doorbell_device_control)
	if mgr.state != .running { return false }
	// An overlapping doorbell may have notified this command too. Check
	// consumption even if this sender reached its own FIFO deadline.
	if !sent { println('agx: RecoverChannel doorbell send failed') }
	started := timer.get_ns()
	for mgr.state == .running {
		consumed := mgr.channels.device_ctrl.ticket_consumed(ticket) or {
			// The latched ring fault keeps the pin until stopped-firmware teardown.
			mgr.state = .error
			return false
		}
		if consumed {
			// Only the event worker publishes and releases recoveries, and a
			// shutdown during the doorbell wait returned above, so the entry is
			// still in the table.
			for index := u32(0); index < mgr.g13_recovery_count; index++ {
				if mgr.g13_recoveries[index].ticket == ticket {
					mgr.release_g13_recovery_locked(index)
					break
				}
			}
			return true
		}
		if timer.get_ns() - started >= u64(1_000_000_000) {
			println('agx: timed out waiting for RecoverChannel; its queue stays pinned')
			return true
		}
		katomic.sync()
	}
	return false
}
