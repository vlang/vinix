// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module gpu

import aarch64.cpu
import aarch64.exception
import aarch64.kio
import aarch64.timer
import apple.ascmailbox
import apple.mailbox
import apple.rtkit
import gpu.agx.hw
import klock

enum RuntimeWaitCase {
	timely
	stale
	shutdown
	deadline
	late
	masked
}

__global runtime_case = RuntimeWaitCase.timely
__global runtime_waits = 0
__global batch_power_ack = u64(0)

fn simulate_runtime_lock_contention() {
	timer.busywait_us(if runtime_case == .late { u64(500_000) } else { u64(499_900) })
}

fn observe_runtime_wait() {
	runtime_waits++
	if runtime_case == .masked {
		assert rtkit_owner.lock.is_held() && !cpu.interrupt_state()
		assert kio.aic_irq_masked(575)
		return
	}
	assert !rtkit_owner.lock.is_held() && cpu.interrupt_state()
	if runtime_case == .shutdown {
		assert rtkit_owner.rtkit_buffers.len == 1 && !kio.aic_irq_masked(575)
		rtkit_owner.shutdown()
		assert rtkit_owner.rtkit_buffers.len == 0 && kio.aic_irq_masked(575)
	} else if runtime_case in [.deadline, .late] {
		klock.on_next_acquire(unsafe { &rtkit_owner.lock }, simulate_runtime_lock_contention)
	} else if runtime_waits == 1 || (runtime_case == .stale && runtime_waits == 3) {
		assert !kio.aic_irq_masked(575)
		kio.queue_aic_event(575)
		exception.dispatch()
		assert kio.aic_irq_masked(575)
	}
	if runtime_case != .stale || runtime_waits == 3 {
		timer.watch_busywait(unsafe { nil })
	}
}

fn check_g13_runtime_transmit() {
	base := u64(0x206408000)
	mut tx := ascmailbox.new_mailbox(base)
	mailbox.set_wait_transport(unsafe { &tx })
	for abi in [hw.FirmwareAbi.v12_3, .v13_5_partial]! {
		for sample in [RuntimeWaitCase.timely, .stale, .shutdown, .deadline, .late, .masked]! {
			mut transport := rtkit.RTKit{name: 'g13-runtime-tx', state: .running}
			mut mgr := GpuManager{hw_config: hw.HwConfig{gpu_gen: .g13, firmware_abi: abi},
				rtkit_receive_irq: 578, rtkit_send_irq: 575, rtk: unsafe { &transport }}
			rtkit_owner = unsafe { &mgr }
			message := if sample == .shutdown {
				transport.set_shmem_allocator(unsafe { voidptr(&mgr) }, allocate_rtkit_shmem)
				mailbox.MboxMsg{data0: (u64(1) << 52) | (u64(1) << 44), data1: rtkit.ep_crashlog}
			} else {
				mailbox.MboxMsg{data0: u64(8) << 52, data1: rtkit.ep_ioreport}
			}
			transport.mbox.inject(message)
			if sample == .shutdown {
				transport.mbox.inject(mailbox.MboxMsg{data0: 0x0070000000000220})
			}
			cpu.set_interrupt_state(sample != .masked)
			timer.watch_busywait(observe_runtime_wait)
			runtime_case = sample
			runtime_waits = 0
			kio.require_send_owner(unsafe { &mgr.lock })
			kio.configure_send(base, unsafe { &tx.lock }, if sample == .stale { u64(25) } else { u64(1) })
			started := timer.get_us()
			unmasks := kio.aic_unmasks()
			assert mgr.checked_poll_rtkit_messages() == (sample != .late)
			assert !mgr.lock.is_held() && !tx.lock.is_held() && kio.aic_irq_masked(575)
			assert cpu.interrupt_state() == (sample != .masked)
			cpu.set_interrupt_state(true)
			timer.watch_busywait(unsafe { nil })
			reads, writes, words := kio.send_result()
			if sample in [.shutdown, .late] {
				assert reads == 1 && writes == 0 && kio.aic_unmasks() == unmasks + 1
				if sample == .shutdown {
					assert mgr.state == .stopped && mgr.trace[0..3] == ['halt', 'stop', 'rtkit']
					assert transport.mbox.recv() != none && transport.iop_power_state == 0
				} else {
					assert timer.get_us() - started == 500_100 && mgr.state == .running
				}
			} else {
				assert writes == 2 && words == [message.data0, message.data1]!
				assert mgr.state == .running
				if sample == .stale {
					assert reads == 3 && kio.aic_unmasks() == unmasks + 2
					assert timer.get_us() - started == 30
				} else if sample == .masked {
					assert reads == 2 && kio.aic_unmasks() == unmasks
					assert timer.get_us() - started == 100
				} else {
					assert reads == 2 && kio.aic_unmasks() == unmasks + 1
					assert timer.get_us() - started == (if sample == .deadline { u64(500_000) } else { u64(10) })
				}
			}
		}
	}
	mailbox.set_wait_transport(unsafe { nil })
	rtkit_owner = unsafe { nil }
	kio.require_send_owner(unsafe { nil })
	kio.configure_send(0, unsafe { nil }, 0)
	println('G13 runtime transmit: early IRQ, stale IRQ, masked caller, shutdown and contended deadline passed on both ABIs')
}

