// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Foundation exports data addresses: three float32 values, an int64 sentinel,
// and NSString pointer cells. Keep their widths and indirection distinct.
fn ns_url_session_constant_symbol(symbol string) ?u64 {
	offset := match symbol {
		'_NSURLSessionDownloadTaskResumeData' { 0 }
		'_NSURLSessionTaskPriorityDefault' { 8 }
		'_NSURLSessionTaskPriorityLow' { 12 }
		'_NSURLSessionTaskPriorityHigh' { 16 }
		'_NSURLSessionTransferSizeUnknown' { 24 }
		'_NSURLSessionUploadTaskResumeData' { 32 }
		else { return none }
	}
	if ios_runtime == unsafe { nil } { return none }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.url_session_constants_arena == 0 {
		if ios_runtime.swift_concurrency_retired { return none }
		page := usize(C.getpagesize())
		arena := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if arena == voidptr(-1) { panic('iOS: cannot allocate URL-session constants') }
		unsafe {
			*(&f32(u64(arena) + 8)) = 0.5
			*(&f32(u64(arena) + 12)) = 0.25
			*(&f32(u64(arena) + 16)) = 0.75
			*(&i64(u64(arena) + 24)) = -1
		}
		mut cursor := u64(128)
		for i, text in ['NSURLSessionDownloadTaskResumeData', 'NSURLSessionUploadTaskResumeData']! {
			object := u64(arena) + 64 + u64(i * 32)
			if cursor + u64(text.len) + 1 > u64(page) { panic('iOS: URL-session constants exceed their page') }
			unsafe {
				*(&u64(object)) = ios_runtime.names['NSString']
				*(&u64(object + 8)) = 0x7c8
				*(&u64(object + 16)) = u64(arena) + cursor
				*(&u64(object + 24)) = u64(text.len)
				C.memcpy(voidptr(u64(arena) + cursor), text.str, usize(text.len))
				*(&u64(u64(arena) + u64(i * 32))) = object
			}
			cursor += u64(text.len) + 1
			ios_runtime.constants[object] = true
		}
		if C.mprotect(arena, page, C.PROT_READ) != 0 { panic('iOS: cannot seal URL-session constants') }
		ios_runtime.url_session_constants_arena = u64(arena)
	}
	return ios_runtime.url_session_constants_arena + u64(offset)
}

// Pool destructors, dictionaries and Swift contexts may still use these keys.
// Retire them only after those owners drain at quiescent runtime shutdown.
fn ns_url_session_constants_stop() {
	arena := ios_runtime.url_session_constants_arena
	if arena == 0 { return }
	for offset in [0, 32]! { ios_runtime.constants.delete(read64(arena + u64(offset))) }
	if C.munmap(unsafe { voidptr(arena) }, usize(C.getpagesize())) != 0 { panic('iOS: cannot retire URL-session constants') }
	ios_runtime.url_session_constants_arena = 0
}
