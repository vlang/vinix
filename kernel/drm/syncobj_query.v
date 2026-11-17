// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import drm.ioctl
import drm.syncobj
import usercopy

fn ioctl_syncobj_query(handle voidptr, data voidptr) int {
	if handle == unsafe { nil } || data == unsafe { nil } { return -14 }
	request := unsafe { &ioctl.DrmSyncobjTimelineArray(data) }
	if request.flags & ~ioctl.drm_syncobj_query_last_submitted != 0
		|| request.count_handles == 0 { return -22 }
	count := request.count_handles
	points := request.points
	last_submitted := request.flags & ioctl.drm_syncobj_query_last_submitted != 0
	mut handles := [64]u32{}
	mut objects := unsafe { [64]voidptr{} }
	mut buffer := SyncobjWaitBuffer{ handles: unsafe { &handles[0] }, objects: unsafe { &objects[0] } }
	if count > 64 { buffer = new_syncobj_handle_buffer(count) or { return -12 } }
	defer { buffer.free_owned() }
	if !usercopy.copy_from_user(buffer.handles, request.handles, u64(count) * sizeof(u32)) { return -14 }
	// Snapshot every object identity before any output. Fence heads are sampled
	// per entry, so concurrent publication can affect a later repeated handle,
	// as in Linux. Retained metadata survives namespace removal and reuse.
	for index := u32(0); index < count; index++ {
		object := syncobj.lookup(u64(handle), unsafe { buffer.handles[index] }) or { return -2 }
		unsafe { buffer.objects[index] = voidptr(object) }
	}
	for index := u32(0); index < count; index++ {
		point := syncobj.query_timeline_point(unsafe { &syncobj.SyncObj(buffer.objects[index]) }, last_submitted)
		offset := u64(index) * sizeof(u64)
		// Keep partial-output order: a later bad address preserves the prefix.
		if offset > ~points || !usercopy.copy_to_user(points + offset, unsafe { &point }, sizeof(point)) { return -14 }
	}
	return 0
}
