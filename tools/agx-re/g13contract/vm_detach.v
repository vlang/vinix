// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_vm_detach_local(file string) ! {
	visible := section(file, 'fn (f &GpuFile) find_vm(', '// Internal owners survive', 'Visible VM namespace')!
	require_order(visible, ['if vm_id == 0 { return none }', 'for vm in f.vms',
		'vm.vm_id == vm_id', '!vm.detached', 'return unsafe { vm }'], 'Visible names resolve within the file and exclude detached owners')!
	owned := section(file, 'fn (f &GpuFile) find_owned_vm(', 'fn ranges_overlap(', 'Physical VM owner')!
	require_order(owned, ['for vm in f.vms', 'if vm.id == vm_id', 'return unsafe { vm }'], 'Physical lookup remains valid after namespace removal')!
	require(!owned.contains('vm.detached'), 'Physical ownership cannot depend on name visibility')!
	create := section(file, 'pub fn (mut f GpuFile) ioctl_vm_create(', 'pub fn (mut f GpuFile) ioctl_vm_destroy(', 'VM namespace publication')!
	require_order(create, ['mgr := f.file_uat()', 'f.lock.acquire()', 'defer { f.lock.release() }',
		'mut gpu_manager := unsafe { f.registration_manager }', 'gpu_manager.lock.acquire()',
		'defer { gpu_manager.lock.release() }', 'if gpu_manager.state == .stopped || gpu_manager.state == .error { return -19 }', 'vm_id := u32(1)',
		'if vm.detached { continue }', 'if vm.vm_id > vm_id { insert_at = index; break }',
		'for f.find_owned_vm(owner_id) != none', 'if !f.reserve_vm_entry_locked()',
		'm.create_context(', 'ctx.id = owner_id', 'ctx.vm_id = vm_id',
		'if m.handoff_abi != .v12_3 && m.bind_context(ctx) == 0', 'm.destroy_context(ctx)',
		'f.vms << ctx', 'f.vms[insert_at] = ctx', 'request.vm_id = vm_id'], 'VM creation publishes the first available file name under the file lock')!
	require(!file.contains('mmu.uat_num_contexts'), 'Software VM owners must be independent of hardware capacity')!
	destroy := section(file, 'pub fn (mut f GpuFile) ioctl_vm_destroy(', '// Caller holds file.lock. User bindings', 'VM namespace removal')!
	require_order(destroy, ['request.extensions != 0 || request.pad != 0', 'return -22',
		'if request.vm_id == 0 { return -2 }',
		'f.lock.acquire()', 'defer { f.lock.release() }', 'f.find_vm(request.vm_id) or { return -2 }',
		'vm.detached = true', 'f.reap_detached_vms_locked()', 'return 0'], 'Remove validated names before deferred physical retirement')!
	require(!destroy.contains('return -16') && !destroy.contains('destroy_context('), 'Busy owners must not prevent namespace removal or be destroyed directly')!
	reap := section(file, 'fn (mut f GpuFile) reap_detached_vms_locked()', 'pub fn (mut f GpuFile) ioctl_gem_create(', 'Detached physical VM retirement')!
	require_order(reap, ['mut uat := unsafe { f.file_uat() }', 'if uat == unsafe { nil } { return }', 'index := f.vms.len - 1',
		'vm_id := vm.id', 'if !vm.detached || katomic.load(&vm.inflight) != 0',
		'if !f.cleanup_closed_mappings_locked(vm) { continue }',
		'for queue in f.queues', 'queue.vm_id == vm_id', 'for ownership in f.g13_queues',
		'ownership.vm_id == vm_id', 'if retained { continue }', 'uat.destroy_context(vm)',
		'f.vms.delete(index)'], 'Retire mappings then exclude every job/queue owner before physical context removal')!
	for token in ['memory.', 'free(', 'f.vms <<'] { require(!reap.contains(token), 'VM reaper must not allocate, free metadata or grow its ownership array')! }
	cleanup := section(file, 'fn (mut f GpuFile) cleanup_closed_mappings_locked(', 'fn (mut f GpuFile) close_object_handle(', 'Detached user bindings')!
	require_order(cleanup, ['katomic.load(&vm.inflight) != 0',
		'!vm.detached && !mapping.retiring && !mapping.handle_closed', 'f.retire_mapping_locked(index)'], 'Every idle detached or closed-handle binding retires independently of current handle names')!
	close := section(file, 'fn (mut f GpuFile) close_object_handle(', 'fn (mut f GpuFile) reserve_mapping_slots_locked(', 'Close binding selection')!
	require_order(close, ['f.lock.acquire()', 'f.objects.remove(handle)', 'for mut mapping in f.mappings',
		'if voidptr(mapping.obj) == voidptr(obj) { mapping.handle_closed = true }',
		'f.cleanup_closed_mappings_locked(vm)', 'f.lock.release()', 'gem.unref(obj)'], 'GEM_CLOSE records the old bindings before dropping its handle reference')!
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

fn check_file_close_registration_local(file string, closing string) ! {
	uat := section(file, 'fn (f &GpuFile) file_uat(', 'fn asahi_variant(', 'File UAT ownership')!
	require_order(uat, ['manager := f.registration_manager', 'if manager == unsafe { nil }',
		'manager.hw_config.gpu_gen != .g13', 'return manager.uat'],
		'G13 file operations retain the original UAT through replacement')!
	retire := section(closing, 'fn retire_closing_file(', 'fn retain_closing_file(', 'Closing registration')!
	require_order(retire, ['file.registration_manager', 'gpu_manager.queue_file_retirement(',
		'retain_closing_file(file, true)', 'reap_closed_files()'],
		'Once the original worker has stopped, register deferred ownership before retrying synchronously')!
	reap := closing.all_after('pub fn reap_closed_files()')
	require_order(reap, ['if closing_reaper_active', 'closing_reaper_requested = true',
		'if closing_head == unsafe { nil }', 'closing_reaper_active = true', 'count := closing_count',
		'closing_reaper_requested = false', 'if file.close()', 'retain_closing_file(file, false)',
		'if !closing_reaper_requested', 'closing_reaper_active = false'],
		'An overlapping close poll transfers a retry without spinning on pinned files')!
	require(!file.contains('gpu.get_global_manager()') && !closing.contains('gpu.get_global_manager()'),
		'File operations and deferred retirement use their own DRM registration')!
}
