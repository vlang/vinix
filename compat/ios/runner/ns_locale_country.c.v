// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Native Foundation and CoreFoundation expose both spellings at the same
// NSString pointer cell. Locale lookup uses the key's content, not its name.
fn ns_locale_country_symbol(symbol string) ?u64 {
	if symbol !in ['_NSLocaleCountryCode', '_kCFLocaleCountryCode']! || ios_runtime == unsafe { nil } { return none }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.ns_locale_country_arena == 0 {
		if ios_runtime.swift_concurrency_retired { return none }
		page := usize(C.getpagesize())
		arena := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if arena == voidptr(-1) { panic('iOS: cannot allocate locale country key') }
		base := u64(arena)
		object := base + 32
		text := 'kCFLocaleCountryCodeKey'
		unsafe {
			*(&u64(base)) = object
			*(&u64(object)) = ios_runtime.names['NSString']
			*(&u64(object + 8)) = 0x7c8
			*(&u64(object + 16)) = base + 64
			*(&u64(object + 24)) = u64(text.len)
			C.memcpy(voidptr(base + 64), text.str, usize(text.len))
		}
		ios_runtime.constants[object] = true
		if C.mprotect(arena, page, C.PROT_READ) != 0 { panic('iOS: cannot seal locale country key') }
		ios_runtime.ns_locale_country_arena = base
	}
	return ios_runtime.ns_locale_country_arena
}

// Dictionaries, pool callbacks and Swift contexts can still borrow the key.
// Retire its registration and page only after those users have drained.
fn ns_locale_country_stop() {
	arena := ios_runtime.ns_locale_country_arena
	if arena == 0 { return }
	ios_runtime.constants.delete(read64(arena))
	if C.munmap(unsafe { voidptr(arena) }, usize(C.getpagesize())) != 0 { panic('iOS: cannot retire locale country key') }
	ios_runtime.ns_locale_country_arena = 0
}
