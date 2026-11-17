// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import drm.ioctl
import drm.syncobj
import usercopy

fn sync_file_deadline_ioctl(fence &syncobj.DmaFence, address u64) int {
	mut request := ioctl.SyncSetDeadline{}
	if !usercopy.copy_from_user(unsafe { &request }, address, sizeof(ioctl.SyncSetDeadline)) { return -14 }
	if request.pad != 0 { return -22 }
	syncobj.set_deadline(fence, i64(request.deadline_ns))
	return 0
}
