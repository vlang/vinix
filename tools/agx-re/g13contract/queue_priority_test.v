module g13contract

import g13layout
import os

fn test_priority_conversion_and_retained_failure_ownership_reject_drift() {
	repo := g13layout.repo_root()
	file := os.read_file(repo + '/kernel/gpu/agx/file/file.v')!
	ioctl := os.read_file(repo + '/kernel/drm/ioctl/ioctl.v')!
	gpu := os.read_file(repo + '/kernel/gpu/agx/gpu/g13.v')!
	check_queue_priority_local(file, ioctl, gpu)!
	for token in ['ioctl.asahi_priority_realtime - request.priority',
		'if manager.hw_config.gpu_gen == .g13 && request.priority > ioctl.asahi_priority_medium { return -22 }',
		'if ownership.vm_id == request.vm_id { return -16 }',
		'if ownership.queue_id == candidate {',
		'f.g13_queues << G13QueueOwnership{ queue_id: id, vm_id: request.vm_id, resources: retained }',
		'unsafe { free(queue) }'] {
		if _ := check_queue_priority_local(file.replace(token, ''), ioctl, gpu) { assert false, token }
	}
	if _ := check_queue_priority_local(file.replace('vm := f.find_vm(request.vm_id)',
		'f.lock.release()\nvm := f.find_vm(request.vm_id)'), ioctl, gpu) { assert false }
	if _ := check_queue_priority_local(file, ioctl.replace('asahi_priority_medium = u32(1)',
		'asahi_priority_medium = u32(2)'), gpu) { assert false }
	for token in ['voidptr(resources.vm) == voidptr(vm)', 'resources.quarantined && !resources.released'] {
		if _ := check_queue_priority_local(file, ioctl, gpu.replace(token, 'true')) { assert false }
	}
}

fn test_packaged_priority_oracle_rejects_policy_and_conversion_drift() {
	header := 'DRM_ASAHI_PRIORITY_LOW = 0,\nDRM_ASAHI_PRIORITY_MEDIUM = 1,\nDRM_ASAHI_PRIORITY_HIGH = 2,\nDRM_ASAHI_PRIORITY_REALTIME = 3,\n'
	file := '    pub(crate) fn queue_create(\n' +
		'if data.priority == uapi::drm_asahi_priority_DRM_ASAHI_PRIORITY_REALTIME { return Err(EINVAL) }\n' +
		'if data.priority == uapi::drm_asahi_priority_DRM_ASAHI_PRIORITY_HIGH && !reg_data.gpu.as_any().is::<crate::g17::Gpu>() { return Err(EINVAL) }\n' +
		'let vm = file_vm.vm.clone(); reg_data.gpu.new_queue(uapi::drm_asahi_priority_DRM_ASAHI_PRIORITY_REALTIME - data.priority)\n' +
		'    /// IOCTL: queue_destroy:'
	check_queue_priority_reference(header, file)!
	for token in ['&& !reg_data.gpu.as_any().is::<crate::g17::Gpu>()',
		'uapi::drm_asahi_priority_DRM_ASAHI_PRIORITY_REALTIME - data.priority'] {
		if _ := check_queue_priority_reference(header, file.replace(token, '')) { assert false }
	}
	if _ := check_queue_priority_reference(header.replace('MEDIUM = 1', 'MEDIUM = 2'), file) { assert false }
}
