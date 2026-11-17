module file

import drm
import drm.asahi
import drm.gem
import drm.ioctl

// Backing constructors are injected in this transport fixture. The real
// mapping, queue, close and timestamp handlers run in the surrounding suite.
pub fn new_gpu_file(_dev &drm.DrmDevice, _owner u64) ?&GpuFile {
	assert file_map_lock.is_held(), 'registry must serialize first-file construction'
	return none
}

pub fn (mut f GpuFile) ioctl_vm_create(data &ioctl.DrmAsahiVmCreate) int {
	assert data.extensions == 0 && data.pad == 0
	mut request := unsafe { data }
	request.vm_id = 55
	return 0
}

pub fn (mut f GpuFile) ioctl_gem_mmap_offset(data &ioctl.DrmAsahiGemMmapOffset) int {
	assert data.extensions == 0
	if data.flags != 0 { return -22 }
	if data.handle != 91 { return -2 }
	mut request := unsafe { data }
	request.offset = 0xabc000
	return 0
}

fn (mut f GpuFile) import_object(_object &gem.GemObject) ?u32 { return none }

pub fn (mut f GpuFile) ioctl_submit(_data &ioctl.DrmAsahiSubmit) int { return -95 }

pub fn (mut f GpuFile) ioctl_modern_submit(data &asahi.Submit) int {
	assert data.pad == 0 && data.flags == 0
	return -95 // Actual packet-to-scheduler execution is in the async fixture.
}
