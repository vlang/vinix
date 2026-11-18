// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module bo

// Per-open AGX GEM handle and mmap-authorization table. Backends serialize
// access with their existing file lock so handle removal and backend-specific
// mapping cleanup remain one atomic operation.

import drm.gem
import gpu.agx.vm as agxvm
import memory

// Match Asahi's checked_object_size errors before requesting backing storage.
// The GEM constructor still owns rounding and allocation; a valid size may OOM.
pub fn create_size_error(size u64) int {
	if size == 0 { return -22 } // EINVAL
	if size > ~u64(0) - agxvm.page_mask { return -75 } // EOVERFLOW
	return 0
}

pub struct Table {
mut:
	objects      []&gem.GemObject
	mmap_objects []&gem.GemObject
	local_handles bool
	first_free int // lowest vacant index in the G13 namespace
}

pub fn new_table(local_handles bool) Table {
	return Table{local_handles: local_handles}
}

pub fn (table &Table) uses_local_handles() bool {
	return table.local_handles
}

// Reserve one slot while holding the file lock. GEM creation keeps that lock
// through publication so it can return ENOMEM before constructing the object.
pub fn (mut table Table) reserve_handle_entry() bool {
	if table.local_handles && table.first_free < table.objects.len { return true }
	if table.objects.len < table.objects.cap { return true }
	max_capacity := max_int / int(sizeof(voidptr))
	if table.objects.len >= max_capacity { return false }
	capacity := if table.objects.cap == 0 { 2 } else if table.objects.cap <= max_capacity / 2 {
		table.objects.cap * 2
	} else { max_capacity }
	storage := memory.malloc_packed_fallible(u64(capacity) * sizeof(voidptr)) @[freed]
	if storage == unsafe { nil } { return false }
	mut replacement := []&gem.GemObject{}
	unsafe {
		replacement.data = storage
		replacement.len = table.objects.len
		replacement.cap = capacity
		replacement.flags = .noslices
		if table.objects.len != 0 {
			C.memcpy(storage, table.objects.data, u64(table.objects.len) * sizeof(voidptr))
		}
		mut old := table.objects
		table.objects = replacement
		old.free()
	}
	return true
}

// Transfer the creator's reference and return the name visible to this file.
// Production callers reserve storage before constructing or importing a BO.
pub fn (mut table Table) add_created(object &gem.GemObject) u32 {
	if object == unsafe { nil } { return 0 }
	table.objects.flags |= .noslices
	if !table.local_handles {
		table.objects << object
		return object.handle
	}
	index := table.first_free
	if index == table.objects.len {
		table.objects << object
	} else {
		table.objects[index] = object
	}
	table.first_free++
	for table.first_free < table.objects.len && table.objects[table.first_free] != unsafe { nil } {
		table.first_free++
	}
	return u32(index + 1)
}

fn (table &Table) handle_index(handle u32) ?int {
	if table.local_handles {
		if handle == 0 || u64(handle) > u64(table.objects.len) { return none }
		index := int(handle - 1)
		if table.objects[index] == unsafe { nil } { return none }
		return index
	}
	for index, object in table.objects {
		if object.handle == handle { return index }
	}
	return none
}

// Return a borrowed pointer. The caller must retain the file lock while using
// it, or use get_ref() when the pointer has to outlive that lock.
pub fn (table &Table) find(handle u32) ?&gem.GemObject {
	index := table.handle_index(handle) or { return none }
	return table.objects[index]
}

pub fn (table &Table) get_ref(handle u32) ?&gem.GemObject {
	object := table.find(handle) or { return none }
	gem.ref_obj(object)
	return object
}

pub fn (mut table Table) import_object(object &gem.GemObject) ?u32 {
	if object == unsafe { nil } || object.vm_private_identity != 0 {
		return none
	}
	if !table.local_handles && object.handle == 0 { return none }
	for index, existing in table.objects {
		if voidptr(existing) == voidptr(object) {
			return if table.local_handles { u32(index + 1) } else { existing.handle }
		}
	}
	if !table.reserve_handle_entry() { return none }
	gem.ref_obj(object)
	return table.add_created(object)
}

pub fn (mut table Table) authorize_mmap(handle u32) ?u64 {
	object := table.find(handle) or { return none }
	for authorized in table.mmap_objects {
		if voidptr(authorized) == voidptr(object) {
			return gem.create_mmap_offset(object)
		}
	}
	gem.ref_obj(object)
	table.mmap_objects.flags |= .noslices
	table.mmap_objects << object
	return gem.create_mmap_offset(object)
}

pub fn (table &Table) mmap_page(page u64) voidptr {
	for object in table.mmap_objects {
		if address := gem.get_object_mmap_page(object, page) {
			return address
		}
	}
	return unsafe { nil }
}

// Match the authorized object's direct-map policy for every userspace alias.
pub fn (table &Table) mmap_attributes(offset u64) u64 {
	for object in table.mmap_objects {
		base := gem.create_mmap_offset(object)
		if offset >= base && offset - base < object.size { return object.pte_extra }
	}
	return 0
}

// A VMA records one cache policy. It must stay inside a single authorized BO,
// even when another authorized object has the immediately following offset.
pub fn (table &Table) valid_mmap_range(offset u64, length u64) bool {
	if length == 0 || offset > ~u64(0) - length { return false }
	for object in table.mmap_objects {
		base := gem.create_mmap_offset(object)
		if offset >= base && offset - base < object.size {
			return length <= object.size - (offset - base)
		}
	}
	return false
}

// Remove a file handle without dropping its reference. This lets the backend
// tear down or retain GPU mappings before it performs the matching unref.
pub fn (mut table Table) remove(handle u32) ?&gem.GemObject {
	index := table.handle_index(handle) or { return none }
	object := table.objects[index]
	if table.local_handles {
		table.objects[index] = unsafe { nil }
		if index < table.first_free { table.first_free = index }
	} else {
		table.objects.delete(index)
	}
	return object
}

pub fn (mut table Table) release_all() {
	for object in table.mmap_objects {
		gem.unref(object)
	}
	for object in table.objects {
		if object != unsafe { nil } { gem.unref(object) }
	}
	// Freed rather than cleared: the table goes with its file. Both are empty
	// and usable again afterwards.
	unsafe {
		table.mmap_objects.free()
		table.objects.free()
	}
	table.first_free = 0
}
