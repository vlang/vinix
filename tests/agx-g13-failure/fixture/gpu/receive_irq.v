// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module gpu

import aarch64.aic
import aarch64.exception
import aarch64.kio
import aarch64.timer
import apple.mailbox
import apple.rtkit
import gpu.agx.hw

__global irq_boot_probe = unsafe { &GpuManager(nil) }
__global irq_boot_waits = 0

fn check_receive_irq_binding() {
	names := 'send-empty\x00recv-not-empty\x00'
	mut cells := [u8(0), 0, 0, 0, 0, 0, 2, 63, 0, 0, 0, 4,
		0, 0, 0, 0, 0, 0, 2, 66, 0, 0, 0, 4]!
	address := unsafe { &cells[0] }
	size := u32(cells.len)
	assert (mailbox.decode_aic_receive_irq(names.str, u32(names.len), address, size) or { u32(0) }) == 578
	assert mailbox.decode_aic_receive_irq(names.str, u32(names.len - 1), address, size) == none
	assert mailbox.decode_aic_receive_irq(names.str, u32(names.len), address, size - 1) == none
	assert mailbox.decode_aic_receive_irq(names.str, u32(names.len), address, 12) == none
	duplicate := 'recv-not-empty\x00recv-not-empty\x00'
	assert mailbox.decode_aic_receive_irq(duplicate.str, u32(duplicate.len), address, size) == none
	cells[15] = 1
	assert mailbox.decode_aic_receive_irq(names.str, u32(names.len), address, size) == none
	cells[15] = 0
	cells[23] = 1
	assert mailbox.decode_aic_receive_irq(names.str, u32(names.len), address, size) == none
}

fn observe_irq_boot_wait() {
	assert !irq_boot_probe.lock.is_held() && !irq_boot_probe.rtk.lock.is_held()
	irq := irq_boot_probe.rtkit_receive_irq
	assert !kio.aic_irq_masked(irq) && !aic.deferred_irq_pending(irq)
	irq_boot_waits++
	// HELLO, EPMAP and AP ACK receive a notification. IOP ACK uses the
	// ten short waits of one polling fallback interval.
	if irq_boot_waits in [1, 2, 13]! {
		kio.queue_aic_event(irq)
		exception.dispatch()
		assert aic.deferred_irq_pending(irq) && kio.aic_irq_masked(irq)
	}
}

fn check_irq_boot(mut mgr GpuManager, irq u32, abi hw.FirmwareAbi) {
	mgr.hw_config.firmware_abi = abi
	mgr.state = .starting
	mgr.rtk.mbox.inject_after(mailbox.MboxMsg{data0: 0x00100000000c000b}, 1)
	mgr.rtk.mbox.inject_after(mailbox.MboxMsg{data0: 0x0088000100000003}, 1)
	mgr.rtk.mbox.inject_after(mailbox.MboxMsg{data0: 0x0070000000000220}, 1)
	mgr.rtk.mbox.inject_after(mailbox.MboxMsg{data0: rtkit_ap_on}, 1)
	assert mgr.lock.is_held()
	irq_boot_probe = unsafe { &mgr }
	irq_boot_waits = 0
	timer.watch_busywait(observe_irq_boot_wait)
	assert mgr.boot_firmware_role(0)
	timer.watch_busywait(unsafe { nil })
	irq_boot_probe = unsafe { nil }
	assert mgr.lock.is_held() && !mgr.rtk.lock.is_held()
	assert mgr.rtk.state == .running && mgr.rtk.iop_power_state == 0x0220
	assert irq_boot_waits == 13
	assert mgr.rtk.mbox.sent == 3 && mgr.rtk.mbox.sent_at(2).data0 == rtkit_ap_on
	assert aic.deferred_irq_pending(irq) && kio.aic_irq_masked(irq)
}

