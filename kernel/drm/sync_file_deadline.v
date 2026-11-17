// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import drm.ioctl
import usercopy

fn sync_file_deadline_ioctl(address u64) int {
	mut request := ioctl.SyncSetDeadline{}
	if !usercopy.copy_from_user(unsafe { &request }, address, sizeof(ioctl.SyncSetDeadline)) { return -14 }
	if request.pad != 0 { return -22 }
	// Current native leaf fences have no deadline callback, like Asahi's
	// underlying JobFence and Linux's private stub. Accept the hint without
	// changing completion, readiness or scheduling. Chains contain only these
	// leaves, so propagating the hint has the same effect. Future scheduler
	// wrappers or leaves with callbacks must supply that propagation behavior.
	return 0
}
