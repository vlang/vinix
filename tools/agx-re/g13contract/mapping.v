// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_user_mapping_contract(local string, manager string) ! {
	retire := section(local, 'fn (mut f GpuFile) retire_mapping_locked(',
		'// GEM_CLOSE drops', 'Vinix user mapping retirement')!
	require_order(retire, ['f.find_owned_vm(mapping.vm_id)', 'katomic.load(&ctx.inflight)',
		'if !mapping.retiring', 'pt.unmap(mapping.addr, mapping.size)',
		'f.mappings[index].retiring = true',
		'if !f.finish_file_mapping(true)', 'return false', 'gem.unref(mapping.obj)',
		'f.mappings.delete(index)'], 'Vinix retained mapping backing')!
	require(retire.count('gem.unref(') == 1 && !retire.contains('manager.state'),
		'User mapping retirement releases once after TLBI and the device-state check')!
	bind := section(local, 'pub fn (mut f GpuFile) ioctl_gem_bind(',
		'pub fn (f &GpuFile) ioctl_get_time(', 'Vinix user mapping ioctl')!
	require_order(bind, ['f.lock.acquire()', 'defer { f.lock.release() }', 'match request.op',
		'ioctl.asahi_bind_op_bind {', 'f.objects.get_ref(request.handle)', 'f.find_vm(request.vm_id)',
		'ctx.pgtable', 'pt.map(', 'f.mappings << GpuMapping{',
		'if !f.finish_file_mapping(false)',
		'pt.unmap(request.addr, request.range)', 'f.mappings[f.mappings.len - 1].retiring = true',
		'return -5'], 'Vinix bind ownership transfer')!
	require(bind.count('f.lock.acquire()') == 1 && bind.count('f.lock.release()') == 1
		&& bind.count('f.retire_mapping_locked(i)') == 1
		&& bind.contains('return f.unbind_range_locked(ctx.id, request.addr, request.range)')
		&& !bind.contains('f.get_object_ref('),
		'Bind/unbind must retain their VM borrow under one file lock')!
	failure := section(bind, 'if !f.finish_file_mapping(false)', 'return -5', 'Vinix failed bind state check')!
	require(!failure.contains('gem.unref'), 'A failed bind state check retains the mapping reference')!
	close := section(local, 'pub fn (mut f GpuFile) close()',
		'fn (mut f GpuFile) get_object_ref(', 'Vinix file close mappings')!
	require_order(close, ['f.retire_mapping_locked(index)', 'return false', 'q.destroy()',
		'uat.destroy_context(vm)', 'f.objects.release_all()'], 'Vinix close mapping gate')!
	submit := section(local, 'pub fn (mut f GpuFile) ioctl_submit(', 'fn dispatch(', 'Vinix mapping admission')!
	require_order(submit, ['f.lock.acquire()', 'if !f.cleanup_closed_mappings_locked(vm)',
		'memory.malloc_packed_fallible(sizeof(G13PendingSubmission))'], 'Vinix mapping admission')!
	finish := section(manager, 'pub fn (mut mgr GpuManager) finish_g13_file_mapping(',
		'// Publish a G13 UAT invalidation through', 'Vinix file mapping serialization')!
	require_order(finish, ['mgr.lock.acquire()', 'defer { mgr.lock.release() }',
		'if unmapped && mgr.state == .stopped { return mgr.hw_config.gpu_gen == .g13 }',
		'return mgr.g13_submission_status_locked() == 0'], 'Vinix shutdown-safe file mapping completion')!
	wrapper := section(local, 'fn (f &GpuFile) finish_file_mapping(', 'fn (f &GpuFile) file_uat(', 'Vinix file mapping completion')!
	require_order(wrapper, ['mut gpu_manager := unsafe { f.registration_manager }',
		'if gpu_manager == unsafe { nil } { return false }', 'gpu_manager.finish_g13_file_mapping(unmapped)'],
		'Vinix checks the original device state after the page-table operation')!
	for body in [retire, bind, wrapper, finish] {
		require(!body.contains('flush_g13_uat_range') && !body.contains('flush_firmware_mapping'),
			'GPU-only file mappings use page-table invalidation without FwCtl')!
	}
}

fn check_user_mapping_reference(mmu string) ! {
	mapping := section(mmu, '    fn sm_step_map<', '    /// Unmap existing mapping.', 'Asahi GEM map')!
	require_order(mapping, ['let op = op.insert(', 'self.tlbi_contexts_naming_root(map_addr, map_length)',
		'Ok(op)'], 'Asahi publishes the GPUVA with root visibility')!
	unmap := section(mmu, '    fn unmap_gpuva(', '    /// A failed map', 'Asahi GEM unmap')!
	require_order(unmap, ['.unmap_pages(', 'if let Some(asid) = self.slot()', 'mem::sync()',
		'self.tlbi_range(asid as u8,', 'mem::sync()', 'self.tlbi_contexts_naming_root(', 'Ok(())'],
		'Asahi completes ASID invalidation after unmap')!
	require(!mapping.contains('fwctl(') && !unmap.contains('fwctl('), 'Asahi GEM map and unmap use no ASC cache request')!
}