fn stop_during_batch_doorbell() {
	timer.watch_busywait(unsafe { nil })
	assert !rtkit_owner.lock.is_held() && !kio.aic_irq_masked(575)
	rtkit_owner.shutdown()
	assert kio.aic_irq_masked(575)
}

fn boot_g13_fixture_transport(mut transport rtkit.RTKit) {
	transport.mbox.inject(mailbox.MboxMsg{data0: 0x00100000000c000b})
	transport.mbox.inject(mailbox.MboxMsg{data0: 0x0088000100000003})
	transport.mbox.inject(mailbox.MboxMsg{data0: 0x0070000000000020})
	transport.mbox.inject(mailbox.MboxMsg{data0: rtkit_ap_on})
	assert transport.boot_started(0, 0)
}

fn restore_power_after_start_attempt() {
	assert rtkit_owner.rtk.handle_system_message(mailbox.MboxMsg{data0: rtkit_ap_on})
}

fn drop_power_during_endpoint_start() {
	timer.watch_busywait(unsafe { nil })
	assert rtkit_owner.rtk.handle_system_message(mailbox.MboxMsg{data0: u64(rtkit.msg_ap_power_ack) << 52})
	// Power can return after the FIFO attempt reports cancellation. Only a
	// caller's fresh START_EP should publish a message in that case.
	fifo_lock := unsafe { &rtkit_owner.rtk.mbox.unguarded_transport.lock }
	klock.on_next_release(fifo_lock, restore_power_after_start_attempt)
}

fn check_g13_endpoint_start_power(abi hw.FirmwareAbi, mut tx ascmailbox.Mailbox) {
	kio.require_send_owner(unsafe { nil })
	for irq in [u32(0), 575]! {
		mut transport := rtkit.RTKit{name: 'g13-start-power'}
		boot_g13_fixture_transport(mut transport)
		transport.mbox.unguarded_transport = unsafe { &tx }
		mut mgr := GpuManager{hw_config: hw.HwConfig{gpu_gen: .g13, firmware_abi: abi}, rtk: unsafe { &transport }}
		rtkit_owner = unsafe { &mgr }
		kio.configure_send(tx.base, unsafe { &tx.lock }, 1)
		unmasks := kio.aic_unmasks()
		timer.watch_busywait(drop_power_during_endpoint_start)
		assert !transport.start_endpoint_irq(0x21, irq), 'START_EP must stop if its application target loses power while waiting'
		reads, writes, _ := kio.send_result()
		assert transport.ap_power_state == 0x20 && reads == 1 && writes == 0 && !tx.lock.is_held()
		assert kio.aic_irq_masked(575) && kio.aic_unmasks() == unmasks + if irq == 0 { 0 } else { 1 }
		assert transport.start_endpoint_irq(0x21, irq)
		retry_reads, retry_writes, words := kio.send_result()
		assert retry_reads == 2 && retry_writes == 2 && words == [rtkit_start_app, u64(rtkit.ep_mgmt)]!
		rtkit_owner = unsafe { nil }
	}
}

fn drop_power_during_batch_doorbell() {
	timer.watch_busywait(unsafe { nil })
	assert !rtkit_owner.lock.is_held() && !kio.aic_irq_masked(575)
	assert rtkit_owner.handle_role_system_message(0, mailbox.MboxMsg{data0: batch_power_ack})
}

