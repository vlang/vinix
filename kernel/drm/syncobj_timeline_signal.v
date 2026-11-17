// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import drm.ioctl
import drm.syncobj
import memory
import usercopy

fn ioctl_syncobj_timeline_signal(handle voidptr, data voidptr) int {
	if handle == unsafe { nil } || data == unsafe { nil } { return -14 }
	request := unsafe { &ioctl.DrmSyncobjTimelineArray(data) }
	if request.flags != 0 || request.count_handles == 0 { return -22 }
	count := request.count_handles
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
	// Linux resolves every object before reading points, and treats a null
	// points pointer as an array of zeroes. Snapshot points before publication.
	bytes := u64(count) * sizeof(u64)
	points_storage := memory.malloc_packed_fallible(bytes) @[freed]
	if points_storage == unsafe { nil } { return -12 }
	defer { memory.free(points_storage) }
	if request.points == 0 { unsafe { C.memset(points_storage, 0, bytes) } }
	else if !usercopy.copy_from_user(points_storage, request.points, bytes) { return -14 }
	points := unsafe { &u64(points_storage) }
	chains_storage := memory.malloc_packed_fallible(u64(count) * sizeof(voidptr)) @[freed]
	if chains_storage == unsafe { nil } { return -12 }
	defer { memory.free(chains_storage) }
	unsafe { C.memset(chains_storage, 0, u64(count) * sizeof(voidptr)) }
	chains := unsafe { &&syncobj.DmaFence(chains_storage) }
	defer {
		for index := u32(0); index < count; index++ {
			syncobj.release_chain_reservation(unsafe { chains[index] })
		}
	}
	for index := u32(0); index < count; index++ {
		chain := syncobj.reserve_chain() or { return -12 }
		unsafe { chains[index] = chain }
	}
	// No allocation remains after the first point is published. Published
	// metadata is retained; the deferred cleanup frees only private reservations.
	payload := syncobj.shared_timeline_stub()
	for index := u32(0); index < count; index++ {
		if !syncobj.add_chain_point(unsafe { &syncobj.SyncObj(buffer.objects[index]) },
			unsafe { chains[index] }, payload, unsafe { points[index] }) { return -22 }
	}
	return 0
}
