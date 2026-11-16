// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_submit_device_local(file string, gpu string) ! {
	submit := section(file, 'pub fn (mut f GpuFile) ioctl_submit(', 'fn dispatch(', 'Native submission device status')!
	require_order(submit, ['defer { memory.free(stage_storage) }', 'agxsubmission.stage_command_array(',
		'agxsubmission.stage_sync_array(', 'manager := gpu.get_global_manager() or { return -19 }',
		'mut state_manager := unsafe { manager }', 'status := state_manager.g13_submission_status()',
		'if status != 0 { return status }', 'f.lock.acquire()', 'agxsubmission.install_output_syncs('],
		'Locked device refusal follows staging with owned-buffer cleanup and precedes file mutation/output publication')!
	gate := section(gpu, 'pub fn (mut mgr GpuManager) g13_submission_status(',
		'pub fn (mut mgr GpuManager) can_query_global_params(', 'Native submission state snapshot')!
	require_order(gate, ['mgr.lock.acquire()', 'status := if mgr.state == .error || mgr.state == .stopped { -19 }',
		'else if mgr.hw_config.gpu_gen != .g13 || mgr.state != .running { -95 }', 'else { 0 }',
		'mgr.lock.release()', 'return status'], 'Device loss precedes unsupported-state refusal and releases its standalone lock')!
	require(gate.count('mgr.lock.acquire()') == 1 && gate.count('mgr.lock.release()') == 1
		&& gate.count('return ') == 1 && !gate.contains('malloc') && !gate.contains('mgr.state = '),
		'Submission snapshot uses one scalar result and no allocation or state mutation')!
}

fn check_submit_device_reference(queue string) ! {
	submit := section(queue, 'impl Queue for Queue::ver {', 'let mut events:', 'Packaged G13 submit crash checkpoint')!
	require_order(submit, ['if gpu.is_crashed()', 'return Err(ENODEV)', 'let op_guard = if in_sync_count > 0',
		'gpu.start_op()?'], 'Packaged crashed submission refuses with ENODEV before operation/job setup')!
}
