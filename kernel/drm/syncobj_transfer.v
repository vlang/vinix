// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import drm.ioctl
import drm.syncobj

fn ioctl_syncobj_transfer(handle voidptr, data voidptr) int {
	if handle == unsafe { nil } || data == unsafe { nil } { return -14 }
	request := unsafe { &ioctl.DrmSyncobjTransfer(data) }
	if request.pad != 0 { return -22 }
	// A timeline destination requires dma_fence_unwrap_merge and array fences.
	// Keep this unsupported until those lifetimes and semantics are in place.
	if request.dst_point != 0 { return -95 }
	destination := syncobj.lookup(u64(handle), request.dst_handle) or { return -2 }
	source := find_syncobj_fence(u64(handle), request.src_handle, request.src_point, request.flags)
	if source.code != 0 { return source.code }
	syncobj.replace_fence(destination, source.fence)
	return 0
}
