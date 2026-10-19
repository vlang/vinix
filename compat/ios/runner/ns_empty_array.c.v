// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The global is a pointer cell; the struct spelling exports the object itself.
// The cache owns one ordinary ObjHeader, immortal to callers until shutdown.
fn ns_empty_array_symbol(symbol string) ?u64 {
	if symbol !in ['___NSArray0__', '___NSArray0__struct']! || ios_runtime == unsafe { nil } { return none }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.empty_array_cell == 0 {
		if ios_runtime.swift_concurrency_retired { return none }
		page := usize(C.getpagesize())
		arena := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if arena == voidptr(-1) { panic('iOS: cannot allocate empty array cell') }
		object := objc_allocate(ios_runtime.names['NSArray'])
		unsafe { *(&u64(arena)) = object }
		if C.mprotect(arena, page, C.PROT_READ) != 0 { panic('iOS: cannot seal empty array cell') }
		ios_runtime.constants[object] = true
		ios_runtime.empty_array = object
		ios_runtime.empty_array_cell = u64(arena)
	}
	return if symbol == '___NSArray0__' { ios_runtime.empty_array_cell } else { ios_runtime.empty_array }
}

fn ns_empty_array_selector(object u64, selector string) bool {
	return object != 0 && object == ios_runtime.empty_array && selector in [
		'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'hash', 'isEqual:', 'isEqualToArray:']!
}

fn ns_empty_array_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if object == 0 || object != ios_runtime.empty_array { return false }
	match selector {
		'copy', 'copyWithZone:' { frame.x[0] = object }
		'mutableCopy', 'mutableCopyWithZone:' { frame.x[0] = objc_allocate(ios_runtime.names['NSMutableArray']) }
		'hash' { frame.x[0] = cf_hash(object) }
		'isEqual:', 'isEqualToArray:' { frame.x[0] = u64(object_equal(object, frame.x[2])) }
		'addObject:', 'removeObjectAtIndex:', 'removeAllObjects', 'setObject:atIndexedSubscript:',
		'setObject:forKeyedSubscript:', 'setObject:forKey:', 'removeObjectForKey:' {
			panic('iOS: mutation of the immutable empty array')
		}
		else { return false }
	}
	return true
}

// Pool and Swift owners may still dereference the cell. Retire only after both
// drain, then remove immortality and release exactly the cache's reference.
fn ns_empty_array_stop() {
	cell := ios_runtime.empty_array_cell
	if cell == 0 { return }
	object := ios_runtime.empty_array
	ios_runtime.constants.delete(object)
	objc_release(object)
	if C.munmap(unsafe { voidptr(cell) }, usize(C.getpagesize())) != 0 { panic('iOS: cannot retire empty array cell') }
	ios_runtime.empty_array = 0
	ios_runtime.empty_array_cell = 0
}
