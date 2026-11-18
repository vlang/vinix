// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import drm.ioctl
import drm.syncobj
import errno
import file
import usercopy

// The ioctl holds the first open description. Keep the second fd referenced
// until the two roots have been flattened and the new fd is installed.
fn sync_file_merge_ioctl(first &syncobj.DmaFence, address u64) int {
	mut reservation := file.FdReservation{}
	number := file.reserve_fd(unsafe { nil }, unsafe { &reservation }) or { return -int(errno.get()) }
	defer { file.cancel_fd_reservation(unsafe { &reservation }) }
	mut request := ioctl.SyncMergeData{}
	if !usercopy.copy_from_user(unsafe { &request }, address, sizeof(request)) { return -14 }
	if request.flags != 0 || request.pad != 0 { return -22 }

	mut other := file.fd_from_fdnum(unsafe { nil }, request.fd2) or { return -2 }
	defer { other.unref() }
	second := sync_file_fence(other) or { return -2 }
	request.name[31] = 0
	merged := syncobj.merge_sync_file_fences(first, second) or { return -12 }
	mut fd := new_sync_file_fd(merged.fence, merged.owned, unsafe { &request.name[0] }) or { return -12 }
	request.fence = i32(number)
	return publish_sync_file_fd(mut fd, unsafe { &reservation }, address, unsafe { &request }, sizeof(request))
}

// Copyout runs while only the caller owns the newly constructed fd. Install
// transfers the reference to the descriptor table, and every failure drops it.
fn publish_sync_file_fd(mut fd file.FD, reservation &file.FdReservation, address u64, input voidptr, size u64) int {
	if !usercopy.copy_to_user(address, input, size) {
		fd.unref()
		return -14
	}
	file.fdnum_install_reserved_fd(reservation, fd) or {
		code := errno.get()
		fd.unref()
		return -int(code)
	}
	return 0
}
