// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_user_mapping_contract(local string, manager string) ! {
	retire := section(local, 'fn (mut f GpuFile) retire_mapping_locked(',
		'// GEM_CLOSE drops', 'Vinix user mapping retirement')!
	require_order(retire, ['katomic.load(&f.inflight_by_vm[mapping.vm_id])',
		'f.find_vm(mapping.vm_id)', 'if !mapping.retiring', 'pt.unmap(mapping.addr, mapping.size)',
		'f.mappings[index].retiring = true',
		'if !flush_firmware_mapping(ctx, mapping.addr, mapping.size, true)',
		'return false', 'gem.unref(mapping.obj)', 'f.mappings.delete(index)'], 'Vinix retained mapping backing')!
	require(retire.count('gem.unref(') == 1 && !retire.contains('manager.state'),
		'User mapping retirement must release once after the serialized flush')!
	bind := section(local, 'pub fn (mut f GpuFile) ioctl_gem_bind(',
		'pub fn (f &GpuFile) ioctl_get_time(', 'Vinix user mapping ioctl')!
	require_order(bind, ['f.lock.acquire()', 'defer { f.lock.release() }', 'match request.op',
		'ioctl.asahi_bind_op_bind {', 'f.objects.get_ref(request.handle)', 'f.find_vm(request.vm_id)',
		'ctx.pgtable', 'pt.map(', 'f.mappings << GpuMapping{',
		'if !flush_firmware_mapping(ctx, request.addr, request.range, false)',
		'pt.unmap(request.addr, request.range)', 'f.mappings[f.mappings.len - 1].retiring = true',
		'return -5'], 'Vinix bind ownership transfer')!
	require(bind.count('f.lock.acquire()') == 1 && bind.count('f.lock.release()') == 1
		&& bind.count('f.retire_mapping_locked(i)') == 2 && !bind.contains('f.get_object_ref('),
		'Bind/unbind must retain their VM borrow under one file lock')!
	failure := section(bind, 'if !flush_firmware_mapping(ctx, request.addr, request.range, false)',
		'return -5', 'Vinix failed bind flush')!
	require(!failure.contains('gem.unref'), 'A failed bind flush must retain the mapping reference')!
	close := section(local, 'pub fn (mut f GpuFile) close()',
		'fn (mut f GpuFile) get_object_ref(', 'Vinix file close mappings')!
	require_order(close, ['f.retire_mapping_locked(index)', 'return false', 'q.destroy()',
		'm.destroy_context(vm)', 'f.objects.release_all()'], 'Vinix close mapping gate')!
	submit := section(local, 'pub fn (mut f GpuFile) ioctl_submit(', 'fn dispatch(', 'Vinix mapping admission')!
	require_order(submit, ['f.lock.acquire()', 'if !f.cleanup_closed_mappings_locked(vm_id)',
		'memory.malloc_packed_fallible(sizeof(G13PendingSubmission))'], 'Vinix mapping admission')!
	flush := section(manager, 'pub fn (mut mgr GpuManager) flush_g13_file_mapping(',
		'// Publish a G13 UAT invalidation through', 'Vinix file flush serialization')!
	require_order(flush, ['mgr.lock.acquire()', 'defer { mgr.lock.release() }',
		'if unmapped && mgr.state == .stopped', 'return true',
		'mgr.flush_g13_uat_range(slot, addr, size)'], 'Vinix shutdown-safe file flush')!
}
