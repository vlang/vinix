// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Native NSURL and CFURL expose the same NSString pointer cell for this key.
// Exporting the key does not implement resource-date lookup.
fn ns_url_resource_key_symbol(symbol string) ?u64 {
	if symbol !in ['_NSURLCreationDateKey', '_kCFURLCreationDateKey']! || ios_runtime == unsafe { nil } { return none }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.url_resource_keys_arena == 0 {
		if ios_runtime.swift_concurrency_retired { return none }
		page := usize(C.getpagesize())
		arena := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if arena == voidptr(-1) { panic('iOS: cannot allocate URL resource keys') }
		base := u64(arena)
		object := base + 32
		text := 'NSURLCreationDateKey'
		unsafe {
			*(&u64(base)) = object
			*(&u64(object)) = ios_runtime.names['NSString']
			*(&u64(object + 8)) = 0x7c8
			*(&u64(object + 16)) = base + 64
			*(&u64(object + 24)) = u64(text.len)
			C.memcpy(voidptr(base + 64), text.str, usize(text.len))
		}
		ios_runtime.constants[object] = true
		if C.mprotect(arena, page, C.PROT_READ) != 0 { panic('iOS: cannot seal URL resource keys') }
		ios_runtime.url_resource_keys_arena = base
	}
	return ios_runtime.url_resource_keys_arena
}

// Pool callbacks, collections and Swift contexts can still borrow the key.
// Retire its registration and page only after those users have drained.
fn ns_url_resource_keys_stop() {
	arena := ios_runtime.url_resource_keys_arena
	if arena == 0 { return }
	ios_runtime.constants.delete(read64(arena))
	if C.munmap(unsafe { voidptr(arena) }, usize(C.getpagesize())) != 0 { panic('iOS: cannot retire URL resource keys') }
	ios_runtime.url_resource_keys_arena = 0
}
