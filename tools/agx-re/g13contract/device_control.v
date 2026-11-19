// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_g13_device_control_wire(channels string, initdata string, grow string, recovery string,
	wire string, status string) ! {
	device := section(channels, 'pub(crate) enum DeviceControlMsg {', '    IdlePowerOff {', 'Asahi DeviceControlMsg tags')!
	before := device.all_before('#[ver(V >= V13_3)]')
	require(before.count('Unk0') == 13, 'Thirteen legacy variants precede GrowTVBAck')!
	require_order(device, ['Unk0c(', '#[ver(V >= V13_3)]', 'Unk0d(', 'GrowTVBAck {', 'RecoverChannel {'],
		'Asahi inserts one enum tag before both commands from 13.3')!
	flags := section(initdata, 'struct FwStatusFlags {', 'struct FwStatus {', 'Asahi firmware status')!
	require(flags.contains('halt_count: AtomicU64'), 'Asahi reads the full halt counter')!
	require_order(status, ['pub struct G13FwStatus {', 'halt_count u64', 'pad_18     [0x8]u8', 'halted     u32'],
		'Vinix preserves the status geometry and halt count width')!
	for constant in ['device_control_grow_tvb_ack_v12_3 = u32(0x0d)',
		'device_control_grow_tvb_ack_v13_5 = u32(0x0e)', 'device_control_recover_channel_v12_3 = u32(0x0e)',
		'device_control_recover_channel_v13_5 = u32(0x0f)'] {
		require(wire.contains(constant), 'G13 versioned device-control tag ${constant}')!
	}
	for builder, command in {'make_grow_tvb_ack': 'grow_tvb_ack', 'make_recover_channel': 'recover_channel'} {
		method := section(wire, 'pub fn ${builder}(', '\n}\n', 'Vinix ${builder}')!
		require_order(method, ['abi hw.FirmwareAbi', 'tag := match abi',
			'.v12_3 { device_control_${command}_v12_3 }', '.v13_5_partial { device_control_${command}_v13_5 }',
			'else { return none }', 'tag: tag'], 'Vinix selects the requested ABI for ${builder}')!
	}
	ack := section(grow, 'fn (mut mgr GpuManager) handle_g13_grow_tvb(', '// Allocate the two event-counter arrays', 'Vinix TVB acknowledgement')!
	require_order(ack, ['mgr.lock.acquire()', 'defer', 'mgr.ensure_g13_tvb_blocks',
		'if mgr.state != .running { return }', 'fw.make_grow_tvb_ack(mgr.hw_config.firmware_abi',
		'katomic.load[u64](&status.halt_count)', 'mgr.channels.device_ctrl.enqueue(voidptr(&ack))',
		'mgr.ring_g13_doorbell_locked(doorbell_device_control)', 'if mgr.state == .running', 'mgr.state = .error'],
		'Vinix passes the full counter and retains shutdown state after waiting')!
	require_order(recovery.all_after('fn (mut mgr GpuManager) recover_g13_channel('),
		['fw.make_recover_channel(mgr.hw_config.firmware_abi',
			'mgr.channels.device_ctrl.enqueue_tracked', 'owner.retain_file_reference()',
			'mgr.g13_recovery_queue = owner', 'sent := mgr.ring_g13_doorbell_locked(doorbell_device_control)',
			'if mgr.state != .running { return false }', 'mgr.channels.device_ctrl.ticket_consumed(ticket)',
			'mgr.release_g13_recovery_queue_locked()', 'if mgr.state == .running { mgr.state = .error }'],
		'Vinix pins the published recovery, checks the device after the IRQ wait and releases the owner on consumption')!
	require_order(recovery.all_after('fn (mut mgr GpuManager) release_g13_recovery_queue_locked('),
		['mgr.g13_recovery_queue = unsafe { nil }', 'owner.release_file_reference()'],
		'Vinix clears the manager pointer before dropping its recovery reference')!
}
