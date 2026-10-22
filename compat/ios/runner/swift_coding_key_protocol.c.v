// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftCodingKeyProtocolFailure {}

fn (_ &SwiftCodingKeyProtocolFailure) msg() string {
	return 'iOS: Swift CodingKey requires an active runtime and sealed storage'
}

fn (_ &SwiftCodingKeyProtocolFailure) code() int { return 1 }

__global swift_coding_key_protocol_failure_value = SwiftCodingKeyProtocolFailure{}

fn swift_coding_key_protocol_failure() IError {
	return unsafe { &swift_coding_key_protocol_failure_value }
}

fn swift_coding_key_protocol_arena_checked() !u64 {
	$if !arm64 {
		return swift_coding_key_protocol_failure()
	}
	if ios_runtime == unsafe { nil } { return swift_coding_key_protocol_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_coding_key_protocol_retired || ios_runtime.swift_concurrency_retired {
		return swift_coding_key_protocol_failure()
	}
	if ios_runtime.swift_coding_key_protocol_arena != 0 {
		return ios_runtime.swift_coding_key_protocol_arena
	}
	// Borrow canonical declarations under the recursive publication lock. Both
	// keyed containers retire first; these dependencies remain live until later.
	custom_debug := swift_custom_debug_arena_checked()!
	string_protocol := swift_string_metadata() - 16 + 352
	page := u64(C.getpagesize())
	arena := C.mmap(unsafe { nil }, usize(page), C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == unsafe { voidptr(-1) } { return swift_coding_key_protocol_failure() }
	base := u64(arena)
	write32(base, 0x30043) // Unique Swift protocol, unconstrained by class.
	swift_protocol_relative(base + 4, ios_runtime.swift_array_arena + page + 224)
	swift_protocol_relative(base + 8, base + 128)
	write32(base + 12, 2) // Inherited protocol constraints on Self.
	write32(base + 16, 6)
	for i, parent in [custom_debug, string_protocol]! {
		requirement := base + 24 + u64(i * 12)
		write32(requirement, 0x80)
		swift_protocol_relative(requirement + 4, base + 144)
		swift_protocol_relative(requirement + 8, parent)
	}
	for i, flags in [u32(0), 0, 0xdcb00013, 0x32b70002, 0xbeb70013, 0xf36c0002]! {
		write32(base + 48 + u64(i * 8), flags)
	}
	// Native inheritance slots, getters and failable initializers all have null
	// default rel32 fields. This declaration does not synthesize conformances.
	C.memcpy(voidptr(base + 128), c'CodingKey', 10)
	C.memcpy(voidptr(base + 144), c'x', 2)
	if C.mprotect(arena, usize(page), C.PROT_READ) != 0 {
		if C.munmap(arena, usize(page)) != 0 {
			panic('iOS: cannot retire unsealed Swift CodingKey declaration')
		}
		return swift_coding_key_protocol_failure()
	}
	ios_runtime.swift_coding_key_protocol_arena = base
	return base
}

fn swift_coding_key_protocol_stop() {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	ios_runtime.swift_coding_key_protocol_retired = true
	if ios_runtime.swift_coding_key_protocol_arena == 0 { return }
	if C.munmap(voidptr(ios_runtime.swift_coding_key_protocol_arena), usize(C.getpagesize())) != 0 {
		panic('iOS: cannot retire Swift CodingKey declaration')
	}
	ios_runtime.swift_coding_key_protocol_arena = 0
}

fn swift_coding_key_protocol_symbol(symbol string) ?u64 {
	offset := match symbol {
		'_$ss9CodingKeyMp' { 0 }
		'_$ss9CodingKeyTL' { 40 }
		'_$ss9CodingKeyPs28CustomDebugStringConvertibleTb' { 48 }
		'_$ss9CodingKeyPs23CustomStringConvertibleTb' { 56 }
		'_$ss9CodingKeyP11stringValueSSvgTq' { 64 }
		'_$ss9CodingKeyP11stringValuexSgSS_tcfCTq' { 72 }
		'_$ss9CodingKeyP8intValueSiSgvgTq' { 80 }
		'_$ss9CodingKeyP8intValuexSgSi_tcfCTq' { 88 }
		else { return none }
	}
	base := swift_coding_key_protocol_arena_checked() or { return none }
	return base + u64(offset)
}
