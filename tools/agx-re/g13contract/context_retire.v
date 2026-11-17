// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_context_retire_local(wire string, garbage string, queues string) ! {
	command := section(wire, 'pub fn make_g13_context_invalidate(', '\n}\n', 'Context command')!
	require_order(command, ['context == unsafe { nil } || size < 0x40 || address == 0',
		'.v12_3 { 0x14 }', '.v13_5_partial { 0x11 }', 'else { return none }',
		'pointer_offset := if abi == .v12_3 { 0x1c } else { 0x14 }',
		'bytes[8] = data[0x23]', 'bytes[context_offset] = data[0]', 'bytes[context_offset + 1] = data[1]',
		'bytes[context_offset + 2] = data[4]', 'for i in 0 .. 8', 'u8(address >> (8 * i))'], 'Context IDs and packed weak pointer follow the versioned ABI')!
	retire := section(garbage, 'fn (mut mgr GpuManager) invalidate_g13_context_locked(', '\n}\n', 'Context retirement')!
	require_order(retire, ['if resources.context_retirement == .complete { return true }',
		'if resources.context_retirement == .pending { return false }', 'mgr.state != .running',
		'!resources.context.mapped', 'private_count, _ := mgr.g13_private.garbage()',
		'readonly_count, _ := mgr.g13_gpu_readonly.garbage()', 'katomic.sync()', 'fw.make_g13_context_invalidate(',
		'enqueue_with_token(voidptr(&message)) or { return false }', 'resources.context_retirement = .pending',
		'if !mgr.ring_device_control() { return false }', 'for mgr.channels.device_ctrl.read_pointer() != token',
		'1_000_000_000', 'katomic.sync()', 'resources.context_retirement = .complete',
		'mgr.g13_private.collect_garbage(private_count)', 'mgr.g13_gpu_readonly.collect_garbage(readonly_count)', 'return true'], 'Publication is one-shot and acknowledgement gates both captured heap prefixes')!
	require(!retire.contains('.gc()') && !retire.contains('= .fresh'), 'Failure cannot collect later garbage or reset published retirement')!
	require(queues.contains('context_retirement G13ContextRetirement'), 'Queue owns one scalar retirement state')!
	free := section(queues, 'fn (mut mgr GpuManager) free_g13_queue_resources_locked(', '\n}\n', 'Queue lifetime gate')!
	require_order(free, ['if resources.released', 'if invalidate && (!mgr.invalidate_g13_context_locked(mut resources)',
		'|| !mgr.invalidate_g13_queue_mappings_locked(mut resources)', 'return false', 'resources.released = true',
		'mgr.free_shared_buffer(mut resources.context)'], 'Context acknowledgement precedes UAT invalidation and backing release')!
}

fn check_context_retire_reference(manager string, channels string, queues string) ! {
	retire := section(manager, '    fn invalidate_context(', '\n}\n', 'Asahi context retirement')!
	require_order(retire, ['if self.is_crashed()', 'guard.private.garbage()', 'guard.gpu_ro.garbage()',
		'DeviceControlMsg::ver::DestroyContext', 'ctx_23: raw.unk_23', 'ctx_0: raw.unk_0',
		'ctx_1: raw.unk_1', 'ctx_4: raw.unk_4', 'gpu_context: Some(context.weak_pointer())',
		'device_control.send(&dc)', 'DOORBELL_DEVCTRL', 'device_control.wait_for(token)?',
		'guard.private.collect_garbage(garbage_count)', 'guard.gpu_ro.collect_garbage(garbage_count_gpuro)'], 'Asahi keeps context and snapshots through the acknowledged command')!
	layout := section(channels, '    DestroyContext {', '    Unk18(', 'Asahi packed context pointer')!
	require_order(layout, ['ctx_4: u8', '#[ver(V < V13_3)]', '__pad1: Pad<1>', '#[ver(V < V13_3)]',
		'unk_18: u32', 'gpu_context: Option<GpuWeakPointer', 'DEVICECONTROL_SZ::ver - 0x20',
		'DEVICECONTROL_SZ::ver - 0x18'], 'Versioned tail padding fixes pointer byte offsets')!
	raw := section(queues, '    pub(crate) struct GpuContextData {', '    impl Default for GpuContextData', 'Asahi context bytes')!
	require_order(raw, ['unk_0: u8', 'unk_1: u8', 'unk_2: Array<0x2, u8>', 'unk_4: u8',
		'unk_5: u8', 'unk_6: Array<0x18, u8>', 'unk_1e: u8', 'unk_1f: u8',
		'unk_20: Array<0x3, u8>', 'unk_23: u8', 'unk_24: Array<0x1c, u8>'], 'Raw context IDs occupy 0/1/4/0x23 of the 0x40-byte object')!
}
