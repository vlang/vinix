// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.ios_thread_create(voidptr, usize, u64, usize, i32, voidptr, voidptr) i32
fn C.ios_thread_join(u64, voidptr) i32
fn C.ios_thread_detached(u64, &i32) i32

// Measured ARM64 Darwin pthread_attr_t: signature, guard, stack top, size,
// scheduling fields, packed flags and reserved bytes. It owns no allocation.
fn pthread_attr_valid(object u64) bool {
	return object != 0 && read64(object) == 0x54484441
}

fn darwin_attr_init(object u64) i32 {
	if object == 0 { return 22 }
	C.memset(unsafe { voidptr(object) }, 0, 64)
	unsafe { *(&u64(object)) = 0x54484441 }
	write32(object + 32, 0x8ff)
	write32(object + 40, 0x10010101)
	return 0
}

fn darwin_attr_destroy(object u64) i32 {
	if !pthread_attr_valid(object) { return 22 }
	unsafe { *(&u64(object)) = 0 }
	return 0
}

fn darwin_attr_getdetach(object u64, output &i32) i32 {
	if !pthread_attr_valid(object) || output == unsafe { nil } { return 22 }
	unsafe { *output = i32(read32(object + 40) & 0xff) }
	return 0
}

fn darwin_attr_setdetach(object u64, state i32) i32 {
	if !pthread_attr_valid(object) || (state != 1 && state != 2) { return 22 }
	write32(object + 40, (read32(object + 40) & ~u32(0xff)) | u32(state))
	return 0
}

fn pthread_attr_stacksize(object u64) u64 {
	size := read64(object + 24)
	return if size == 0 { u64(524288) } else { size }
}

fn darwin_attr_getsize(object u64, output &u64) i32 {
	if !pthread_attr_valid(object) || output == unsafe { nil } { return 22 }
	unsafe { *output = pthread_attr_stacksize(object) }
	return 0
}

fn darwin_attr_setsize(object u64, size u64) i32 {
	// The Mac accepts legacy 4 KiB multiples and rounds them to a 16 KiB page.
	if !pthread_attr_valid(object) || size == 0 || size & 4095 != 0 || size > ~u64(0) - 16383 { return 22 }
	unsafe { *(&u64(object + 24)) = (size + 16383) & ~u64(16383) }
	return 0
}

fn darwin_attr_getstack(object u64, base &u64, size &u64) i32 {
	if !pthread_attr_valid(object) || base == unsafe { nil } || size == unsafe { nil } { return 22 }
	// With an explicit size and no address the native getter returns -size.
	unsafe { *base = read64(object + 16) - read64(object + 24)
		*size = pthread_attr_stacksize(object) }
	return 0
}

fn darwin_attr_setstack(object u64, base u64, size u64) i32 {
	if !pthread_attr_valid(object) || base == 0 || base & 16383 != 0 || size == 0 || size & 16383 != 0 || base > ~u64(0) - size { return 22 }
	unsafe { *(&u64(object + 16)) = base + size
		*(&u64(object + 24)) = size }
	return 0
}

fn pthread_attr_guardsize(object u64) u64 {
	return if read32(object + 40) & 0x10000000 != 0 { u64(16384) } else { read64(object + 8) }
}

fn darwin_attr_getguard(object u64, output &u64) i32 {
	if !pthread_attr_valid(object) || output == unsafe { nil } { return 22 }
	unsafe { *output = pthread_attr_guardsize(object) }
	return 0
}

fn darwin_attr_setguard(object u64, size u64) i32 {
	if !pthread_attr_valid(object) || size & 4095 != 0 || size > ~u64(0) - 16383 { return 22 }
	unsafe { *(&u64(object + 8)) = (size + 16383) & ~u64(16383) }
	write32(object + 40, read32(object + 40) & ~u32(0x10000000))
	return 0
}

fn darwin_pthread_create(thread_id voidptr, attributes voidptr, start voidptr, argument voidptr) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	if thread_id == unsafe { nil } || start == unsafe { nil } { return 22 }
	mut size := u64(524288)
	mut top := u64(0)
	mut guard := u64(16384)
	mut detached := i32(0)
	if attributes != unsafe { nil } {
		object := u64(attributes)
		if !pthread_attr_valid(object) { return 22 }
		flags := read32(object + 40)
		if flags & 0xff != 1 && flags & 0xff != 2 { return 22 }
		// Only default inherited scheduling is implemented; do not ignore a
		// foreign QoS/policy request hidden in Darwin's opaque object.
		if read64(object + 32) != 0x8ff || flags & ~u32(0x100000ff) != 0x10100 || read32(object + 44) != 0 || read64(object + 48) != 0 || read64(object + 56) != 0 { return 45 }
		size = pthread_attr_stacksize(object)
		top = read64(object + 16)
		guard = pthread_attr_guardsize(object)
		if size & 16383 != 0 || (top != 0 && (top < size || top & 16383 != 0)) || guard & 16383 != 0 { return 22 }
		detached = if flags & 0xff == 2 { i32(1) } else { i32(0) }
	}
	return i32(darwin_native_error(int(mach_thread_create(thread_id, usize(size), top, usize(guard), detached, start, argument))))
}

fn darwin_pthread_join(handle u64, output voidptr) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	if handle == 0 { return 22 }
	if handle == u64(C.pthread_self()) { return 11 }
	$if linux {
		mut detached := i32(0)
		result := C.ios_thread_detached(handle, unsafe { &detached })
		if result != 0 { return i32(pthread_error(int(result))) }
		if detached != 0 { return 22 }
	}
	port := mach_threads_join_begin(handle)
	result := C.ios_thread_join(handle, output)
	if result == 0 { mach_threads_join_end(port) }
	return i32(pthread_error(int(result)))
}

fn pthread_attr_symbol(symbol string) ?u64 {
	return match symbol {
		'_pthread_attr_init' { u64(unsafe { voidptr(darwin_attr_init) }) }
		'_pthread_attr_destroy' { u64(unsafe { voidptr(darwin_attr_destroy) }) }
		'_pthread_attr_getdetachstate' { u64(unsafe { voidptr(darwin_attr_getdetach) }) }
		'_pthread_attr_setdetachstate' { u64(unsafe { voidptr(darwin_attr_setdetach) }) }
		'_pthread_attr_getstacksize' { u64(unsafe { voidptr(darwin_attr_getsize) }) }
		'_pthread_attr_setstacksize' { u64(unsafe { voidptr(darwin_attr_setsize) }) }
		'_pthread_attr_getstack' { u64(unsafe { voidptr(darwin_attr_getstack) }) }
		'_pthread_attr_setstack' { u64(unsafe { voidptr(darwin_attr_setstack) }) }
		'_pthread_attr_getguardsize' { u64(unsafe { voidptr(darwin_attr_getguard) }) }
		'_pthread_attr_setguardsize' { u64(unsafe { voidptr(darwin_attr_setguard) }) }
		else { return none }
	}
}
