// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_vm_detach_local(file string) ! {
	visible := section(file, 'fn (f &GpuFile) find_vm(', '// Internal owners survive', 'Visible VM namespace')!
	require_order(visible, ['vm_id < mmu.uat_num_contexts && f.detached_vms[vm_id]', 'return none', 'return f.find_owned_vm(vm_id)'], 'Hidden names do not resolve to physical owners')!
	owned := section(file, 'fn (f &GpuFile) find_owned_vm(', 'fn ranges_overlap(', 'Physical VM owner')!
	require_order(owned, ['for vm in f.vms', 'if vm.id == vm_id', 'return unsafe { vm }'], 'Physical lookup remains valid after namespace removal')!
	require(!owned.contains('detached_vms'), 'Physical ownership cannot depend on name visibility')!
	create := section(file, 'pub fn (mut f GpuFile) ioctl_vm_create(', 'pub fn (mut f GpuFile) ioctl_vm_destroy(', 'VM namespace publication')!
	require_order(create, ['f.lock.acquire()', 'f.detached_vms[ctx.id] = false', 'f.vms << ctx', 'f.lock.release()'], 'Reused slots publish a visible new name')!
	destroy := section(file, 'pub fn (mut f GpuFile) ioctl_vm_destroy(', '// Caller holds file.lock. User bindings', 'VM namespace removal')!
	require_order(destroy, ['request.extensions != 0 || request.pad != 0', 'return -22',
		'if request.vm_id == 0 || request.vm_id >= mmu.uat_num_contexts { return -2 }',
		'f.lock.acquire()', 'defer { f.lock.release() }', 'f.find_vm(request.vm_id) or { return -2 }',
		'f.detached_vms[vm.id] = true', 'f.reap_detached_vms_locked()', 'return 0'], 'Remove validated names before deferred physical retirement')!
	require(!destroy.contains('return -16') && !destroy.contains('destroy_context('), 'Busy owners must not prevent namespace removal or be destroyed directly')!
	reap := section(file, 'fn (mut f GpuFile) reap_detached_vms_locked()', 'pub fn (mut f GpuFile) ioctl_gem_create(', 'Detached physical VM retirement')!
	require_order(reap, ['if uat_mgr == unsafe { nil } { return }', 'index := f.vms.len - 1',
		'vm_id := vm.id', 'vm_id >= mmu.uat_num_contexts || !f.detached_vms[vm_id]',
		'katomic.load(&f.inflight_by_vm[vm_id]) != 0', 'if !f.cleanup_closed_mappings_locked(vm_id) { continue }',
		'for queue in f.queues', 'queue.vm_id == vm_id', 'for ownership in f.g13_queues',
		'ownership.vm_id == vm_id', 'if retained { continue }', 'manager.destroy_context(vm)',
		'f.vms.delete(index)', 'f.detached_vms[vm_id] = false'], 'Retire mappings then exclude every job/queue owner before physical context removal')!
	for token in ['memory.', 'free(', 'f.vms <<'] { require(!reap.contains(token), 'VM reaper must not allocate, free metadata or grow its ownership array')! }
	cleanup := section(file, 'fn (mut f GpuFile) cleanup_closed_mappings_locked(', 'fn (mut f GpuFile) close_object_handle(', 'Detached user bindings')!
	require_order(cleanup, ['katomic.load(&f.inflight_by_vm[vm_id]) != 0',
		'!f.detached_vms[vm_id] && !mapping.retiring && f.objects.contains(mapping.obj)', 'f.retire_mapping_locked(index)'], 'Every idle detached user mapping retires even while its BO name remains live')!
	retire := section(file, 'fn (mut f GpuFile) retire_mapping_locked(', '// GEM_CLOSE drops', 'Hidden mapping owner')!
	require(retire.contains('f.find_owned_vm(mapping.vm_id)'), 'Retained mappings must find their hidden physical VM')!
	submit := section(file, 'pub fn (mut f GpuFile) ioctl_submit(', 'fn dispatch(', 'Existing queue VM owner')!
	require(submit.contains('vm := f.find_owned_vm(vm_id)') && !submit.contains('f.find_vm(vm_id)'), 'Existing queues submit through their physical owner')!
	registry := section(file, 'fn reap_open_detached_g13_queues()', 'pub fn (mut f GpuFile) ioctl_queue_destroy(', 'Open detached VM retries')!
	require_order(registry, ['file_map_lock.acquire()', 'owned.lock.acquire()', 'owned.reap_detached_g13_queues_locked()',
		'owned.reap_detached_vms_locked()', 'owned.lock.release()', 'file_map_lock.release()'], 'Registry and file locks pin physical VM retries after queue retirement')!
}

fn check_vm_detach_reference(file string, mmu string) ! {
	drop := section(file, 'impl Drop for Vm {', '/// Sync object from userspace.', 'Asahi VM namespace owner drop')!
	require_order(drop, ['self.vm.close_idle_reclaim()', 'let left_range =', 'let right_range =',
		'.unmap_range(None, left_range.start, left_range.range())',
		'.unmap_range(None, right_range.start, right_range.range())', 'self.vm.bo_deferred_cleanup()'], 'Asahi VM owner removal tears down both user binding ranges')!
	destroy := section(file, 'pub(crate) fn vm_destroy(', '/// IOCTL: gem_create:', 'Asahi VM name removal')!
	require_order(destroy, ['vms().remove(data.vm_id as usize)', 'if vm.is_none()', 'Err(ENOENT)', 'drop(vm)', 'Ok(0)'], 'Asahi removes names independently of queue ownership')!
	queue := section(file, 'pub(crate) fn queue_create(', '/// IOCTL: queue_destroy:', 'Asahi queue VM owners')!
	require_order(queue, ['guard.get(data.vm_id.try_into()?).ok_or(ENOENT)?', 'let vm = file_vm.vm.clone()',
		'let ualloc = file_vm.ualloc.clone()', 'let ualloc_priv = file_vm.ualloc_priv.clone()', 'reg_data.gpu.new_queue('], 'Asahi queues retain VM and driver allocators independently of VM names')!
	unmap := section(mmu, 'pub(crate) fn unmap_range', 'fn unmap_prepared_cleanup(', 'Asahi mapping removal')!
	require_order(unmap, ['if self.defer_unmap(iova, size)?', 'return Ok(())', 'self.unmap_range_commit(dev, iova, size, true)'], 'Asahi can defer user removal or commit through GPUVM guards')!
}
