// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Struct accessors use their own process-lifetime lock table. Native mutexes
// fit in these padded slots without a per-copy allocation or object registry.
struct ObjStructCopyLock {
mut:
	words [16]u64
}
__global objc_struct_copy_locks = [8]ObjStructCopyLock{}
__global objc_struct_copy_initialized = false

fn objc_struct_copy_index(address u64) int {
	return int(((address >> 4) ^ (address >> 9)) & 7)
}
fn objc_struct_copy_lock(index int) voidptr {
	return unsafe { voidptr(&objc_struct_copy_locks[index].words[0]) }
}
fn objc_struct_copy_initialize() {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if objc_struct_copy_initialized { return }
	if C.ios_sizeof_mutex() > sizeof(ObjStructCopyLock) { panic('iOS: struct property mutex exceeds native storage') }
	for i in 0 .. 8 {
		if C.ios_mutex_create(objc_struct_copy_lock(i), 0) != 0 { panic('iOS: cannot initialize struct property mutex') }
	}
	objc_struct_copy_initialized = true
}

fn objc_copy_struct(destination u64, source u64, size i64, is_atomic bool, has_strong bool) {
	// Modern Apple runtimes ignore this obsolete GC ownership flag as well.
	_ = has_strong
	mut first := unsafe { voidptr(0) }
	mut second := unsafe { voidptr(0) }
	if is_atomic {
		objc_struct_copy_initialize()
		dst := objc_struct_copy_index(destination)
		src := objc_struct_copy_index(source)
		first = objc_struct_copy_lock(if dst < src { dst } else { src })
		second = objc_struct_copy_lock(if dst < src { src } else { dst })
		if C.pthread_mutex_lock(first) != 0 { panic('iOS: cannot lock struct property storage') }
		if first != second && C.pthread_mutex_lock(second) != 0 { panic('iOS: cannot lock struct property storage') }
	}
	unsafe { C.memmove(voidptr(destination), voidptr(source), usize(size)) }
	if is_atomic {
		if first != second && C.pthread_mutex_unlock(second) != 0 { panic('iOS: cannot unlock struct property storage') }
		if C.pthread_mutex_unlock(first) != 0 { panic('iOS: cannot unlock struct property storage') }
	}
}
