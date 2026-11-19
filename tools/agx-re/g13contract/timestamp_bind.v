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
	require_order(registration, ['memory.malloc_packed_fallible(sizeof(DrmDevice))',
		'if storage == unsafe { nil }', 'errno.set(errno.enomem)', 'return none',
		'*dev = DrmDevice{', 'driver_data: driver_data',
		'registered: false', 'if !published { discard_unpublished_device(dev) }',
		'dev.node = create_device_node(dev, false)?', 'dev.render_node = create_device_node(dev, true)?',
		'publish_device_nodes(dev)?', 'published = true',
		'registered_devices[id] = dev', 'katomic.store(mut dev.registered, true)'],
		'Publish device readiness after installing its context, nodes and registry entry')!
	discard := section(drm, 'fn discard_unpublished_device(', '// Install driver-private context', 'DRM registration rollback')!
	require_order(discard, ['for node in [dev.node, dev.render_node]!', 'if node == unsafe { nil }',
		'memory.free(voidptr(node.box))', 'memory.free(voidptr(node))', 'memory.free(voidptr(dev))'],
		'Release only the initialized registration records on failure')!
	unregister := section(drm, 'pub fn unregister_device(', 'fn copy_version_field(', 'DRM unregistration')!
	require_order(unregister, ['if !unregister_device_nodes(dev) { return }', 'remove_drm_sysfs(mut device)',
		'fn unregister_device_nodes(', 'drm_devices_lock.acquire()', 'registered_devices[dev.dev_id] != dev { return false }',
		'katomic.store(mut d.registered, false)', 'remove_device_nodes(dev)',
		'registered_devices[dev.dev_id] = unsafe { nil }'],
		'Remove the registered owner and its names before allowing the slot to be reused, and its sysfs entries after, outside the lock')!
	open := section(drm, 'fn (mut this DrmNode) open(', 'fn (mut this DrmNode) mapping_attributes(', 'DRM node open')!
	require_order(open, ['!this.dev.is_registered()', 'errno.set(errno.enodev)', 'return none', 'return this.box'],
		'DRM opens check device readiness and reuse the node resource')!
	owned := section(drm, 'pub fn register_owned_driver(', 'fn discard_unpublished_device(', 'Owned DRM descriptor')!
	require_order(owned, ['return register_driver_with_data(driver, driver_data) or {',
		'driver.ioctls.free()', 'free(driver)', 'return none'],
		'Failed registration releases its owned ioctl table and descriptor')!
	definition := section(drm, 'pub fn register_driver_definition(', '// Consume a heap driver descriptor', 'Driver definition storage')!
	require_order(definition, ['memory.malloc_packed_fallible(sizeof(DrmDriver))',
		'if storage == unsafe { nil }', 'definition.ioctls.free()', 'errno.set(errno.enomem)', 'return none',
		'*driver = definition', 'return register_owned_driver(driver, driver_data)'],
		'Driver definition storage fails before publication and releases any owned ioctl table')!
	require_order(driver, ['mgr.init(', 'drm.register_driver_definition(agx_drm_driver, voidptr(mgr))'],
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
