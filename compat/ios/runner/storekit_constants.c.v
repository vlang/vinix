// SPDX-License-Identifier: GPL-2.0-or-later
module main

// SKAdNetwork exports NSString pointer cells containing "high", "medium" and
// "low", measured from the installed iOSSupport StoreKit shared-cache image.
// These globals provide values only; they do not submit attribution requests.
fn storekit_constant_symbol(symbol string) ?u64 {
	index := match symbol {
		'_SKAdNetworkCoarseConversionValueHigh' { 0 }
		'_SKAdNetworkCoarseConversionValueMedium' { 1 }
		'_SKAdNetworkCoarseConversionValueLow' { 2 }
		else { return none }
	}
	if ios_runtime == unsafe { nil } { return none }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.storekit_constants_arena == 0 {
		if ios_runtime.swift_concurrency_retired { return none }
		page := usize(C.getpagesize())
		arena := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
			C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if arena == voidptr(-1) { panic('iOS: cannot allocate StoreKit globals') }
		// Three pointer cells followed by three 32-byte CFSTR records.
		mut cursor := u64(120)
		for i, text in ['high', 'medium', 'low']! {
			object := u64(arena) + 24 + u64(i * 32)
			if cursor + u64(text.len) + 1 > u64(page) {
				panic('iOS: StoreKit globals exceed their page')
			}
			unsafe {
				*(&u64(u64(arena) + u64(i * 8))) = object
				*(&u64(object)) = ios_runtime.names['NSString']
				*(&u64(object + 8)) = 0x7c8
				*(&u64(object + 16)) = u64(arena) + cursor
				*(&u64(object + 24)) = u64(text.len)
				C.memcpy(voidptr(u64(arena) + cursor), text.str, usize(text.len))
			}
			cursor += u64(text.len) + 1
			ios_runtime.constants[object] = true
		}
		if C.mprotect(arena, page, C.PROT_READ) != 0 {
			panic('iOS: cannot seal StoreKit globals')
		}
		ios_runtime.storekit_constants_arena = u64(arena)
	}
	return ios_runtime.storekit_constants_arena + u64(index * 8)
}

// Pool destructors, collections and Swift contexts may still borrow these
// immortal strings. Retire the registrations and page after those users drain.
fn storekit_constants_stop() {
	arena := ios_runtime.storekit_constants_arena
	if arena == 0 { return }
	for i in 0 .. 3 { ios_runtime.constants.delete(read64(arena + u64(i * 8))) }
	if C.munmap(unsafe { voidptr(arena) }, usize(C.getpagesize())) != 0 {
		panic('iOS: cannot retire StoreKit globals')
	}
	ios_runtime.storekit_constants_arena = 0
}
