// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import os

fn check_g13_receive_lifetime(local string, remote string, recovery string) ! {
	doorbell := section(remote, 'fn recv_message(', 'fn crashed(', 'Asahi firmware receive')!
	require_order(doorbell, ['if ep != EP_FIRMWARE || msg != MSG_RX_DOORBELL',
		'let mut ch = data.rx_channels.lock()', 'ch.fw_log.poll()', 'ch.ktrace.poll()', 'ch.stats.poll()', 'ch.event.poll()'],
		'Asahi serializes firmware receive dispatch under its RX mutex')!
	read := section(local, 'fn (mut mgr GpuManager) dequeue_g13_rx(', 'fn (mut mgr GpuManager) mark_g13_worker_error(', 'Vinix firmware read')!
	require_order(read, ['mgr.lock.acquire()', 'defer { mgr.lock.release() }',
		'return mgr.state == .running && rx.dequeue(destination)'], 'Vinix protects each RX read until the copy and acknowledgement complete')!
	dispatch := section(local, 'pub fn (mut mgr GpuManager) handle_event()', 'fn (mut mgr GpuManager) handle_role_system_message(', 'Vinix event dispatch')!
	require_order(dispatch, ['mgr.dequeue_g13_rx(mut mgr.channels.event, voidptr(&buf[0]))',
		'*&fw.FwEventMsg(&buf[0])', 'match message.tag', 'event.scan_all_completions()',
		'mgr.recover_g13_fault(', 'mgr.mark_g13_worker_error()', 'mgr.recover_g13_channel(',
		'mgr.handle_g13_grow_tvb(message.payload[0], message.payload[1], message.payload[2])'],
		'Vinix dispatches from its private event copy outside the receive lock')!
	aux := section(local, 'fn (mut mgr GpuManager) drain_auxiliary_channels()', 'fn (mut mgr GpuManager) check_g13_firmware_health()', 'Vinix auxiliary receive')!
	require_order(aux, ['mgr.read_g13_fw_log(subchannel)', 'mgr.dequeue_g13_rx(mut mgr.channels.ktrace',
		'mgr.dequeue_g13_rx(mut mgr.channels.stats'], 'FWLog, KTrace and Stats drain in firmware receive order')!
	poll := section(local, 'fn (mut mgr GpuManager) poll_rtkit_messages(', '// The manager lock guards teardown', 'Vinix RTKit receive order')!
	require_order(poll, ['mgr.recv_role_message(role)', 'ep == u8(ep_firmware) && msg.data0 == msg_rx_doorbell',
		'role == 0 && mgr.hw_config.gpu_gen == .g13', 'mgr.drain_g13_receive_channels()',
		'if mgr.state != .running { return true }'], 'A G13 firmware doorbell drains its rings before the next RTKit message')!
	drain := section(local, 'fn (mut mgr GpuManager) drain_g13_receive_channels()', '// Caller holds mgr.lock.', 'Vinix G13 receive dispatch')!
	require_order(drain, ['mgr.drain_auxiliary_channels()', 'mgr.handle_event()'],
		'G13 drains diagnostics before firmware events can trigger recovery or teardown')!
	worker := section(local, 'fn event_worker(', '// Shutdown the GPU', 'Vinix receive worker')!
	require_order(worker, ['mgr.check_g13_firmware_health()', 'mgr.poll_rtkit_messages()',
		'if mgr.state != .running', 'if mgr.hw_config.gpu_gen == .g13',
		'mgr.drain_g13_receive_channels()', 'mgr.check_g13_firmware_health()'],
		'G13 workers use the same ordered drain even without a mailbox doorbell')!
	loss := section(local, 'fn (mut mgr GpuManager) mark_g13_worker_error()', 'pub fn (mut mgr GpuManager) handle_event()', 'Vinix worker error')!
	require_order(loss, ['mgr.lock.acquire()', 'if mgr.state == .running { mgr.state = .error }', 'mgr.lock.release()'],
		'An asynchronous receive failure cannot overwrite stopped state')!
	stop := local.all_after('pub fn (mut mgr GpuManager) shutdown()')
	require_order(stop, ['mgr.lock.acquire()', 'if mgr.state == .stopped { return }', 'mgr.state = .stopped',
		'mgr.stop_firmware_cpus(mgr.firmware_roles)', 'mgr.release_g13_channels()'],
		'Vinix marks stopped and releases RX backing under the same lock')!
	require_order(recovery.all_after('fn (mut mgr GpuManager) recover_g13_channel('), [
		'mgr.lock.acquire()', 'if mgr.state != .running { return false }', 'mgr.mark_g13_slot_error_locked(',
		'mgr.channels.device_ctrl.enqueue_with_token('], 'Channel recovery declines stale requests after loss or teardown')!
}

