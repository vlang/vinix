module file

import drm.asahi
import drm.ioctl

pub fn (mut f GpuFile) ioctl_submit(_data &ioctl.DrmAsahiSubmit) int { return -95 }

pub fn (mut f GpuFile) ioctl_modern_submit(data &asahi.Submit) int {
	assert data.pad == 0 && data.flags == 0
	return -95 // Actual packet-to-scheduler execution is in the async fixture.
}
