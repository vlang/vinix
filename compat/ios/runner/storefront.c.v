// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Storefront is resilient: the getter borrows Self through x20. Native ARM64
// StoreKit stores countryCode's two String words at offset zero and returns an
// owned String in x0/x1. Copy only that field, retaining its bridge owner; the
// other Storefront fields and any account/store service are not involved.
fn storefront_country_code(value u64) SwiftStringWords {
	mut words := SwiftStringWords{}
	C.memcpy(unsafe { &words }, voidptr(value), 16)
	swift_bridge_retain(words.second)
	return words
}

fn storefront_symbol(symbol string) ?u64 {
	if symbol != '_$s8StoreKit10StorefrontV11countryCodeSSvg' { return none }
	$if !arm64 { return none }
	if ios_runtime == unsafe { nil } { return none }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.storefront_retired { return none }
	if ios_runtime.storefront_code != 0 { return ios_runtime.storefront_code }
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if code == unsafe { voidptr(-1) } { return none }
	base := u64(code)
	write32(base, 0xaa1403e0) // mov x0,x20: borrowed resilient Self -> V helper.
	write32(base + 4, 0x58000070) // ldr x16,+16
	write32(base + 8, 0xd61f0200) // br x16: helper returns the String pair directly.
	unsafe { *(&u64(base + 16)) = u64(voidptr(storefront_country_code)) }
	C.__builtin___clear_cache(code, voidptr(base + 24))
	if C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) != 0 {
		if C.munmap(code, page) != 0 { panic('iOS: cannot retire unsealed Storefront getter') }
		return none
	}
	ios_runtime.storefront_code = base
	return base
}

fn storefront_stop() {
	// Runtime lock held after Swift/Objective-C callers and callbacks drain.
	ios_runtime.storefront_retired = true
	if ios_runtime.storefront_code == 0 { return }
	if C.munmap(voidptr(ios_runtime.storefront_code), usize(C.getpagesize())) != 0 {
		panic('iOS: cannot retire Storefront getter')
	}
	ios_runtime.storefront_code = 0
}
