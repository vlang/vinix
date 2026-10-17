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
	if symbol !in ['_$s8StoreKit10StorefrontV11countryCodeSSvg',
		'_$s8StoreKit10StorefrontV7currentACSgvgZ', '_$s8StoreKit10StorefrontV7currentACSgvgZTu']! { return none }
	$if !arm64 { return none }
	if ios_runtime == unsafe { nil } { return none }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.storefront_retired { return none }
	base := storefront_arena_locked() or { return none }
	return match symbol {
		'_$s8StoreKit10StorefrontV7currentACSgvgZ' { base + 32 }
		'_$s8StoreKit10StorefrontV7currentACSgvgZTu' { base + u64(C.getpagesize()) }
		else { base }
	}
}

fn storefront_arena_locked() ?u64 {
	if ios_runtime.storefront_code != 0 { return ios_runtime.storefront_code }
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if code == unsafe { voidptr(-1) } { return none }
	base := u64(code)
	write32(base, 0xaa1403e0) // mov x0,x20: borrowed resilient Self -> V helper.
	write32(base + 4, 0x58000070) // ldr x16,+16
	write32(base + 8, 0xd61f0200) // br x16: helper returns the String pair directly.
	unsafe { *(&u64(base + 16)) = u64(voidptr(storefront_country_code)) }
	// Vinix has no App Store account service. current therefore completes with
	// Optional<Storefront>.none. Native Storefront's extra inhabitant uses only
	// countryCode's bridge word at +8; its other 40 bytes stay uninitialized.
	// Async indirect result is x0, context is x22. ResumeParent receives that
	// same child context and restores/frees its own caller frame. A tail branch
	// permits completion to free this context without a subsequent access.
	write32(base + 32, 0xf900041f) // str xzr,[x0,#8]
	write32(base + 36, 0xf94006d0) // ldr x16,[x22,#8]
	write32(base + 40, 0xd61f0200) // br x16
	descriptor := base + u64(page)
	swift_protocol_relative(descriptor, base + 32)
	write32(descriptor + 4, 64) // Native async function descriptor context size.
	C.__builtin___clear_cache(code, voidptr(base + 44))
	if C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(voidptr(descriptor), page, C.PROT_READ) != 0 {
		if C.munmap(code, page * 2) != 0 { panic('iOS: cannot retire unsealed Storefront entries') }
		return none
	}
	ios_runtime.storefront_code = base
	return base
}

fn storefront_stop() {
	// Runtime lock held after Swift/Objective-C callers and callbacks drain.
	ios_runtime.storefront_retired = true
	if ios_runtime.storefront_code == 0 { return }
	if C.munmap(voidptr(ios_runtime.storefront_code), usize(C.getpagesize()) * 2) != 0 {
		panic('iOS: cannot retire Storefront entries')
	}
	ios_runtime.storefront_code = 0
}
