// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import drm.syncobj
import memory

struct SyncobjWaitGeometry {
	objects_offset u64
	captures_offset u64
	bytes u64
}

// Packed allocator storage is aligned to 16 bytes. Align each region before
// adding the next one, checking every multiplication, addition and rounding.
fn syncobj_wait_geometry(count u64) ?SyncobjWaitGeometry {
	maximum := ~u64(0)
	if count == 0 || count > (maximum - 15) / sizeof(u32) { return none }
	objects_offset := (count * sizeof(u32) + 15) & ~u64(15)
	if count > (maximum - objects_offset) / sizeof(voidptr) { return none }
	objects_end := objects_offset + count * sizeof(voidptr)
	if objects_end > maximum - 15 { return none }
	captures_offset := (objects_end + 15) & ~u64(15)
	if count > (maximum - captures_offset) / sizeof(syncobj.FenceCapture) { return none }
	return SyncobjWaitGeometry{ objects_offset: objects_offset,
		captures_offset: captures_offset, bytes: captures_offset + count * sizeof(syncobj.FenceCapture) }
}

struct SyncobjWaitBuffer {
mut:
	allocation voidptr = unsafe { nil }
	handles &u32 = unsafe { nil }
	objects &voidptr = unsafe { nil }
	captures &syncobj.FenceCapture = unsafe { nil }
}

// Reset needs only handle/object snapshots; no capture nodes are registered.
fn new_syncobj_handle_buffer(count u32) ?SyncobjWaitBuffer {
	geometry := syncobj_wait_geometry(u64(count)) or { return none }
	allocation := memory.malloc_packed_fallible(geometry.captures_offset) @[freed]
	if allocation == unsafe { nil } { return none }
	unsafe { C.memset(allocation, 0, geometry.captures_offset) }
	return SyncobjWaitBuffer{ allocation: allocation,
		handles: unsafe { &u32(allocation) },
		objects: unsafe { &voidptr(u64(allocation) + geometry.objects_offset) } }
}

fn new_syncobj_wait_buffer(count u32) ?SyncobjWaitBuffer {
	geometry := syncobj_wait_geometry(u64(count)) or { return none }
	allocation := memory.malloc_packed_fallible(geometry.bytes) @[freed]
	if allocation == unsafe { nil } { return none }
	unsafe { C.memset(allocation, 0, geometry.bytes) }
	return SyncobjWaitBuffer{
		allocation: allocation
		handles: unsafe { &u32(allocation) }
		objects: unsafe { &voidptr(u64(allocation) + geometry.objects_offset) }
		captures: unsafe { &syncobj.FenceCapture(u64(allocation) + geometry.captures_offset) }
	}
}

// The caller must release every borrowed capture before retiring this owner.
// Inline views have no allocation; clearing one never frees stack storage.
fn (mut buffer SyncobjWaitBuffer) free_owned() {
	if buffer.allocation != unsafe { nil } { memory.free(buffer.allocation) }
	buffer.allocation = unsafe { nil }
	buffer.handles = unsafe { nil }
	buffer.objects = unsafe { nil }
	buffer.captures = unsafe { nil }
}
