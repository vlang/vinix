// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import drm.ioctl
import drm.syncobj
import memory
import usercopy

fn C.__builtin_alloca(uint) voidptr

// Append at most 31 bytes. The formatter terminates the file name explicitly;
// detailed object/driver fields start zeroed, like Linux's kzalloc buffer.
fn sync_name_append(target &u8, offset u32, text string) u32 {
	mut position := offset
	for index in 0 .. text.len {
		if position == 31 { break }
		unsafe { target[position] = text[index] }
		position++
	}
	return position
}

fn sync_name_number(target &u8, offset u32, value u64) u32 {
	mut digits := [20]u8{}
	mut count := u32(0)
	mut remaining := value
	for {
		digits[count] = `0` + u8(remaining % 10)
		count++
		remaining /= 10
		if remaining == 0 { break }
	}
	mut position := offset
	for count > 0 && position < 31 {
		count--
		unsafe { target[position] = digits[count] }
		position++
	}
	return position
}

fn sync_info_names(file_name &u8, obj_name &u8, driver_name &u8, info &syncobj.FenceSnapshot) {
	driver := match info.kind { .chain { 'dma_fence_chain' } .fence_array { 'dma_fence_array' } .stub { 'stub' } .queue { 'asahi' } .generic { 'vinix' } }
	timeline := match info.kind { .chain, .fence_array { 'unbound' } .stub { 'stub' } .queue { 'queue' } .generic { 'fence' } }
	sync_name_append(obj_name, 0, timeline)
	sync_name_append(driver_name, 0, driver)
	mut offset := sync_name_append(file_name, 0, driver)
	offset = sync_name_append(file_name, offset, '-')
	offset = sync_name_append(file_name, offset, timeline)
	offset = sync_name_number(file_name, offset, info.context)
	offset = sync_name_append(file_name, offset, '-')
	// Linux prints seqno with %lld, including the signed high-half values.
	mut magnitude := info.seqno
	if i64(info.seqno) < 0 {
		offset = sync_name_append(file_name, offset, '-')
		magnitude = u64(-(i64(info.seqno) + 1)) + 1
	}
	offset = sync_name_number(file_name, offset, magnitude)
	unsafe { file_name[offset] = 0 }
}

// Unwrap retained chains head-first, as dma_fence_unwrap does. Retirement can
// shrink the second pass, but immutable links cannot add records after count.
fn sync_file_info_ioctl(fence &syncobj.DmaFence, address u64, name &u8) int {
	mut info := ioctl.SyncFileInfo{}
	if !usercopy.copy_from_user(unsafe { &info }, address, sizeof(ioctl.SyncFileInfo)) { return -14 }
	if info.flags != 0 || info.pad != 0 { return -22 }
	mut count := u32(0)
	mut iterator := unsafe { &syncobj.FenceUnwrap(C.__builtin_alloca(sizeof(syncobj.FenceUnwrap))) }
	mut cursor := syncobj.unwrap_first(fence, iterator)
	for cursor != unsafe { nil } {
		if count == ~u32(0) { return -75 }
		count++
		cursor = syncobj.unwrap_next(iterator)
	}
	// Count-only queries ignore the supplied array pointer and allocate nothing.
	if info.num_fences == 0 {
		info.status = i32(syncobj.snapshot(fence).status)
	} else {
		if info.num_fences < count { return -22 }
		bytes := u64(count) * sizeof(ioctl.SyncFenceInfo)
		allocation := memory.malloc_packed_fallible(bytes)
		if allocation == unsafe { nil } { return -12 }
		defer { memory.free(allocation) }
		unsafe { C.memset(allocation, 0, bytes) }
		mut details := unsafe { &ioctl.SyncFenceInfo(allocation) }
		info.status = 1
		cursor = syncobj.unwrap_first(fence, iterator)
		count = 0
		for cursor != unsafe { nil } {
			leaf := syncobj.snapshot(cursor)
			mut detail := unsafe { &details[count] }
			unsafe { *detail = ioctl.SyncFenceInfo{ status: i32(leaf.status), timestamp_ns: leaf.timestamp_ns } }
			// The root supplies the file name; each record names its leaf.
			mut ignored_name := [32]u8{}
			sync_info_names(unsafe { &ignored_name[0] }, unsafe { &detail.obj_name[0] }, unsafe { &detail.driver_name[0] }, unsafe { &leaf })
			if info.status > 0 { info.status = detail.status }
			count++
			cursor = syncobj.unwrap_next(iterator)
		}
		// Copy the array before the header, preserving Linux's partial-output
		// order when the later copy fails or the two user ranges overlap.
		if !usercopy.copy_to_user(info.sync_fence_info, details, bytes) { return -14 }
	}
	if name != unsafe { nil } && unsafe { name[0] } != 0 {
		for i in 0 .. info.name.len {
			info.name[i] = unsafe { name[i] }
			if info.name[i] == 0 { break }
		}
	} else {
		state := syncobj.identity(fence)
		mut names := ioctl.SyncFenceInfo{}
		sync_info_names(unsafe { &info.name[0] }, unsafe { &names.obj_name[0] }, unsafe { &names.driver_name[0] }, unsafe { &state })
	}
	info.num_fences = count
	if !usercopy.copy_to_user(address, unsafe { &info }, sizeof(ioctl.SyncFileInfo)) { return -14 }
	return 0
}
