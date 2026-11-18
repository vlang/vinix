// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_timestamp_bind_local(file string) ! {
	names := section(file, 'fn (mut f GpuFile) allocate_timestamp_id_locked(', 'fn (f &GpuFile) find_vm(', 'Timestamp name allocation')!
	require_order(names, ['mut candidate := u32(1)', 'for index, object in f.timestamp_objects',
		'if object.id > candidate { return candidate, index }', 'if object.id == candidate && !object.detached',
		'if candidate == ~u32(0) { return 0, index }', 'candidate++', 'return candidate, f.timestamp_objects.len'],
		'Select the first free timestamp name while ignoring retained detached mappings')!
	storage := section(file, 'fn (mut f GpuFile) reserve_timestamp_entry_locked(', 'fn (f &GpuFile) find_vm(', 'Timestamp publication storage')!
	require_order(storage, ['f.timestamp_objects.len < f.timestamp_objects.cap', 'return true',
		'memory.malloc_packed_fallible(u64(capacity) * sizeof(TimestampObject)) @[freed]',
		'if storage == unsafe { nil } { return false }', 'replacement.flags = .noslices',
		'C.memcpy(storage, f.timestamp_objects.data,', 'mut old := f.timestamp_objects',
		'f.timestamp_objects = replacement', 'old.free()'], 'Grow the timestamp table without changing live records on OOM')!
	query := section(file, 'pub fn (mut f GpuFile) ioctl_gem_bind_object(', 'pub fn (mut f GpuFile) ioctl_queue_create(', 'Timestamp-object request validation')!
	bind := section(query, 'ioctl.asahi_bind_object_op_bind {', 'ioctl.asahi_bind_object_op_unbind {', 'Timestamp BIND')!
	require_order(bind, ['request.flags != ioctl.asahi_bind_object_usage_timestamps',
		'request.offset & pgtable.uat_pg_mask != 0', 'request.range & pgtable.uat_pg_mask != 0',
		'request.range > ~request.offset', 'return -22', 'f.get_object_ref(request.handle) or { return -2 }',
		'if obj.vm_private_identity != 0 { gem.unref(obj); return -22 }', 'if request.range == 0 || request.offset > obj.size',
		'gem.unref(obj)', 'mut gpu_manager := unsafe { f.registration_manager }',
		'if gpu_manager == unsafe { nil }', 'gem.unref(obj)', 'return -19',
		'map_code, va := gpu_manager.map_g13_timestamp_buffer(',
		'if map_code != 0', 'gem.unref(obj)', 'return map_code',
		'f.lock.acquire()', 'id, slot := f.allocate_timestamp_id_locked()',
		'mut publish_code := if id == 0 { -16 } else if !f.reserve_timestamp_entry_locked() { -12 } else { 0 }',
		'if publish_code == 0', 'gpu_manager.lock.acquire()', 'if gpu_manager.state == .stopped',
		'publish_code = -19',
		'f.timestamp_objects << object', 'index > slot', 'f.timestamp_objects[index] = f.timestamp_objects[index - 1]',
		'f.timestamp_objects[slot] = object', 'request.object_handle = id', 'gpu_manager.lock.release()',
		'f.lock.release()', 'if publish_code != 0',
		'gpu_manager.unmap_g13_timestamp_buffer(va, request.range)', 'gem.unref(obj)', 'return publish_code'],
		'Timestamp BIND checks overflow before BO lookup, empty ranges after it and publishes only its output handle')!
	require(bind.count('gpu_manager.lock.release()') == 1,
		'Timestamp publication keeps the manager lock through insertion and output assignment')!
	require(!bind.contains('gpu.get_global_manager()') && !bind.contains('f.registration_manager ='),
		'BIND uses the original registration even before a file has a timestamp handle')!
	require(!bind.contains('request.object_handle !=') && !bind.contains('request.object_handle =='),
		'BIND object_handle is output-only')!
	unbind := query.all_after('ioctl.asahi_bind_object_op_unbind {')
	require_order(unbind, ['request.flags != 0 || request.handle != 0 || request.offset != 0',
		'request.range != 0', 'return -22', 'f.lock.acquire()', 'object.id == request.object_handle',
		'if found_index < 0', 'f.lock.release()', 'return -2',
		'if found.references != 0', 'f.timestamp_objects[found_index].detached = true', 'f.lock.release()', 'return 0',
		'manager := f.registration_manager', 'f.timestamp_objects.delete(found_index)', 'f.lock.release()',
		'release_timestamp_object(manager, found)', 'return 0'],
		'Timestamp UNBIND hides the name and the original manager retires it once captures are gone')!
	require(!unbind.contains('gpu.get_global_manager()'), 'UNBIND cannot select a replacement GPU manager')!
	require(!unbind.contains('request.object_handle == 0'), 'Zero is a missing timestamp name, not a malformed request')!
	require(!unbind.contains('return -19'), 'Manager availability does not block name removal')!
}

fn check_timestamp_registration_local(file string, drm string, driver string) ! {
	device := section(drm, 'pub struct DrmDevice {', '// Forward-reference placeholder', 'DRM registration data')!
	require_order(device, ['pub:', 'driver_data voidptr', 'pub mut:'], 'DRM device context is immutable')!
	registration := section(drm, 'pub fn register_driver_with_data(', 'pub fn unregister_device(', 'DRM publication')!
	require_order(registration, ['mut dev := &DrmDevice{', 'driver_data: driver_data',
		'create_device_node(dev,', 'registered_devices[id] = dev'], 'Set the device context before exposing a node')!
	require_order(driver, ['mgr.init(', 'drm.register_driver_with_data(agx_drm_driver, voidptr(mgr))'],
		'AGX registers the initialized manager with its device')!
	constructor := section(file, 'pub fn new_gpu_file(', '// Tear the file down.', 'File registration context')!
	require_order(constructor, ['dev == unsafe { nil }', 'manager := unsafe { &gpu.GpuManager(dev.driver_data) }',
		'manager == unsafe { nil } || manager.uat == unsafe { nil }', 'mut f := &GpuFile{', 'dev: unsafe { dev }',
		'registration_manager: manager', 'return f'],
		'A newly constructed file snapshots the manager of its originating device')!
}

fn check_timestamp_bind_reference(file string, gpu string, gem string, mmu string) ! {
	bind := section(file, 'pub(crate) fn do_gem_bind_object(', 'pub(crate) fn do_gem_unbind_object(', 'Packaged timestamp BIND')!
	require_order(bind, ['(data.range | data.offset) as usize & mmu::UAT_PGMSK != 0',
		'data.flags != uapi::drm_asahi_bind_object_flags_DRM_ASAHI_BIND_OBJECT_USAGE_TIMESTAMPS',
		'.checked_add(data.range)', '.ok_or(EINVAL)?', 'gem::Object::lookup_handle(file, data.handle)?',
		'reg_data.gpu.map_timestamp_buffer(bo, offset..end_offset)?',
		'GFP_KERNEL,', ')?;', 'KBox::new(Object::TimestampBuffer(mapping), GFP_KERNEL)?',
		'.insert_limit(1..=u32::MAX, obj, GFP_KERNEL)', 'let handle = handle? as u64', 'data.object_handle = handle as u32'],
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
