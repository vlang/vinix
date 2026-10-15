// SPDX-License-Identifier: GPL-2.0-or-later
module main

// These symbols export addresses of NSString pointer cells. Their values are
// measured Foundation spellings; NSUnderlyingErrorKey omits the "Key" suffix.
fn ns_foundation_key_symbol(symbol string) ?u64 {
	index := match symbol {
		'_NSUbiquityIdentityDidChangeNotification' { 0 }
		'_NSUnderlyingErrorKey' { 1 }
		'_NSUserActivityTypeBrowsingWeb' { 2 }
		else { return none }
	}
	if ios_runtime == unsafe { nil } { return none }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.foundation_keys_arena == 0 {
		if ios_runtime.swift_concurrency_retired { return none }
		page := usize(C.getpagesize())
		arena := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if arena == voidptr(-1) { panic('iOS: cannot allocate Foundation key globals') }
		mut cursor := u64(128) // Three pointer cells, padding and three CFSTR records.
		for i, text in ['NSUbiquityIdentityDidChangeNotification', 'NSUnderlyingError', 'NSUserActivityTypeBrowsingWeb']! {
			object := u64(arena) + 32 + u64(i * 32)
			if cursor + u64(text.len) + 1 > u64(page) { panic('iOS: Foundation keys exceed their page') }
			unsafe {
				*(&u64(object)) = ios_runtime.names['NSString']
				*(&u64(object + 8)) = 0x7c8
				*(&u64(object + 16)) = u64(arena) + cursor
				*(&u64(object + 24)) = u64(text.len)
				C.memcpy(voidptr(u64(arena) + cursor), text.str, usize(text.len))
				*(&u64(u64(arena) + u64(i * 8))) = object
			}
			cursor += u64(text.len) + 1
			ios_runtime.constants[object] = true
		}
		if C.mprotect(arena, page, C.PROT_READ) != 0 { panic('iOS: cannot seal Foundation key globals') }
		ios_runtime.foundation_keys_arena = u64(arena)
	}
	return ios_runtime.foundation_keys_arena + u64(index * 8)
}

// Notifications, pool destructors, dictionaries and Swift contexts must stop
// using these immortal strings before their registrations and page retire.
fn ns_foundation_keys_stop() {
	arena := ios_runtime.foundation_keys_arena
	if arena == 0 { return }
	for i in 0 .. 3 { ios_runtime.constants.delete(read64(arena + u64(i * 8))) }
	if C.munmap(unsafe { voidptr(arena) }, usize(C.getpagesize())) != 0 { panic('iOS: cannot retire Foundation key globals') }
	ios_runtime.foundation_keys_arena = 0
}
