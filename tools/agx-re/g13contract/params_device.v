// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_params_device_local(file string, gpu string) ! {
	query := section(file, 'pub fn (f &GpuFile) ioctl_get_params(', 'pub fn (mut f GpuFile) ioctl_vm_create(', 'Native parameter-query device state')!
	require_order(query, ['request.extensions != 0 || request.param_group != 0 || request.pad != 0',
		'return -22', 'manager := gpu.get_global_manager() or { return -19 }',
		'mut gpu_manager := unsafe { manager }', 'if !gpu_manager.can_query_global_params() { return -19 }',
		'params := make_global_params(manager)', 'return agxparams.copy_global('],
		'Global queries reject lost devices after header validation and before formatting/copying')!
	gate := section(gpu, 'pub fn (mut mgr GpuManager) can_query_global_params(', 'pub fn new_gpu_manager(', 'Locked parameter-query state snapshot')!
	require_order(gate, ['mgr.lock.acquire()', 'defer { mgr.lock.release() }',
		'return mgr.state != .error && mgr.state != .stopped'],
		'Parameter state snapshot shares the shutdown lock and releases it before caller copying')!
	require(!gate.contains('malloc') && !gate.contains('copy_to_user') && !gate.contains('mgr.state ='),
		'Query state snapshot neither allocates, copies nor changes manager state')!
}

fn check_params_device_reference(file string, gpu string) ! {
	query := section(file, 'pub(crate) fn get_params(', '/// Query only file-owned VM state;', 'Packaged parameter-query crash check')!
	require_order(query, ['if data.param_group != 0 || data.pad != 0', 'return Err(EINVAL)',
		'if gpu.is_crashed()', 'return Err(ENODEV)', 'let memory_limits', 'gpu.get_params(&mut params)?',
		'params_writer.write_slice('], 'Packaged global query rejects crash before formatting or copying')!
	gate := section(gpu, 'fn is_crashed(&self) -> bool {', 'fn get_params(', 'Packaged one-time crash snapshot')!
	require(gate.contains('self.crashed.load(Ordering::Relaxed)'), 'Packaged crash query is a snapshot, not a lock across usercopy')!
}
