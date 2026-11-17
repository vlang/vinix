// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_queue_priority_local(file string, ioctl string, gpu string) ! {
	for index, name in ['low', 'medium', 'high', 'realtime'] {
		exact_line(ioctl, 'pub const asahi_priority_${name} = u32(${index})', 'Vinix queue priority numbering')!
	}
	create := section(file, 'pub fn (mut f GpuFile) ioctl_queue_create(',
		'pub fn (mut f GpuFile) ioctl_queue_destroy(', 'Vinix G13 queue admission')!
	require_order(create, ['request.priority > ioctl.asahi_priority_realtime',
		'if manager.hw_config.gpu_gen == .g13 && request.priority > ioctl.asahi_priority_medium { return -22 }',
		'firmware_priority := if manager.hw_config.gpu_gen == .g13 {',
		'ioctl.asahi_priority_realtime - request.priority', '} else { request.priority }',
		'f.lock.acquire()', 'defer { f.lock.release() }', 'vm := f.find_vm(request.vm_id)',
		'id := f.allocate_queue_id_locked()',
		'workqueue.new_workqueue(id, request.vm_id, firmware_priority, request.queue_caps)',
		'gpu_manager.create_g13_queue_resources(id, channel_mask, firmware_priority, vm)',
		'gpu_manager.retained_g13_queue_resources(id, vm)',
		'f.g13_queues << G13QueueOwnership{ queue_id: id, vm_id: request.vm_id, resources: retained }',
		'queue.destroy()', 'workqueue.free_workqueue(queue)', 'return -12',
		'f.queues << wq', 'request.queue_id = id'], 'Vinix G13 priority and VM borrow lifetime')!
	require(create.count('f.lock.acquire()') == 1 && create.count('f.lock.release()') == 1,
		'Queue creation must hold one file lock through VM borrow and publication')!
	require(create.count('workqueue.free_workqueue(queue)') == 2, 'Both unpublished logical queue failure paths must free metadata')!
	allocator := section(file, 'fn (mut f GpuFile) allocate_queue_id_locked(',
		'fn (mut f GpuFile) allocate_timestamp_id_locked(', 'Vinix retained queue ID reservation')!
	require_order(allocator, ['for ownership in f.g13_queues {',
		'if ownership.queue_id == candidate {', 'used = true', 'if !used {'], 'Vinix retained queue ID reservation')!
	destroy := section(file, 'fn (mut f GpuFile) reap_detached_vms_locked()',
		'pub fn (mut f GpuFile) ioctl_gem_create(', 'Vinix failed queue VM pin')!
	require_order(destroy, ['for ownership in f.g13_queues {',
		'if ownership.vm_id == vm_id { retained = true; break }', 'if retained { continue }',
		'manager.destroy_context(vm)'], 'Vinix failed queue VM pin')!
	lookup := section(gpu, 'pub fn (mut mgr GpuManager) retained_g13_queue_resources(',
		'pub fn (mut mgr GpuManager) release_g13_queue_resources(', 'Vinix retained failed queue lookup')!
	require_order(lookup, ['mgr.lock.acquire()', 'defer { mgr.lock.release() }', 'for resources in mgr.g13_queues',
		'resources.queue_id == queue_id && voidptr(resources.vm) == voidptr(vm)',
		'&& resources.quarantined && !resources.released', 'return resources'], 'Vinix retained failed queue lookup')!
}

fn check_queue_priority_reference(header string, file string) ! {
	for index, name in ['LOW', 'MEDIUM', 'HIGH', 'REALTIME'] {
		exact_line(header, 'DRM_ASAHI_PRIORITY_${name} = ${index},', 'Asahi queue priority numbering')!
	}
	create := section(file, '    pub(crate) fn queue_create(',
		'    /// IOCTL: queue_destroy:', 'Asahi G13 queue priority policy')!
	require_order(create, ['if data.priority == uapi::drm_asahi_priority_DRM_ASAHI_PRIORITY_REALTIME',
		'return Err(EINVAL)', 'if data.priority == uapi::drm_asahi_priority_DRM_ASAHI_PRIORITY_HIGH',
		'&& !reg_data.gpu.as_any().is::<crate::g17::Gpu>()', 'return Err(EINVAL)',
		'let vm = file_vm.vm.clone()', 'reg_data.gpu.new_queue(',
		'uapi::drm_asahi_priority_DRM_ASAHI_PRIORITY_REALTIME - data.priority'], 'Asahi G13 queue priority policy')!
}
