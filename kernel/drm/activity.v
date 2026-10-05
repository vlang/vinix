// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

import drm.ioctl
import katomic
import lib

__global gpu_submissions u64

// Count accepted command submissions, not hardware busy time. The Asahi and
// VirtIO drivers expose submission completion but no utilization/power sensor.
fn account_activity(device &DrmDevice, command u32) {
	if device.driver == unsafe { nil } { return }
	if (device.driver.name == 'asahi' && command == ioctl.drm_asahi_submit)
		|| (device.driver.name == 'virtio_gpu' && command == ioctl.drm_virtgpu_execbuffer) {
		katomic.inc(mut &gpu_submissions)
	}
}

pub fn activity_text() string {
	mut text := lib.new_text(256)
	drm_devices_lock.acquire()
	text.add('devices: ')
	text.add_unsigned(u64(next_dev_id))
	text.add('\ndrivers:')
	for index in 0 .. int(next_dev_id) {
		device := registered_devices[index]
		if device != unsafe { nil } && device.driver != unsafe { nil } {
			text.add(' ')
			text.add(device.driver.name)
		}
	}
	drm_devices_lock.release()
	text.add('\nsubmissions: ')
	text.add_unsigned(katomic.load(&gpu_submissions))
	text.add('\nbusy_time_available: 0\npower_available: 0\n')
	return lib.finish_text(text)
}