fn check_g13_batch_power_wait(mut mgr GpuManager, mut tx ascmailbox.Mailbox) {
	for kind in [rtkit.msg_iop_power_ack, rtkit.msg_ap_power_ack]! {
		batch_power_ack = u64(kind) << 52
		kio.configure_send(tx.base, unsafe { &tx.lock }, 1)
		timer.watch_busywait(drop_power_during_batch_doorbell)
		mgr.lock.acquire()
		assert !mgr.ring_g13_batch_pipe_locked(3, 2), 'batch doorbell must stop when RTKit loses application readiness during the FIFO wait'
		assert mgr.lock.is_held() && mgr.state == .running && kio.aic_irq_masked(575)
		mgr.lock.release()
		reads, writes, _ := kio.send_result()
		assert reads == 1 && writes == 0 && !tx.lock.is_held()

		// System replies remain available while an application power gate is off.
		kio.configure_send(tx.base, unsafe { &tx.lock }, 1)
		runtime_waits = 0
		timer.watch_busywait(observe_runtime_wait)
		report := mailbox.MboxMsg{data0: u64(8) << 52, data1: rtkit.ep_ioreport}
		assert mgr.handle_role_system_message(0, report)
		system_reads, system_writes, system_words := kio.send_result()
		assert system_reads == 2 && system_writes == 2 && system_words == [report.data0, report.data1]!

		assert mgr.handle_role_system_message(0, mailbox.MboxMsg{data0: batch_power_ack | 0x20})
		kio.configure_send(tx.base, unsafe { &tx.lock }, 0)
		mgr.lock.acquire()
		assert mgr.ring_g13_batch_pipe_locked(3, 2)
		mgr.lock.release()
		retry_reads, retry_writes, retry_words := kio.send_result()
		assert retry_reads == 1 && retry_writes == 2 && retry_words == [u64(0x008300000000000e), 0x21]!
	}
}

fn crash_during_polled_send() {
	timer.watch_busywait(unsafe { nil })
	assert rtkit_owner.lock.is_held() && kio.aic_irq_masked(575)
	assert !rtkit_owner.handle_role_system_message(0, mailbox.MboxMsg{data0: u64(1) << 52,
		data1: rtkit.ep_crashlog})
}

fn crash_on_fifo_retry() {
	timer.watch_busywait(unsafe { nil })
	fifo_lock := unsafe { &rtkit_owner.rtk.mbox.unguarded_transport.lock }
	klock.on_next_acquire(fifo_lock, crash_during_polled_send)
}

enum PolledCrashPoint {
	first_lock
	poll_wait
	retry_lock
}

fn check_g13_polled_crash_wait(abi hw.FirmwareAbi, point PolledCrashPoint, message mailbox.MboxMsg, mut tx ascmailbox.Mailbox) {
	for irq in [u32(0), 575]! {
		mut transport := rtkit.RTKit{name: 'g13-polled-crash'}
		boot_g13_fixture_transport(mut transport)
		transport.mbox.unguarded_transport = unsafe { &tx }
		// The receive worker handles a crash on an allocated endpoint outside mgr.lock.
		transport.system_iovas[rtkit.ep_crashlog] = 1
		mut mgr := GpuManager{hw_config: hw.HwConfig{gpu_gen: .g13, firmware_abi: abi},
			rtkit_send_irq: irq, rtk: unsafe { &transport }}
		rtkit_owner = unsafe { &mgr }
		kio.require_send_owner(unsafe { &mgr.lock })
		cpu.set_interrupt_state(irq == 0)
		mgr.lock.acquire()
		wait := mgr.g13_rtkit_send_wait_locked()
		ep := mailbox.msg_endpoint(&message)
		kio.configure_send(tx.base, unsafe { &tx.lock }, 0)
		assert transport.send_message_wait(ep, message.data0, wait)
		reads, writes, words := kio.send_result()
		assert reads == 1 && writes == 2 && words == [message.data0, message.data1]!
		kio.configure_send(tx.base, unsafe { &tx.lock }, if point == .first_lock { u64(0) } else { u64(1) })
		match point {
			.first_lock { klock.on_next_acquire(unsafe { &tx.lock }, crash_during_polled_send) }
			.poll_wait { timer.watch_busywait(crash_during_polled_send) }
			.retry_lock { timer.watch_busywait(crash_on_fifo_retry) }
		}
		assert !transport.send_message_wait(ep, message.data0, wait), 'polled RTKit send on endpoint ${ep} must stop after a crash at ${point}'
		assert transport.state == .error && mgr.state == .running && mgr.lock.is_held()
		crash_reads, crash_writes, _ := kio.send_result()
		expected_reads := if point == .first_lock { u64(0) } else { u64(1) }
		assert crash_reads == expected_reads && crash_writes == 0 && !tx.lock.is_held()
		assert !transport.send_message_wait(ep, message.data0, wait)
		final_reads, final_writes, _ := kio.send_result()
		assert final_reads == expected_reads && final_writes == 0
		mgr.lock.release()
		assert cpu.interrupt_state() == (irq == 0)
		cpu.set_interrupt_state(true)
		rtkit_owner = unsafe { nil }
		kio.require_send_owner(unsafe { nil })
	}
}

