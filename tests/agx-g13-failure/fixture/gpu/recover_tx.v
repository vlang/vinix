// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module gpu

import aarch64.kio
import aarch64.timer
import apple.ascmailbox
import apple.mailbox
import apple.rtkit
import gpu.agx.channel
import gpu.agx.event
import gpu.agx.fw
import gpu.agx.hw
import katomic

enum RecoverySendCase {
	delayed
	later_unread
	wrapped
	polled
	stopped
	late_consumed
	completion_timeout
	send_timeout
	ring_fault
	bad_write
	wrapped_bad_write
	full
}

__global recovery_send_case = RecoverySendCase.delayed
__global recovery_header = unsafe { &channel.RingHeader(nil) }
__global recovery_owner = unsafe { &G13QueueResources(nil) }

fn consume_recovery_ticket() {
	assert rtkit_owner.lock.is_held() && recovery_owner.has_file_references()
	recovery_header.read_ptr = recovery_header.write_ptr
}

fn observe_recovery_irq_wait() {
	assert !rtkit_owner.lock.is_held() && recovery_owner.has_file_references()
	assert !rtkit_owner.channels.device_ctrl.lock.is_held()
	assert recovery_header.write_ptr == 0 && recovery_header.read_ptr == 3
	if recovery_send_case == .stopped {
		stop_during_batch_doorbell()
		assert !recovery_owner.has_file_references()
		// Any access to the old channel header after teardown is invalid.
		rtkit_owner.channels.device_ctrl.state_phys = 1
		return
	}
	if recovery_send_case in [.later_unread, .wrapped, .wrapped_bad_write, .late_consumed]! {
		wraps := recovery_send_case in [.wrapped, .wrapped_bad_write]!
		if wraps {
			// Isolate the recovery pin from the job's own teardown guard.
			mut job := unsafe { rtkit_owner.g13_compute_jobs[0] }
			job.released = true
			assert !rtkit_owner.checked_release_g13_queue_resources(recovery_owner)
		}
		rtkit_owner.lock.acquire()
		recovery_header.read_ptr = recovery_header.write_ptr
		if recovery_send_case != .late_consumed {
			// Leave a later command unread, possibly at the original index.
			message := fw.FwRecoverChannel{}
			later := if wraps { 4 } else { 1 }
			for index in 0 .. later {
				assert rtkit_owner.channels.device_ctrl.enqueue(voidptr(&message))
				if index + 1 < later { recovery_header.read_ptr = recovery_header.write_ptr }
			}
		}
		rtkit_owner.lock.release()
	}
	if recovery_send_case in [.bad_write, .wrapped_bad_write]! {
		// A corrupt, in-range write index falsely reports an empty ring.
		recovery_header.write_ptr = recovery_header.read_ptr
	}
	if recovery_send_case == .late_consumed {
		timer.watch_busywait(unsafe { nil })
		timer.busywait_us(500_000)
		return
	}
	if recovery_send_case == .ring_fault { recovery_header.read_ptr = 4 }
	if recovery_send_case == .delayed { katomic.on_next_sync(consume_recovery_ticket) }
	if recovery_send_case == .send_timeout {
		timer.watch_busywait(unsafe { nil })
		return
	}
	observe_runtime_wait()
}

