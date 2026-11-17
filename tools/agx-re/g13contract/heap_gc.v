// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_heap_gc_local(source string, manager string, wire string) ! {
	require(source.contains('g13_max_fw_garbage_bytes = u64(16 * 1024 * 1024)')
		&& source.contains('g13_max_fw_garbage_objects = u64(2048)'), 'Firmware GC uses upstream thresholds')!
	collect := section(source, 'fn (mut mgr GpuManager) collect_g13_heap_garbage_locked()', '\n}\n', 'Firmware GC')!
	require_order(collect, ['mgr.state != .running || mgr.hw_config.gpu_gen != .g13',
		'private_count, private_bytes := mgr.g13_private.garbage()',
		'readonly_count, readonly_bytes := mgr.g13_gpu_readonly.garbage()',
		'if !g13_heap_garbage_needs_collection(', 'if !mgr.flush_g13_fw_cache_locked()',
		'return', 'mgr.g13_private.collect_garbage(private_count)',
		'mgr.g13_gpu_readonly.collect_garbage(readonly_count)'], 'Cache barrier precedes bounded snapshot collection')!
	require(!collect.contains('.gc()'), 'Collection must not include later releases')!
	barrier := section(source, 'fn (mut mgr GpuManager) flush_g13_fw_cache_locked()', '\n}\n', 'Cache barrier')!
	require_order(barrier, ['mgr.state != .running || mgr.hw_config.gpu_gen != .g13',
		'fw.make_g13_cache_flush(mgr.hw_config.firmware_abi) or { return false }',
		'enqueue_with_token(voidptr(&message)) or { return false }',
		'if !mgr.ring_device_control() { return false }',
		'for mgr.channels.device_ctrl.read_pointer() != token', '1_000_000_000',
		'katomic.sync()', 'return true'], 'Device-control publication waits for its own token')!
	require(!barrier.contains('sched.yield('), 'Cache polling must not enter the dying-thread scheduler path')!
	allocation := section(manager, 'fn (mut mgr GpuManager) alloc_g13_buffer_with_protection(', '\n}\n', 'G13 allocator entry')!
	require_order(allocation, ['protection != pgtable.gpu_prot_fw_private_rw',
		'pgtable.gpu_prot_gpu_ro_fw_private_rw { return none }',
		'mgr.collect_g13_heap_garbage_locked()', 'return match protection'], 'All supported G13 classes check collection before allocation')!
	command := section(wire, 'pub fn make_g13_cache_flush(', '\n}\n', 'Cache flush wire command')!
	require_order(command, ['.v12_3 { 0x14 }', '.v13_5_partial { 0x11 }', 'else { return none }',
		'tag: if abi == .v12_3 { device_control_destroy_context_v12_3 } else { device_control_destroy_context_v13_5 }',
		'bytes[context_offset] = 0xff', 'bytes[context_offset + 1] = 0xff'], 'No-op context IDs occupy the versioned byte offsets')!
	require(wire.contains('device_control_destroy_context_v12_3 = u32(0x17)')
		&& wire.contains('device_control_destroy_context_v13_5 = u32(0x18)'), 'Versioned DestroyContext discriminants')!
}

fn check_heap_gc_reference(source string, channels string) ! {
	require(source.contains('MAX_FW_ALLOC_GARBAGE_BYTES: usize = 16 * 1024 * 1024')
		&& source.contains('MAX_FW_ALLOC_GARBAGE_OBJECTS: usize = 2048'), 'Asahi collection thresholds')!
	collect := section(source, "fn alloc(&self) -> Guard<'_, KernelAllocators, MutexBackend> {", '\n    fn bind_vm(', 'Asahi allocator entry')!
	require_order(collect, ['guard.private.garbage()', 'guard.gpu_ro.garbage()',
		'garbage_bytes > MAX_FW_ALLOC_GARBAGE_BYTES', 'ro_garbage_bytes > MAX_FW_ALLOC_GARBAGE_BYTES',
		'garbage_count > MAX_FW_ALLOC_GARBAGE_OBJECTS', 'ro_garbage_count > MAX_FW_ALLOC_GARBAGE_OBJECTS',
		'if self.flush_fw_cache().is_err()', '} else {', 'guard.private.collect_garbage(garbage_count)',
		'guard.gpu_ro.collect_garbage(ro_garbage_count)'], 'Asahi checks both heaps and collects pre-flush counts on success')!
	barrier := section(source, 'fn flush_fw_cache(&self) -> Result {', '\n    fn handle_timeout(', 'Asahi firmware cache barrier')!
	require_order(barrier, ['DeviceControlMsg::ver::DestroyContext', 'ctx_0: 0xff', 'ctx_1: 0xff',
		'gpu_context: None', 'device_control.send(&dc)', 'DOORBELL_DEVCTRL', 'device_control.wait_for(token)?'], 'Asahi no-op context command and completion token')!
	layout := section(channels, '    DestroyContext {', '    Unk18(', 'Asahi DestroyContext layout')!
	require_order(channels, ['#[ver(V >= V13_3)]', 'Unk0d(', 'GrowTVBAck {', 'DestroyContext {'], 'The extra v13.3 variant shifts later tags')!
	require_order(layout, ['unk_4: u32', 'ctx_23: u8', '#[ver(V < V13_3)]', '__pad0: Pad<3>',
		'unk_c: U32', 'unk_10: U32', 'ctx_0: u8', 'ctx_1: u8', 'ctx_4: u8'], 'Versioned sentinel offsets follow packed U32 fields')!
}