fn check_g13_batch_pipe_transmit() {
	base := u64(0x206408000)
	mut tx := ascmailbox.new_mailbox(base)
	mailbox.set_wait_transport(unsafe { &tx })
	for abi in [hw.FirmwareAbi.v12_3, .v13_5_partial]! {
		check_g13_endpoint_start_power(abi, mut tx)
		for point in [PolledCrashPoint.first_lock, .poll_wait, .retry_lock]! {
			for message in [mailbox.MboxMsg{data0: u64(8) << 52, data1: rtkit.ep_ioreport},
				mailbox.MboxMsg{data0: 0x008300000000000e, data1: 0x21}]! {
				check_g13_polled_crash_wait(abi, point, message, mut tx)
			}
		}
		mut transport := rtkit.RTKit{name: 'g13-batch-doorbell'}
		boot_g13_fixture_transport(mut transport)
		mut mgr := GpuManager{hw_config: hw.HwConfig{gpu_gen: .g13, firmware_abi: abi},
			rtkit_send_irq: 575, rtk: unsafe { &transport }}
		rtkit_owner = unsafe { &mgr }
		kio.require_send_owner(unsafe { &mgr.lock })
		kio.configure_send(base, unsafe { &tx.lock }, 1)
		runtime_case = .timely
		runtime_waits = 0
		timer.watch_busywait(observe_runtime_wait)
		mgr.lock.acquire()
		assert mgr.ring_g13_batch_pipe_locked(3, 2)
		assert mgr.lock.is_held() && runtime_waits == 1 && kio.aic_irq_masked(575)
		mgr.lock.release()
		reads, writes, words := kio.send_result()
		assert reads == 2 && writes == 2 && words == [u64(0x008300000000000e), 0x21]!
		// An application doorbell still needs both RTKit power states.
		assert mgr.handle_role_system_message(0, mailbox.MboxMsg{data0: 0x0070000000000000})
		kio.configure_send(base, unsafe { &tx.lock }, 0)
		mgr.lock.acquire()
		assert !mgr.ring_g13_batch_pipe_locked(3, 2)
		mgr.lock.release()
		rejected_reads, rejected_writes, _ := kio.send_result()
		assert rejected_reads == 0 && rejected_writes == 0
		assert mgr.handle_role_system_message(0, mailbox.MboxMsg{data0: 0x0070000000000020})
		check_g13_batch_power_wait(mut mgr, mut tx)
		kio.configure_send(base, unsafe { &tx.lock }, 1)
		timer.watch_busywait(stop_during_batch_doorbell)
		mgr.lock.acquire()
		assert !mgr.ring_g13_batch_pipe_locked(3, 2)
		assert mgr.lock.is_held() && mgr.state == .stopped && kio.aic_irq_masked(575)
		stopped_reads, stopped_writes, _ := kio.send_result()
		assert stopped_reads == 1 && stopped_writes == 0
		assert !mgr.ring_g13_batch_pipe_locked(3, 0)
		mgr.lock.release()
		final_reads, final_writes, _ := kio.send_result()
		assert final_reads == stopped_reads && final_writes == 0
	}
	mailbox.set_wait_transport(unsafe { nil })
	rtkit_owner = unsafe { nil }
	kio.require_send_owner(unsafe { nil })
	kio.configure_send(0, unsafe { nil }, 0)
	println('G13 START_EP: IRQ and polling cancellation leave a fresh start usable on both ABIs')
	println('G13 batch pipe transmit: both ABIs cover live encoding, shutdown, polled crashes and in-flight power transitions with system replies')
}
