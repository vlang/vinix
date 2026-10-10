// SPDX-License-Identifier: GPL-2.0-or-later
module ans

import apple.ans.anscore
import errno
import resource

fn (mut dev AnsBlock) block_health() ?resource.BlockHealth {
	if dev.partition >= 0 {
		errno.set(errno.enotty)
		return none
	}
	ans_lock.acquire()
	defer { ans_lock.release() }
	if !ans_ready {
		errno.set(errno.enodev)
		return none
	}
	mut report := resource.BlockHealth{ protocol: resource.health_nvme, disk_id: dev.stat.rdev }
	result := anscore.health(dev.ns_index, unsafe { &report.identify[0] }, unsafe { &report.data[0] })
	if result != 0 {
		errno.set(errno.eio)
		return none
	}
	report.flags = resource.health_supported | resource.health_enabled |
		resource.health_data_valid | resource.health_status_valid
	if report.data[0] != 0 { report.flags |= resource.health_threshold_exceeded }
	return report
}
