// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Hashable witnesses follow the descriptor and inherited Equatable table:
// hashValue at word 2, hash(into:) at 3, _rawHashValue(seed:) at 4. These
// forwarding entries use the caller's conformance; they do not substitute a
// hashing algorithm or require a concrete Self/RawValue representation.
fn swift_hash_emit(code u64) {
	// RawRepresentable.hashValue's generic arguments are Self metadata in x0,
	// Self Hashable table in x1, RawRepresentable in x2, RawValue Hashable in x3.
	// Borrowed indirect self is x20. Call Self._rawHashValue with seed zero,
	// metadata in x1 and Hashable table in x2; preserve x20 via a tail branch.
	for i, op in [u32(0xf9401030), // ldr x16,[x1,#32]
		0xaa0103e2, 0xaa0003e1, 0xd2800000, 0xd61f0200]! {
		write32(code + u64(i * 4), op)
	}
	// _hashValue(for:): borrowed value address x0, metadata x1, table x2.
	// Move the value into Swift's context register, restore the caller's
	// context after the witness returns, and leave its signed Int result in x0.
	for i, op in [u32(0xa9be7bfd), // stp x29,x30,[sp,#-32]!
		0xa90153f3, // stp x19,x20,[sp,#16]
		0x910003fd, // mov x29,sp
		0xaa0003f4, // mov x20,x0
		0xf9401050, // ldr x16,[x2,#32]
		0xd2800000, // mov x0,#0
		0xd63f0200, // blr x16
		0xa94153f3, 0xa8c27bfd, 0xd65f03c0]! {
		write32(code + 32 + u64(i * 4), op)
	}
	// Protocol dispatch entries keep every argument/context unchanged.
	write32(code + 96, 0xf9400830) // hashValue: ldr x16,[x1,#16]
	write32(code + 100, 0xd61f0200)
	write32(code + 128, 0xf9400c50) // hash(into:): ldr x16,[x2,#24]
	write32(code + 132, 0xd61f0200)
	write32(code + 160, 0xf9401050) // _rawHashValue(seed:): ldr x16,[x2,#32]
	write32(code + 164, 0xd61f0200)
}

fn swift_hash_symbol(symbol string) ?u64 {
	if entry := swift_coding_key_debug_description_symbol(symbol) { return entry }
	if entry := swift_coding_key_description_symbol(symbol) { return entry }
	if entry := swift_encoder_keyed_dispatch_symbol(symbol) { return entry }
	if entry := swift_decoder_keyed_dispatch_symbol(symbol) { return entry }
	if entry := swift_keyed_generic_encoding_symbol(symbol) { return entry }
	if entry := swift_keyed_integer_encoding_symbol(symbol) { return entry }
	if entry := swift_keyed_string_encoding_symbol(symbol) { return entry }
	if entry := swift_keyed_generic_decoding_symbol(symbol) { return entry }
	if entry := swift_keyed_integer_decoding_symbol(symbol) { return entry }
	if entry := swift_keyed_string_decoding_symbol(symbol) { return entry }
	if entry := swift_hash_table_symbol(symbol) { return entry }
	if symbol == '_$sSSSHsWP' {
		return swift_string_hashable_table_checked() or { panic(err) }
	}
	if symbol == '_$sSS4hash4intoys6HasherVz_tF' {
		return u64(unsafe { voidptr(swift_string_hash_into) })
	}
	if entry := swift_raw_symbol(symbol) { return entry }
	if entry := swift_raw_integer_encoding_symbol(symbol) { return entry }
	if entry := swift_raw_integer_decoding_symbol(symbol) { return entry }
	if entry := swift_hasher_symbol(symbol) { return entry }
	offset := match symbol {
		'_$sSYsSHRzSH8RawValueSYRpzrlE04hashB0Sivg' { 0 }
		'_$ss10_hashValue3forSix_tSHRzlF' { 32 }
		'_$sSH9hashValueSivgTj' { 96 }
		'_$sSH4hash4intoys6HasherVz_tFTj' { 128 }
		'_$sSH13_rawHashValue4seedS2i_tFTj' { 160 }
		else { return none }
	}
	return swift_hash_entry(u64(offset))
}

fn swift_hash_entry(offset u64) u64 {
	$if !arm64 { panic('iOS: Swift hashing dispatch requires ARM64') }
	swift_hasher_initialize()
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_hash_code == 0 {
		page := usize(C.getpagesize())
		code := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
			C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if code == unsafe { voidptr(-1) } { panic('iOS: cannot allocate Swift hashing entries') }
		swift_hash_emit(u64(code))
		swift_hasher_emit(u64(code) + 192)
		swift_raw_emit(u64(code) + 640)
		swift_raw_equality_emit(u64(code) + 800)
		swift_raw_integer_encoding_emit(u64(code) + 896)
		swift_raw_integer_decoding_emit(u64(code) + 1152)
		swift_keyed_string_decoding_emit(u64(code) + 1440)
		swift_keyed_integer_decoding_emit(u64(code) + 1488)
		swift_keyed_generic_decoding_emit(u64(code) + 1536)
		swift_keyed_string_encoding_emit(u64(code) + 1600)
		swift_keyed_integer_encoding_emit(u64(code) + 1664)
		swift_keyed_generic_encoding_emit(u64(code) + 1728)
		swift_decoder_keyed_dispatch_emit(u64(code) + 1792)
		swift_coding_key_description_emit(u64(code) + 1824)
		swift_coding_key_debug_description_emit(u64(code) + 1888)
		C.__builtin___clear_cache(code, unsafe { voidptr(u64(code) + 1900) })
		if C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) != 0 {
			C.munmap(code, page)
			panic('iOS: cannot seal Swift hashing entries')
		}
		ios_runtime.swift_hash_code = u64(code)
	}
	return ios_runtime.swift_hash_code + u64(offset)
}

fn swift_hash_stop() {
	// As with ARC/metadata, shutdown has joined workers and drained callbacks.
	if ios_runtime.swift_hash_code != 0 {
		if C.munmap(unsafe { voidptr(ios_runtime.swift_hash_code) }, usize(C.getpagesize())) != 0 {
			panic('iOS: cannot retire Swift hashing entries')
		}
		ios_runtime.swift_hash_code = 0
	}
}
