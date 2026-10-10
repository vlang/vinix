// SPDX-License-Identifier: GPL-2.0-or-later
module ans

import anscore
import errno
import klock
import resource
import stat

fn test_ans_resource_report_uses_controller_scope_and_opened_disk_identity() {
	for warning in [u8(0), 1, 2, 4, 8, 16, 32, 64, 128, 255]! {
		model := anscore.model_setup(0, 0, warning)
		mut disk := AnsBlock{ stat: stat.Stat{ rdev: 91 }, ns_index: 1 }
		mut box := resource.Resource(unsafe { &disk })
		report := resource.block_health(mut box) or {
			assert false
			return
		}
		assert sizeof(report) == 1088 && report.version == 1 && report.protocol == 2
		assert report.disk_id == 91 && report.flags == if warning == 0 { u64(15) } else { u64(31) }
		assert report.identify[511] == u8(511 * 17 + 6) && report.data[0] == warning
		assert report.data[47] == u8(47 * 17 + 2) && report.data[511] == u8(511 * 17 + 2)
		for value in report.reserved {
			assert value == 0
		}
		assert model.commands == 2 && klock.depth == 0
		anscore.model_free(model)
	}
}

fn test_ans_partition_unready_and_failed_queries_return_no_report() {
	model := anscore.model_setup(1, 2, 0)
	defer { anscore.model_free(model) }
	mut disk := AnsBlock{ partition: 0 }
	assert disk.block_health() == none && errno.get() == errno.enotty && model.commands == 0
	disk.partition = -1
	ans_ready = false
	assert disk.block_health() == none && errno.get() == errno.enodev && model.commands == 0
	ans_ready = true
	assert disk.block_health() == none && errno.get() == errno.eio && model.commands == 2
	assert klock.depth == 0
}
