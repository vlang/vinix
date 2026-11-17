// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import drm.ioctl
import drm.syncobj
import memory
import usercopy
import proc
import katomic
import sched

fn ioctl_syncobj_timeline_wait(handle voidptr, data voidptr) int {
	if handle == unsafe { nil } || data == unsafe { nil } { return -14 }
	mut request := unsafe { &ioctl.DrmSyncobjTimelineWait(data) }
	known := ioctl.drm_syncobj_wait_all | ioctl.drm_syncobj_wait_for_submit
		| ioctl.drm_syncobj_wait_available | ioctl.drm_syncobj_wait_deadline
	if request.flags & ~known != 0 { return -22 }
	count := request.count_handles
	if count == 0 { return 0 }
	flags := request.flags
	mut handles := [64]u32{}
	mut objects := unsafe { [64]voidptr{} }
	mut buffer := SyncobjWaitBuffer{ handles: unsafe { &handles[0] }, objects: unsafe { &objects[0] } }
	if count > 64 { buffer = new_syncobj_handle_buffer(count) or { return -12 } }
	defer { buffer.free_owned() }
	if !usercopy.copy_from_user(buffer.handles, request.handles, u64(count) * sizeof(u32)) { return -14 }
	for index := u32(0); index < count; index++ {
		object := syncobj.lookup(u64(handle), unsafe { buffer.handles[index] }) or { return -2 }
		unsafe { buffer.objects[index] = voidptr(object) }
	}
	points_storage := memory.malloc_packed_fallible(u64(count) * sizeof(u64)) @[freed]
	if points_storage == unsafe { nil } { return -12 }
	defer { memory.free(points_storage) }
	if request.points == 0 { unsafe { C.memset(points_storage, 0, u64(count) * sizeof(u64)) } }
	else if !usercopy.copy_from_user(points_storage, request.points, u64(count) * sizeof(u64)) { return -14 }
	points := unsafe { &u64(points_storage) }
	captures_storage := memory.malloc_packed_fallible(u64(count) * sizeof(syncobj.TimelineCapture)) @[freed]
	if captures_storage == unsafe { nil } { return -12 }
	defer { memory.free(captures_storage) }
	unsafe { C.memset(captures_storage, 0, u64(count) * sizeof(syncobj.TimelineCapture)) }
	captures := unsafe { &syncobj.TimelineCapture(captures_storage) }
	defer {
		mut remaining := count
		for remaining > 0 { remaining--; syncobj.release_timeline_capture(unsafe { &captures[remaining] }) }
	}
	available := flags & ioctl.drm_syncobj_wait_available != 0
	allow_future := flags & (ioctl.drm_syncobj_wait_for_submit | ioctl.drm_syncobj_wait_available) != 0
	wait_all := flags & ioctl.drm_syncobj_wait_all != 0
	mut ready_count := u32(0)
	mut first := ~u32(0)
	for index := u32(0); index < count; index++ {
		if !syncobj.prepare_timeline_capture(unsafe { &syncobj.SyncObj(buffer.objects[index]) },
			unsafe { &captures[index] }, unsafe { points[index] }, allow_future) { return -22 }
		if fence := syncobj.captured_timeline_fence(unsafe { &captures[index] }) {
			if available || syncobj.is_signaled(fence) {
				if ready_count == 0 { first = index }
				ready_count++
			}
		}
	}
	if ready_count == count || (!wait_all && ready_count != 0) { request.first_signaled = first; return 0 }
	if allow_future {
		for index := u32(0); index < count; index++ { syncobj.arm_timeline_capture(unsafe { &captures[index] }) }
	}
	if flags & ioctl.drm_syncobj_wait_deadline != 0 {
		for index := u32(0); index < count; index++ {
			if fence := syncobj.captured_timeline_fence(unsafe { &captures[index] }) {
				syncobj.set_deadline(fence, i64(request.deadline_nsec))
			}
		}
	}
	for {
		ready_count = 0
		for index := u32(0); index < count; index++ {
			if fence := syncobj.captured_timeline_fence(unsafe { &captures[index] }) {
				if available || syncobj.is_signaled(fence) {
					if !wait_all { request.first_signaled = index; return 0 }
					ready_count++
				}
			}
		}
		if ready_count == count { request.first_signaled = first; return 0 }
		if request.timeout_nsec <= 0 || u64(request.timeout_nsec) <= syncobj.now_ns() { return -62 }
		waiting_thread := proc.current_thread()
		if katomic.load(&waiting_thread.must_exit) || proc.pending_signals(waiting_thread) & ~waiting_thread.masked_signals != 0 { return -proc.interrupted_errno }
		sched.reschedule()
	}
	return -62
}
