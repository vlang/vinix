// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_timestamp_bind_local(file string) ! {
	query := section(file, 'pub fn (mut f GpuFile) ioctl_gem_bind_object(', 'pub fn (mut f GpuFile) ioctl_queue_create(', 'Timestamp-object request validation')!
	bind := section(query, 'ioctl.asahi_bind_object_op_bind {', 'ioctl.asahi_bind_object_op_unbind {', 'Timestamp BIND')!
	require_order(bind, ['request.flags != ioctl.asahi_bind_object_usage_timestamps',
		'request.offset & pgtable.uat_pg_mask != 0', 'request.range & pgtable.uat_pg_mask != 0',
		'request.range > ~request.offset', 'return -22', 'f.get_object_ref(request.handle) or { return -2 }',
		'if obj.vm_private_identity != 0 { gem.unref(obj); return -22 }', 'if request.range == 0 || request.offset > obj.size',
		'gem.unref(obj)', 'gpu.get_global_manager()', 'map_code, va := gpu_manager.map_g13_timestamp_buffer(',
		'if map_code != 0', 'gem.unref(obj)', 'return map_code',
		'f.timestamp_objects << TimestampObject{', 'request.object_handle = id'],
		'Timestamp BIND checks overflow before BO lookup, empty ranges after it and publishes only its output handle')!
	require(!bind.contains('request.object_handle !=') && !bind.contains('request.object_handle =='),
		'BIND object_handle is output-only')!
	unbind := query.all_after('ioctl.asahi_bind_object_op_unbind {')
	require_order(unbind, ['request.flags != 0 || request.handle != 0 || request.offset != 0',
		'request.range != 0', 'return -22', 'f.lock.acquire()', 'object.id == request.object_handle',
		'if found_index < 0', 'f.lock.release()', 'return -2',
		'manager := gpu.get_global_manager() or { f.lock.release(); return -19 }',
		'f.timestamp_objects.delete(found_index)', 'f.lock.release()',
		'gpu_manager.unmap_g13_timestamp_buffer(found.va, found.size)', 'gem.unref(found.obj)'],
		'Timestamp UNBIND resolves missing names before manager lookup and keeps ownership installed on missing-manager failure')!
	require(!unbind.contains('request.object_handle == 0'), 'Zero is a missing timestamp name, not a malformed request')!
}

fn check_timestamp_bind_reference(file string, gpu string, gem string, mmu string) ! {
	bind := section(file, 'pub(crate) fn do_gem_bind_object(', 'pub(crate) fn do_gem_unbind_object(', 'Packaged timestamp BIND')!
	require_order(bind, ['(data.range | data.offset) as usize & mmu::UAT_PGMSK != 0',
		'data.flags != uapi::drm_asahi_bind_object_flags_DRM_ASAHI_BIND_OBJECT_USAGE_TIMESTAMPS',
		'.checked_add(data.range)', '.ok_or(EINVAL)?', 'gem::Object::lookup_handle(file, data.handle)?',
		'reg_data.gpu.map_timestamp_buffer(bo, offset..end_offset)?', 'data.object_handle = handle as u32'],
		'Packaged BIND validates the sum before lookup and writes object_handle only on success')!
	require(!bind.contains('data.object_handle !=') && !bind.contains('data.object_handle =='), 'Packaged BIND ignores the initial output handle')!
	unbind := section(file, 'pub(crate) fn do_gem_unbind_object(', '/// IOCTL: queue_create:', 'Packaged timestamp UNBIND')!
	require_order(unbind, ['data.range != 0 || data.offset != 0', 'data.flags != 0', 'data.handle != 0',
		'objects().remove(data.object_handle as usize)', 'if object.is_none()', 'Err(ENOENT)'], 'Packaged UNBIND resolves all object names, including zero')!
	require(!unbind.contains('data.object_handle == 0'), 'Packaged UNBIND has no special zero-name rejection')!
	mapper := section(gpu, '    fn map_timestamp_buffer(\n        &self,\n        mut bo: gem::ObjectRef,', '\n}\n', 'Packaged timestamp mapper')!
	require(mapper.contains('bo.map_range_into_range('), 'Packaged timestamp mapping follows BO lookup')!
	object := section(gem, 'pub(crate) fn map_range_into_range(', '/// Maps an object into a given `Vm` at a specific address.', 'Packaged timestamp BO bounds')!
	require_order(object, ['if obj_range.end > self.gem.size()', 'return Err(EINVAL)', 'validate_vm_binding(', 'vm.map_in_range('], 'Packaged timestamp BO/private validation')!
	map_range := section(mmu, 'fn map_in_range_with_mode(', '/// Map a GEM object into this Vm at a specific address.', 'Packaged mapping admission')!
	require(map_range.contains('if size == 0 || object_range.end > gem.size()'), 'Packaged empty ranges fail in mapping, after BO lookup')!
	require_order(map_range, ['inner.mm.insert_node_in_range(', 'Err(error) =>', 'drop(vm_exec);', 'return Err(error);',
		'let ret = inner.map_node(&node, prot);', 'ret?', 'Ok(KernelMapping(ManuallyDrop::new(node)))'],
		'Packaged timestamp aperture propagates reservation errors before publishing the mapping owner')!
}