fn check_g13_recovery_transmit() {
	base := u64(0x206408000)
	mut tx := ascmailbox.new_mailbox(base)
	mailbox.set_wait_transport(unsafe { &tx })
	event.set_completed(8, false)
	for abi in [hw.FirmwareAbi.v12_3, .v13_5_partial]! {
		for sample in [RecoverySendCase.delayed, .later_unread, .wrapped, .polled, .stopped, .late_consumed,
			.completion_timeout, .send_timeout, .ring_fault, .bad_write, .wrapped_bad_write, .full]! {
			mut transport := rtkit.RTKit{name: 'g13-recover-channel'}
			boot_g13_fixture_transport(mut transport)
			mut header := channel.RingHeader{write_ptr: 3,
				read_ptr: if sample == .full { u32(0) } else { u32(3) }}
			mut ring := [4]fw.FwRecoverChannel{}
			mut job_queue := G13QueueResources{}
			job_queue.subqueues[2].info.va = 0x123000
			mut job := G13ComputeJobResources{queue: unsafe { &job_queue }, event_slot: 8, stamp_value: 0x100, submitted: true}
			mut mgr := GpuManager{hw_config: hw.HwConfig{gpu_gen: .g13, firmware_abi: abi},
				rtkit_send_irq: if sample == .polled { u32(0) } else { u32(575) },
				rtk: unsafe { &transport }, g13_compute_jobs: [unsafe { &job }]}
			mgr.channels.device_ctrl = channel.new_tx_channel('recovery', 1, u64(unsafe { &header }),
				1, u64(unsafe { &ring }), 4, u32(sizeof(fw.FwRecoverChannel)))
			rtkit_owner = unsafe { &mgr }
			recovery_owner = unsafe { &job_queue }
			recovery_header = unsafe { &header }
			recovery_send_case = sample
			runtime_case = .timely
			runtime_waits = 0
			kio.require_send_owner(unsafe { &mgr.lock })
			kio.configure_send(base, unsafe { &tx.lock }, if sample == .send_timeout { u64(500_001) } else { u64(1) })
			if sample == .polled {
				mailbox.watch_send(consume_recovery_ticket)
			} else {
				timer.watch_busywait(observe_recovery_irq_wait)
			}
			consumed := sample in [.delayed, .later_unread, .wrapped, .polled, .late_consumed]!
			// As in Asahi, a command not consumed within a second is logged, not fatal.
			timed_out := sample in [.completion_timeout, .send_timeout]!
			complete := consumed || timed_out
			// An invalid pipe marks the slot but publishes nothing (Asahi logs it).
			write_before := header.write_ptr
			assert mgr.recover_g13_channel(3, 8, 0x100, 1) && mgr.state == .running
			assert header.write_ptr == write_before && mgr.g13_recovery_count == 0
			assert job.error.status == 7 && job.error.extra == 1
			result := mgr.recover_g13_channel(2, 8, 0x100, 1)
			if sample in [.bad_write, .wrapped_bad_write]! {
				assert !result && job_queue.has_file_references() && mgr.channels.device_ctrl.has_fault(),
					'corrupt device-control write index must retain the recovery queue until shutdown'
			}
			assert result == complete
			timer.watch_busywait(unsafe { nil })
			mailbox.watch_send(unsafe { nil })
			reads, writes, words := kio.send_result()
			assert !mgr.lock.is_held() && !tx.lock.is_held() && kio.aic_irq_masked(575)
			assert job.error.status == 7 && job.error.extra == 1
			if sample in [.polled, .full]! {
				assert reads == 0 && writes == 0
			} else if sample in [.stopped, .send_timeout, .late_consumed]! {
				assert reads > 0 && writes == 0
			} else {
				assert reads == 2 && writes == 2 && words == [u64(0x0083000000000011), 0x21]!
			}
			if sample == .full {
				assert header.write_ptr == 3 && ring[3] == fw.FwRecoverChannel{}
				assert mgr.state == .running && !job_queue.has_file_references()
			} else if sample in [.wrapped, .wrapped_bad_write]! {
				assert header.write_ptr == if sample == .wrapped { u32(0) } else { u32(3) }
				assert header.read_ptr == 3 && ring[3] == fw.FwRecoverChannel{}
			} else {
				assert header.write_ptr == match sample {
					.later_unread { u32(1) }
					.bad_write { u32(3) }
					else { u32(0) }
				}
				assert ring[3] == fw.FwRecoverChannel{tag: if abi == .v12_3 { u32(0x0e) } else { u32(0x0f) },
					pipe_type: 2, work_queue: 0x123000, event_value: 0x100}
			}
			if consumed {
				assert mgr.state == .running && !job_queue.has_file_references()
				assert mgr.g13_recovery_count == 0
			} else if timed_out {
				check_pending_recoveries(mut mgr, mut header, mut job_queue, base, mut tx)
			} else if sample == .stopped {
				assert mgr.state == .stopped && !job_queue.has_file_references()
				assert !mgr.recover_g13_channel(2, 8, 0x100, 1)
			} else if sample != .full {
				assert mgr.state == .error && job_queue.has_file_references()
				job.released = true
				assert !mgr.checked_release_g13_queue_resources(&job_queue)
				mgr.shutdown()
				assert mgr.state == .stopped && !job_queue.has_file_references()
				assert mgr.g13_recovery_count == 0
			}
		}
	}
	// A channel error whose work already retired names no live queue. Asahi
	// logs it and carries on; Vinix does too, without publishing a command.
	for abi in [hw.FirmwareAbi.v12_3, .v13_5_partial]! {
		mut header := channel.RingHeader{write_ptr: 3, read_ptr: 3}
		mut ring := [4]fw.FwRecoverChannel{}
		mut job_queue := G13QueueResources{}
		job_queue.subqueues[2].info.va = 0x123000
		mut retired := G13ComputeJobResources{queue: unsafe { &job_queue }, event_slot: 8, stamp_value: 0x100,
			submitted: true, released: true}
		mut mgr := GpuManager{hw_config: hw.HwConfig{gpu_gen: .g13, firmware_abi: abi},
			g13_compute_jobs: [unsafe { &retired }]}
		mgr.channels.device_ctrl = channel.new_tx_channel('recovery', 1, u64(unsafe { &header }),
			1, u64(unsafe { &ring }), 4, u32(sizeof(fw.FwRecoverChannel)))
		assert mgr.recover_g13_channel(2, 8, 0x100, 1)
		assert mgr.state == .running && header.write_ptr == 3 && mgr.g13_recovery_count == 0
		assert mgr.recover_g13_channel(1, event.max_stamps, 0x100, 1)
		assert mgr.state == .running && header.write_ptr == 3 && !job_queue.has_file_references()
		mgr.state = .stopped
		assert !mgr.recover_g13_channel(2, 8, 0x100, 1)
	}
	assert sizeof(fw.FwRecoverChannel) == 0x30 && __offsetof(fw.FwRecoverChannel, work_queue) == 8
	mailbox.set_wait_transport(unsafe { nil })
	rtkit_owner = unsafe { nil }
	recovery_owner = unsafe { nil }
	recovery_header = unsafe { nil }
	kio.require_send_owner(unsafe { nil })
	kio.configure_send(0, unsafe { nil }, 0)
	println('G13 RecoverChannel: 24 cases cover both ABIs, later publications, write-index faults, pinned timeouts, overlapping recoveries and shutdown')
}

