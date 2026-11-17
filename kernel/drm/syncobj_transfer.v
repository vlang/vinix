// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import drm.ioctl
import drm.syncobj

fn ioctl_syncobj_transfer(handle voidptr, data voidptr) int {
	if handle == unsafe { nil } || data == unsafe { nil } { return -14 }
	request := unsafe { &ioctl.DrmSyncobjTransfer(data) }
	if request.pad != 0 { return -22 }
	destination := syncobj.lookup_referenced(u64(handle), request.dst_handle) or { return -2 }
	defer { syncobj.release_syncobj(destination) }
	source := find_syncobj_fence(u64(handle), request.src_handle, request.src_point, request.flags)
	if source.code != 0 { return source.code }
	if request.dst_point != 0 {
		merged := syncobj.unwrap_merge(source.fence) or { return -12 }
		defer { syncobj.release_merge_reservation(merged) }
		chain := syncobj.reserve_chain() or { return -12 }
		defer { syncobj.release_chain_reservation(chain) }
		if !syncobj.add_chain_point(destination, chain, merged, request.dst_point) { return -22 }
		return 0
	}
	syncobj.replace_fence(destination, source.fence)
	return 0
}