fn check_silent_irq_boot(irq u32) {
	// Reuse the simulated built-in route for a separate failed probe.
	aic.rearm_deferred_irq(irq)
	assert !kio.aic_irq_masked(irq)
	mut transport := rtkit.RTKit{name: 'g13-silent-irq'}
	mut failed := GpuManager{state: .starting, hw_config: hw.HwConfig{gpu_gen: .g13},
		rtkit_receive_irq: irq, rtk: unsafe { &transport }}
	failed.lock.acquire()
	started := timer.get_ns()
	assert !failed.boot_firmware_role(0) && failed.lock.is_held()
	elapsed := timer.get_ns() - started
	assert elapsed >= 1_000_000_000 && elapsed < 1_020_000_000
	assert !failed.fail_g13_initialization()
	failed.lock.release()
	assert transport.state == .error && failed.state == .error && kio.aic_irq_masked(irq)
	assert failed.trace == ['stop', 'rtkit', 'channels', 'events']
}

fn check_g13_receive_irq() {
	check_receive_irq_binding()
	irq := u32(578)
	assert !aic.claim_deferred_irq(irq)
	assert aic.initialise(kio.simulated_aic_base)
	assert !aic.claim_deferred_irq(896)
	mut transport := rtkit.RTKit{name: 'g13-rx-irq'}
	mut mgr := GpuManager{hw_config: hw.HwConfig{gpu_gen: .g13}, rtk: unsafe { &transport }}
	assert mgr.rtkit_receive_due()
	mgr.lock.acquire()
	mgr.claim_rtkit_receive_irq(irq)
	assert mgr.rtkit_receive_irq == irq && kio.aic_cpu_target(irq) == 1
	assert !aic.claim_deferred_irq(579) && !kio.aic_irq_masked(irq)
	for abi in [hw.FirmwareAbi.v12_3, .v13_5_partial]! {
		transport = rtkit.RTKit{name: 'g13-rx-irq'}
		check_irq_boot(mut mgr, irq, abi)
		mgr.finish_rtkit_receive()
	}
	mgr.state = .running
	mgr.lock.release()

	// Ordinary worker maintenance can run between receive checks.
	event_worker(mut mgr)
	assert mgr.polls == 0 && mgr.trace == ['success']
	mgr.state = .running
	timer.busywait_us(999)
	assert !mgr.rtkit_receive_due()
	timer.busywait_us(1)
	assert mgr.rtkit_receive_due()
	transport.mbox.inject(mailbox.MboxMsg{data0: 0x0070000000000220})
	event_worker(mut mgr)
	assert mgr.polls == 1 && transport.iop_power_state == 0x0220
	assert !mgr.rtkit_receive_due() && !kio.aic_irq_masked(irq)
	mgr.state = .running

	// The handler masks the level line until the deferred worker runs.
	unmasks := kio.aic_unmasks()
	transport.mbox.inject(mailbox.MboxMsg{data0: 0x0070000000000020})
	kio.queue_aic_event(irq)
	exception.dispatch()
	assert aic.deferred_irq_pending(irq) && mgr.rtkit_receive_due()
	assert kio.aic_irq_masked(irq) && kio.aic_unmasks() == unmasks
	assert transport.iop_power_state == 0x0220
	event_worker(mut mgr)
	assert mgr.polls == 2 && transport.iop_power_state == 0x20
	assert !aic.deferred_irq_pending(irq) && !kio.aic_irq_masked(irq)
	assert kio.aic_unmasks() == unmasks + 1

	mgr.state = .running
	mgr.shutdown()
	assert kio.aic_irq_masked(irq)
	kio.queue_aic_event(irq)
	exception.dispatch()
	assert kio.aic_irq_masked(irq) && kio.aic_unmasks() == unmasks + 1
	aic.unmask_irq(579)
	kio.queue_aic_event(579)
	exception.dispatch()
	assert !kio.aic_irq_masked(579) && kio.aic_unmasks() == unmasks + 3
	check_silent_irq_boot(irq)
	println('G13 receive IRQ: binding validation, fallback, deferred delivery, shutdown and ordinary IRQ rearm passed')
	println('G13 boot receive IRQ: both firmware ABIs and silent firmware cleanup passed')
}