// A RecoverChannel the firmware has not consumed keeps its queue pinned while
// the device runs. Another channel error can publish a second command, and the
// worker unpins each queue as the firmware consumes its command.
fn check_pending_recoveries(mut mgr GpuManager, mut header channel.RingHeader, mut job_queue G13QueueResources,
	base u64, mut tx ascmailbox.Mailbox) {
	assert mgr.state == .running && mgr.g13_recovery_count == 1 && job_queue.has_file_references()
	assert header.write_ptr == 0 && header.read_ptr == 3
	// The worker leaves an unconsumed command pinned.
	mgr.lock.acquire()
	mgr.release_consumed_g13_recoveries_locked()
	mgr.lock.release()
	assert mgr.g13_recovery_count == 1 && job_queue.has_file_references()
	kio.configure_send(base, unsafe { &tx.lock }, u64(500_001))
	assert mgr.recover_g13_channel(2, 8, 0x100, 1)
	assert mgr.state == .running && header.write_ptr == 1 && mgr.g13_recovery_count == 2
	assert katomic.load(&job_queue.file_references) == 2
	// The firmware consumes the first command only.
	header.read_ptr = 0
	mgr.lock.acquire()
	mgr.release_consumed_g13_recoveries_locked()
	mgr.lock.release()
	assert mgr.g13_recovery_count == 1 && katomic.load(&job_queue.file_references) == 1
	// A new channel error releases consumed pins before publishing.
	header.read_ptr = 1
	assert mgr.recover_g13_channel(2, 8, 0x100, 1)
	assert mgr.state == .running && header.write_ptr == 2 && mgr.g13_recovery_count == 1
	assert katomic.load(&job_queue.file_references) == 1
	header.read_ptr = 2
	mgr.lock.acquire()
	mgr.release_consumed_g13_recoveries_locked()
	mgr.lock.release()
	assert mgr.g13_recovery_count == 0 && !job_queue.has_file_references()
}
