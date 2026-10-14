// SPDX-License-Identifier: GPL-2.0-or-later
module main

// ARM64 Optional<OpaquePointer> uses null for nil and otherwise preserves the
// pointer word. Int.init(bitPattern:) returns those bits as signed Swift.Int;
// it does not dereference, validate, retain or truncate the pointer. Measured
// from the installed Swift library, whose initializer is a single RET.
fn swift_integer_pointer_bits(bits u64) i64 { return i64(bits) }

// Int is a frozen, inline POD word. All copy/take witnesses are bit copies;
// neither destruction nor assignment has ownership work to perform.
fn swift_integer_copy(destination u64, source u64, metadata u64) u64 {
	unsafe { *(&u64(destination)) = *(&u64(source)) }
	return destination
}
fn swift_integer_destroy(value u64, metadata u64) {}
fn swift_integer_enum_get(value u64, empty_cases u32, metadata u64) u32 {
	if empty_cases == 0 || unsafe { *(&u8(value + 8)) } == 0 { return 0 }
	return unsafe { *(&u32(value)) } + 1
}
fn swift_integer_enum_store(value u64, which_case u32, empty_cases u32, metadata u64) {
	if empty_cases == 0 { return }
	unsafe { *(&u8(value + 8)) = if which_case == 0 { u8(0) } else { u8(1) } }
	if which_case != 0 { unsafe { *(&u64(value)) = u64(which_case - 1) } }
}
fn swift_integer_equal(left u64, right u64) bool { return left == right }
fn swift_integer_equal_indirect(left u64, right u64, metadata u64, table u64) bool {
	return read64(left) == read64(right)
}
fn swift_integer_hash_value(value u64) i64 { return swift_hasher_hash_word(0, value) }
fn swift_integer_hash_into(mut state SwiftHasher, value u64) { swift_hasher_word(mut state, value) }

// The three instance witnesses borrow indirect Self in x20. Public Int
// methods pass its bits directly. Tail calls preserve the Swift context and
// use the same process seeds and SipHash state machine as generic Hasher.
fn swift_integer_witness_emit(code u64, body u64, getter bool) {
	write32(code, if getter { u32(0xf9400280) } else { u32(0xf9400281) }) // ldr x0/x1,[x20]
	write32(code + 4, 0x58000070)
	write32(code + 8, 0xd61f0200)
	write32(code + 12, 0xd503201f)
	unsafe { *(&u64(code + 16)) = body }
}