fn check_g13_receive_irq(asahi_linux string, repo string) ! {
	dts := read(os.join_path(asahi_linux, 'arch/arm64/boot/dts/apple/t8103.dtsi'))!
	node := section(dts, 'agx_mbox: mbox@206408000', 'cpufreq_e:', 'Asahi M1 mailbox binding')!
	require_order(node, ['interrupt-parent = <&aic>', '<AIC_IRQ 578 IRQ_TYPE_LEVEL_HIGH>',
		'"recv-empty", "recv-not-empty"'], 'Asahi names the level-triggered M1 GPU mailbox receive line')!
	linux := read(os.join_path(asahi_linux, 'drivers/soc/apple/mailbox.c'))!
	handler := section(linux, 'static irqreturn_t apple_mbox_recv_irq(', 'int apple_mbox_poll(', 'Asahi receive IRQ handler')!
	require_order(handler, ['spin_lock(&mbox->rx_lock)', 'apple_mbox_poll_locked(mbox)', 'spin_unlock(&mbox->rx_lock)'],
		'Asahi drains its receive mailbox on the receive IRQ')!
	irqchip := read(os.join_path(asahi_linux, 'drivers/irqchip/irq-apple-aic.c'))!
	require(irqchip.contains('Reading the interrupt reason automatically acknowledges and masks')
		&& irqchip.contains('irqc->info.target_cpu + off + i * 4, 1'),
		'Asahi acknowledges with auto-mask and targets CPU 0 by default on AICv1')!

	driver := read(os.join_path(repo, 'kernel/gpu/agx/driver/driver.v'))!
	require_order(driver, ["find_compatible('apple,t8103-aic')", "get_property(node, 'interrupt-names')",
		'mailbox.decode_aic_receive_irq(', 'mailbox_receive_irq: g13_mailbox_receive_irq(mailbox_node)',
		'receive_irq := if chip_id == 0x8103 { platform.mailbox_receive_irq }', 'if !mgr.init(receive_irq)',
		'agx_driver_inst.gpu = mgr', 'gpu.set_global_manager(agx_driver_inst.gpu)'],
		'Vinix passes the M1 AICv1 binding to the private probe before publishing the manager')!
	controller := read(os.join_path(repo, 'kernel/aarch64/aic/aic.v'))!
	require_order(controller, ['irq == katomic.load(&deferred_irq)', 'katomic.store(mut deferred_pending, true)',
		'continue', 'unmask_irq(irq)', 'pub fn claim_deferred_irq(', 'aic_write(aic_target_cpu + irq * 4, 1)',
		'unmask_irq(irq)'], 'Vinix leaves the deferred line masked and programs CPU 0 before enabling it')!
	manager := read(os.join_path(repo, 'kernel/gpu/agx/gpu/gpu.v'))!
	failure := section(manager, 'fn (mut mgr GpuManager) fail_g13_initialization(', '// Allocate the completion-tracking resources', 'Vinix failed boot cleanup')!
	require_order(failure, ['aic.mask_irq(mgr.rtkit_receive_irq)', 'mgr.stop_firmware_cpus(mgr.firmware_roles)',
		'mgr.release_rtkit_buffers()', 'mgr.release_g13_channels()'], 'Vinix masks the claimed line and stops firmware before boot teardown')!
	require_order(manager, ['aic.deferred_irq_pending(mgr.rtkit_receive_irq)', 'timer.get_us() - mgr.rtkit_receive_us >= 1_000',
		'poll_mailbox && !mgr.poll_rtkit_messages()', 'if still_healthy && poll_mailbox { mgr.finish_rtkit_receive() }',
		'mgr.state = .stopped', 'aic.mask_irq(mgr.rtkit_receive_irq)', 'mgr.stop_firmware_cpus(mgr.firmware_roles)'],
		'Vinix drains in the worker, polls on timeout and masks the line before firmware stop')!
}
