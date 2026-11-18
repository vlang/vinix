module file

import drm.asahi
import drm.gem
import drm.ioctl

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
