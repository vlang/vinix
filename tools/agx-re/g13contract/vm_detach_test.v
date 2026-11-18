module g13contract

import g13layout

fn test_vm_detach_guards_require_hidden_names_and_retained_physical_owners() {
	file := read(g13layout.repo_root() + '/kernel/gpu/agx/file/file.v')!
	check_vm_detach_local(file)!
	for token in ['ctx.id = owner_id', 'vm.detached = true',
		'vm.vm_id == vm_id', '&& !vm.detached', 'if retained { continue }',
		'if !f.cleanup_closed_mappings_locked(vm) { continue }', 'f.vms.delete(index)',
		'f.vms[insert_at] = ctx', 'owned.reap_detached_vms_locked()',
		'&& !vm.closed_mappings_pending', 'vm.closed_mappings_pending = true',
		'owned.closed_mappings_pending = false', 'if !vm.detached { continue }',
		'!vm.detached && !mapping.retiring', 'ctx := f.find_owned_vm(mapping.vm_id)',
		'vm := f.find_owned_vm(vm_id)'] {
		if _ := check_vm_detach_local(file.replace(token, '')) { assert false, token }
	}
	if _ := check_vm_detach_local(file.replace('vm.detached = true', 'return -16')) { assert false }
}

fn test_vm_detach_reference_requires_namespace_drop_and_independent_queue_owners() {
	file := 'impl Drop for Vm { self.vm.close_idle_reclaim(); let left_range = x; let right_range = y;\n' +
		'.unmap_range(None, left_range.start, left_range.range()) .unmap_range(None, right_range.start, right_range.range()) self.vm.bo_deferred_cleanup(); }\n' +
		'/// Sync object from userspace.\npub(crate) fn vm_destroy( vms().remove(data.vm_id as usize); if vm.is_none() { Err(ENOENT) } else { drop(vm); Ok(0) }\n/// IOCTL: gem_create:\n' +
		'pub(crate) fn queue_create( guard.get(data.vm_id.try_into()?).ok_or(ENOENT)?; let vm = file_vm.vm.clone(); let ualloc = file_vm.ualloc.clone(); let ualloc_priv = file_vm.ualloc_priv.clone(); reg_data.gpu.new_queue(\n/// IOCTL: queue_destroy:'
	mmu := 'pub(crate) fn unmap_range if self.defer_unmap(iova, size)? { return Ok(()); } self.unmap_range_commit(dev, iova, size, true)\nfn unmap_prepared_cleanup('
	check_vm_detach_reference(file, mmu)!
	for token in ['vms().remove(data.vm_id as usize)', 'drop(vm)', 'let vm = file_vm.vm.clone()',
		'.unmap_range(None, right_range.start, right_range.range())'] {
		if _ := check_vm_detach_reference(file.replace(token, ''), mmu) { assert false, token }
	}
	if _ := check_vm_detach_reference(file, mmu.replace('self.unmap_range_commit(dev, iova, size, true)', '')) { assert false }
}
