// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module bo

// Per-open AGX GEM handle and mmap-authorization table. Backends serialize
// access with their existing file lock so handle removal and backend-specific
// mapping cleanup remain one atomic operation.

import drm.gem

pub struct Table {
mut:
	objects      []&gem.GemObject
	mmap_objects []&gem.GemObject
}

// Add the creator's existing reference to this file's handle table.
pub fn (mut table Table) add_created(object &gem.GemObject) {
	if object != unsafe { nil } {
		table.objects << object
	}
}

// Return a borrowed pointer. The caller must retain the file lock while using
// it, or use get_ref() when the pointer has to outlive that lock.
pub fn (table &Table) find(handle u32) ?&gem.GemObject {
	for object in table.objects {
		if object.handle == handle {
			return object
		}
	}
	return none
}

pub fn (table &Table) get_ref(handle u32) ?&gem.GemObject {
	object := table.find(handle) or { return none }
	gem.ref_obj(object)
	return object
}

pub fn (mut table Table) import_object(object &gem.GemObject) ?u32 {
	if object == unsafe { nil } {
		return none
	}
	for existing in table.objects {
		if voidptr(existing) == voidptr(object) {
			return existing.handle
		}
	}
	gem.ref_obj(object)
	table.objects << object
	return object.handle
}

pub fn (mut table Table) authorize_mmap(handle u32) ?u64 {
	object := table.find(handle) or { return none }
	for authorized in table.mmap_objects {
		if voidptr(authorized) == voidptr(object) {
			return gem.create_mmap_offset(object)
		}
	}
	gem.ref_obj(object)
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

pub fn (table &Table) contains(object &gem.GemObject) bool {
	for candidate in table.objects {
		if voidptr(candidate) == voidptr(object) {
			return true
		}
	}
	return false
}

// Remove a file handle without dropping its reference. This lets the backend
// tear down or retain GPU mappings before it performs the matching unref.
pub fn (mut table Table) remove(handle u32) ?&gem.GemObject {
	for index, object in table.objects {
		if object.handle == handle {
			table.objects.delete(index)
			return object
		}
	}
	return none
}

pub fn (mut table Table) release_all() {
	for object in table.mmap_objects {
		gem.unref(object)
	}
	table.mmap_objects.clear()
	for object in table.objects {
		gem.unref(object)
	}
	table.objects.clear()
}