fn swift_integer_metadata() u64 {
	swift_hasher_initialize()
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	page := u64(C.getpagesize())
	if ios_runtime.swift_integer_arena != 0 { return ios_runtime.swift_integer_arena + page + 16 }
	$if !arm64 { panic('iOS: Swift Int witnesses require ARM64') }
	arena := C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == unsafe { voidptr(-1) } { panic('iOS: cannot allocate Swift Int metadata') }
	base := u64(arena)
	data := base + page
	metadata := data + 16
	witness := data + 64
	descriptor := data + 160
	module_descriptor := data + 192
	hash_table := data + 256
	equal_table := data + 296
	hash_protocol := data + 352
	equal_protocol := data + 432
	write32(base, 0x58000080) // MetadataResponse in x0/x1, always Complete.
	write32(base + 4, 0xd2800001)
	write32(base + 8, 0xd65f03c0)
	unsafe {
		*(&u64(base + 16)) = metadata
		*(&u64(metadata - 8)) = witness
		*(&u64(metadata)) = 0x200
		*(&u64(metadata + 8)) = descriptor
	}
	for i, function in [u64(unsafe { voidptr(swift_integer_copy) }),
		u64(unsafe { voidptr(swift_integer_destroy) }), u64(unsafe { voidptr(swift_integer_copy) }),
		u64(unsafe { voidptr(swift_integer_copy) }), u64(unsafe { voidptr(swift_integer_copy) }),
		u64(unsafe { voidptr(swift_integer_copy) }), u64(unsafe { voidptr(swift_integer_enum_get) }),
		u64(unsafe { voidptr(swift_integer_enum_store) })]! { unsafe { *(&u64(witness + u64(i * 8))) = function } }
	unsafe { *(&u64(witness + 64)) = 8; *(&u64(witness + 72)) = 8 }
	write32(witness + 80, 7) // POD, inline, bitwise-takable, alignment 8, no extra inhabitants.
	write32(descriptor, 0x51)
	swift_protocol_relative(descriptor + 4, module_descriptor)
	swift_protocol_relative(descriptor + 8, data + 216)
	swift_protocol_relative(descriptor + 12, base)
	write32(descriptor + 20, 1)
	write32(descriptor + 24, 2)
	swift_protocol_relative(module_descriptor + 8, data + 208)
	C.memcpy(unsafe { voidptr(data + 208) }, c'Swift', 6)
	C.memcpy(unsafe { voidptr(data + 216) }, c'Int', 4)
	for i, protocol in [hash_protocol, equal_protocol]! {
		conformance := data + 320 + u64(i * 16)
		table := if i == 0 { hash_table } else { equal_table }
		name := data + 480 + u64(i * 16)
		unsafe { *(&u64(table)) = conformance }
		swift_protocol_relative(conformance, protocol)
		swift_protocol_relative(conformance + 4, descriptor)
		swift_protocol_relative(conformance + 8, table)
		write32(protocol, 0x30043)
		swift_protocol_relative(protocol + 4, module_descriptor)
		swift_protocol_relative(protocol + 8, name)
		write32(protocol + 16, if i == 0 { u32(4) } else { u32(1) })
		C.memcpy(unsafe { voidptr(name) }, if i == 0 { c'Hashable' } else { c'Equatable' }, 9)
	}
	// Hashable's trailing generic signature precedes its four requirements:
	// Self (mangled "x") conforms to Equatable. The first table requirement
	// is the inherited Equatable table, followed by hashValue/hash/rawHash.
	write32(hash_protocol + 12, 1)
	write32(hash_protocol + 24, 0x80) // Protocol requirement, key argument.
	swift_protocol_relative(hash_protocol + 28, data + 512)
	swift_protocol_relative(hash_protocol + 32, equal_protocol)
	C.memcpy(unsafe { voidptr(data + 512) }, c'x', 2)
	for i, flags in [u32(0), 0x026b0013, 0x3d890011, 0xc41a0011]! {
		write32(hash_protocol + 36 + u64(i * 8), flags)
	}
	write32(equal_protocol + 24, 0x97eb0001) // Static == method; native discriminator.
	swift_protocol_relative(hash_protocol + 64, base + 160) // Default rawHashValue.
	unsafe {
		*(&u64(hash_table + 8)) = equal_table
		*(&u64(hash_table + 16)) = base + 32
		*(&u64(hash_table + 24)) = base + 64
		*(&u64(hash_table + 32)) = base + 96
		*(&u64(equal_table + 8)) = u64(voidptr(swift_integer_equal_indirect))
	}
	swift_integer_witness_emit(base + 32, u64(unsafe { voidptr(swift_integer_hash_value) }), true)
	swift_integer_witness_emit(base + 64, u64(unsafe { voidptr(swift_integer_hash_into) }), false)
	swift_integer_witness_emit(base + 96, u64(unsafe { voidptr(swift_hasher_hash_word) }), false)
	write32(base + 128, 0xf9400470) // Equatable dispatch: ldr x16,[x3,#8]; br.
	write32(base + 132, 0xd61f0200)
	swift_hasher_default_emit(base + 160)
	swift_vararg_emit(base, data)
	swift_byte_metadata_emit(base, data)
	C.__builtin___clear_cache(arena, unsafe { voidptr(base + 408) })
	if C.mprotect(arena, usize(page), C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(unsafe { voidptr(data) }, usize(page), C.PROT_READ) != 0 {
		C.munmap(arena, usize(page * 2))
		panic('iOS: cannot seal Swift Int metadata')
	}
	ios_runtime.swift_integer_arena = base
	return metadata
}
fn swift_integer_stop() {
	if ios_runtime.swift_integer_arena == 0 { return }
	if C.munmap(unsafe { voidptr(ios_runtime.swift_integer_arena) }, usize(C.getpagesize()) * 2) != 0 {
		panic('iOS: cannot retire Swift Int metadata')
	}
	ios_runtime.swift_integer_arena = 0
}

fn swift_integer_symbol(symbol string) ?u64 {
	if address := swift_byte_symbol(symbol) { return address }
	function := match symbol {
		'_$sSi10bitPatternSis13OpaquePointerVSg_tcfC' { u64(unsafe { voidptr(swift_integer_pointer_bits) }) }
		'_$sSi2eeoiySbSi_SitFZ' { u64(unsafe { voidptr(swift_integer_equal) }) }
		'_$sSi9hashValueSivg' { u64(unsafe { voidptr(swift_integer_hash_value) }) }
		'_$sSi4hash4intoys6HasherVz_tF' { u64(unsafe { voidptr(swift_integer_hash_into) }) }
		'_$sSi13_rawHashValue4seedS2i_tF' { u64(unsafe { voidptr(swift_hasher_hash_word) }) }
		'_$sSi16_cVarArgEncodingSaySiGvg' { u64(unsafe { voidptr(swift_integer_vararg) }) }
		else { u64(0) }
	}
	if function != 0 {
		if symbol != '_$sSi10bitPatternSis13OpaquePointerVSg_tcfC' { swift_hasher_initialize() }
		return function
	}
	offset := match symbol {
		// Native Builtin.Int64 and Int share this exact POD value-witness
		// table. Export the sealed table, preserving Int's metadata identity.
		'_$sBi64_WV' { 64 }
		'_$sSiN' { 16 }
		'_$sSiMn' { 160 }
		'_$sSiSHsWP' { 256 }
		'_$sSiSQsWP' { 296 }
		'_$sSiSHsMc' { 320 }
		'_$sSiSQsMc' { 336 }
		'_$sSHMp' { 352 }
		'_$sSHTL' { 380 }
		// Hashable's first requirement is its inherited Equatable conformance.
		'_$sSHSQTb' { 388 }
		'_$sSH9hashValueSivgTq' { 396 }
		'_$sSH4hash4intoys6HasherVz_tFTq' { 404 }
		'_$sSH13_rawHashValue4seedS2i_tFTq' { 412 }
		'_$sSQMp' { 432 }
		'_$sSQTL' { 448 }
		'_$sSQ2eeoiySbx_xtFZTq' { 456 }
		'_$sSis7CVarArgsWP' { 528 }
		'_$sSis7CVarArgsMc' { 544 }
		'_$ss7CVarArgMp' { 560 }
		'_$ss7CVarArgTL' { 576 }
		'_$ss7CVarArgP05_cVarB8EncodingSaySiGvgTq' { 584 }
		'_$sSiMa', '_$sSQ2eeoiySbx_xtFZTj', '_$ss7CVarArgP05_cVarB8EncodingSaySiGvgTj' { 0 }
		else { return none }
	}
	metadata := swift_integer_metadata()
	if symbol == '_$sSiMa' { return ios_runtime.swift_integer_arena }
	if symbol == '_$sSQ2eeoiySbx_xtFZTj' { return ios_runtime.swift_integer_arena + 128 }
	if symbol == '_$ss7CVarArgP05_cVarB8EncodingSaySiGvgTj' { return ios_runtime.swift_integer_arena + 320 }
	return metadata - 16 + u64(offset)
}
