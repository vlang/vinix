// SPDX-License-Identifier: GPL-2.0-or-later
module main

// These exports address NSString pointer cells, not the NSString objects.
// Native Foundation gives the deprecated URL-string name its own cell while
// sharing the same immutable object with the replacement name.
fn ns_url_error_symbol(symbol string) ?u64 {
	index := match symbol {
		'_NSURLErrorDomain' { 0 }
		'_NSURLErrorFailingURLErrorKey' { 1 }
		'_NSURLErrorFailingURLStringErrorKey' { 2 }
		'_NSErrorFailingURLStringKey' { 3 }
		'_NSURLErrorFailingURLPeerTrustErrorKey' { 4 }
		'_NSURLErrorBackgroundTaskCancelledReasonKey' { 5 }
		'_NSURLErrorNetworkUnavailableReasonKey' { 6 }
		else { return none }
	}
	if ios_runtime == unsafe { nil } { return none }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.url_error_arena == 0 {
		if ios_runtime.swift_concurrency_retired { return none }
		page := usize(C.getpagesize())
		arena := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if arena == voidptr(-1) { panic('iOS: cannot allocate URL-error constant cells') }
		mut cursor := u64(288) // Seven cells, padding and seven 32-byte record slots.
		for i, text in ['NSURLErrorDomain', 'NSErrorFailingURLKey', 'NSErrorFailingURLStringKey', '', 'NSURLErrorFailingURLPeerTrustErrorKey', 'NSURLErrorBackgroundTaskCancelledReasonKey', 'NSURLErrorNetworkUnavailableReasonKey']! {
			if i == 3 { unsafe { *(&u64(u64(arena) + 24)) = read64(u64(arena) + 16) }; continue }
			// The runtime's immortal NSString profile is the emitted __cfstring
			// record: isa, ASCII flags, byte pointer and byte length. Keep both
			// records and copied NUL-terminated bytes on the sealed page.
			object := u64(arena) + 64 + u64(i * 32)
			if cursor + u64(text.len) + 1 > u64(page) { panic('iOS: URL-error constants exceed their page') }
			unsafe {
				*(&u64(object)) = ios_runtime.names['NSString']
				*(&u64(object + 8)) = 0x7c8
				*(&u64(object + 16)) = u64(arena) + cursor
				*(&u64(object + 24)) = u64(text.len)
				C.memcpy(voidptr(u64(arena) + cursor), text.str, usize(text.len))
			}
			cursor += u64(text.len) + 1
			ios_runtime.constants[object] = true
			unsafe { *(&u64(u64(arena) + u64(i * 8))) = object }
		}
		if C.mprotect(arena, page, C.PROT_READ) != 0 { panic('iOS: cannot seal URL-error constant cells') }
		ios_runtime.url_error_arena = u64(arena)
	}
	return ios_runtime.url_error_arena + u64(index * 8)
}

// Retire after pools and constant dictionaries: their values can still refer
// to these immortal strings without owning an ordinary reference count.
fn ns_url_error_stop() {
	arena := ios_runtime.url_error_arena
	if arena == 0 { return }
	for index in [0, 1, 2, 4, 5, 6]! {
		object := read64(arena + u64(index * 8))
		ios_runtime.constants.delete(object)
	}
	if C.munmap(unsafe { voidptr(arena) }, usize(C.getpagesize())) != 0 { panic('iOS: cannot retire URL-error constant cells') }
	ios_runtime.url_error_arena = 0
}
