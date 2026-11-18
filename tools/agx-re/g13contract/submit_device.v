// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_submit_device_local(file string, gpu string) ! {
	submit := section(file, 'pub fn (mut f GpuFile) ioctl_submit(', 'fn dispatch(', 'Native submission device status')!
	require_order(submit, ['defer { memory.free(stage_storage) }', 'agxsubmission.stage_command_array(',
		'agxsubmission.stage_g13_sync_array(', 'manager := f.registration_manager',
		'if manager == unsafe { nil } { return -19 }',
		'mut gpu_manager := unsafe { manager }', 'status := gpu_manager.g13_submission_status()',
		'if status != 0 { return status }', 'f.lock.acquire()', 'agxsubmission.install_output_syncs('],
		'Locked device refusal follows staging with owned-buffer cleanup and precedes file mutation/output publication')!
	gate := section(gpu, 'pub fn (mut mgr GpuManager) g13_submission_status(',
		'fn (mgr &GpuManager) g13_submission_status_locked(', 'Native submission state snapshot')!
	classify := section(gpu, 'fn (mgr &GpuManager) g13_submission_status_locked(',
		'pub fn (mut mgr GpuManager) try_hold_g13_submission_slot(', 'Native submission state classification')!
	require_order(gate, ['mgr.lock.acquire()', 'defer { mgr.lock.release() }',
		'return mgr.g13_submission_status_locked()'], 'Snapshot classifies device state under its standalone lock')!
	require_order(classify, ['return if mgr.state == .error || mgr.state == .stopped { -19 }',
		'else if mgr.hw_config.gpu_gen != .g13 || mgr.state != .running { -95 }', 'else { 0 }'],
		'Device loss precedes unsupported-state refusal')!
	require(gate.count('mgr.lock.acquire()') == 1 && gate.count('mgr.lock.release()') == 1
		&& gate.count('return ') == 1 && !gate.contains('malloc') && !gate.contains('mgr.state = ')
		&& !classify.contains('malloc') && !classify.contains('mgr.state = '),
		'Submission snapshot uses one scalar result and no allocation or state mutation')!
	retry := section(gpu, 'pub fn (mut mgr GpuManager) try_hold_g13_submission_slot(',
		'pub fn (mut mgr GpuManager) can_query_global_params(', 'Native slot reacquisition')!
	require_order(retry, ['mgr.lock.acquire()', 'defer { mgr.lock.release() }',
		'status := mgr.g13_submission_status_locked()', 'if status != 0 { return status }',
		'return int(mgr.uat.bind_context(vm))'], 'Submit after a wake rechecks device status and binds through its manager UAT')!
}

fn check_submit_device_reference(queue string) ! {
	submit := section(queue, 'impl Queue for Queue::ver {', 'let mut events:', 'Packaged G13 submit crash checkpoint')!
	require_order(submit, ['if gpu.is_crashed()', 'return Err(ENODEV)', 'let op_guard = if in_sync_count > 0',
		'gpu.start_op()?'], 'Packaged crashed submission refuses with ENODEV before operation/job setup')!
}

fn check_modern_submit_device_local(submit string) ! {
	require_order(submit, ['mut manager := unsafe { f.registration_manager }',
		'if manager != unsafe { nil } { manager.refresh_g13_submit_globals() }',
		'capture_submission_queue(data.queue_id)', 'submission.stage_packet_syncs(',
		'defer { if packet != unsafe { nil } { memory.free(packet) } }',
		'if data.cmdbuf_size != 0', 'memory.malloc_packed_fallible(data.cmdbuf_size)',
		'usercopy.copy_from_user(packet, data.cmdbuf, data.cmdbuf_size)',
		'if manager == unsafe { nil } { return -19 }',
		'status := manager.g13_submission_status()',
		'if status != 0 { return status }', 'if data.cmdbuf_size == 0 { return -22 }',
		'memory.malloc_packed_fallible(sizeof(submission.PacketWorkspace))', 'submission.decode_packet(',
		'f.submit_g13_staged('], 'Modern submit checks the device after copying and before parsing')!
	require(submit.count('if data.cmdbuf_size == 0') == 1 && submit.count('g13_submission_status()') == 1,
		'Modern submit must defer empty-packet rejection until after the device check')!
	require(!submit.contains('gpu.get_global_manager()'), 'Modern submit remains on the file registration')!
}

fn check_modern_submit_device_reference(file string, queue string) ! {
	submit := section(file, 'pub(crate) fn submit(', 'pub(crate) fn get_time(', 'Asahi modern staging')!
	require_order(submit, ['.ok_or(ENOENT)?', 'let guarded = ', 'SyncItem::parse_array(',
		'if !guarded {', 'copy_commands(&mut vec)?', 'queue.lock().submit('],
		'Asahi unguarded G13 submit snapshots bytes after sync staging')!
	parse := queue.all_after('impl Queue for Queue::ver {')
	require_order(parse, ['if gpu.is_crashed()', 'return Err(ENODEV)', 'let mut cmdbuf = Reader::new(cmdbuf_raw)',
		'while !cmdbuf.is_empty()', 'if nr_hw_commands == 0 || nr_hw_commands > MAX_COMMANDS_PER_SUBMISSION'],
		'Asahi checks device loss before parsing and hardware-command validation')!
}

fn check_submit_idle_delay_reference(file string, manager string, layout string) ! {
	submit := section(file, 'pub(crate) fn submit(', 'pub(crate) fn get_time(', 'Asahi submit Globals refresh')!
	require_order(submit, ['if data.flags != 0 || data.pad != 0', 'return Err(EINVAL)',
		'if let Some(manager) = gpu.manager()', 'manager.update_globals()', '.queues()', 'SyncItem::parse_array('],
		'Asahi refreshes Globals after header validation and before queue lookup')!
	refresh := section(manager, 'fn update_globals(&self) {', 'fn alloc(&self)', 'Asahi idle delay refresh')!
	require_order(refresh, ['let mut timeout: u32 = 2;', 'DebugFlags::WaitForPowerOff',
		'timeout = 0;', 'DebugFlags::KeepGpuPowered', 'timeout = 5000;',
		'raw.idle_off_delay_ms.store(timeout, Ordering::Relaxed)'], 'Asahi normal and debug idle delays')!
	require(layout.contains('idle_off_delay_ms: AtomicU32'), 'Asahi idle delay must be a firmware-visible 32-bit atomic')!
}

fn check_submit_idle_delay_local(submit string, manager string) ! {
	require_order(submit, ['if data.flags != 0 || data.pad != 0 { return -22 }',
		'manager.refresh_g13_submit_globals()', 'f.capture_submission_queue('],
		'Modern G13 refreshes the idle delay before queue lookup')!
	refresh := section(manager, 'pub fn (mut mgr GpuManager) refresh_g13_submit_globals()',
		'// The firmware samples pending_submissions', 'Vinix idle delay refresh')!
	require_order(refresh, ['mgr.lock.acquire()', 'defer { mgr.lock.release() }',
		'mgr.state != .running || mgr.hw_config.gpu_gen != .g13 || mgr.g13_channels == unsafe { nil }',
		'fw.g13_globals_idle_off_delay_offset(mgr.hw_config.firmware_abi)',
		'globals.phys == 0 || globals.size < offset + sizeof(u32)',
		'&u32(u64(globals.cpu_address()) + offset)', 'katomic.store(mut field, u32(2))'],
		'Vinix writes only the active Globals ABI field while holding the shutdown lock')!
}
