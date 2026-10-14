// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftAssociatedMetadata {
	metadata u64
	state    u64
}

type SwiftRawGetterCall = fn (u64, u64, u64, u64, u64)
type SwiftRawHashCall = fn (u64, u64, u64, u64, u64)
type SwiftRawDestroy = fn (u64, u64)

// Swift 6's associated-type slot is data, not an accessor function: either
// complete metadata or a low-bit-tagged mangled name. Use acquire/release
// publication so concurrent lookups never call a data pointer as code.
fn swift_associated_type(_request u64, table u64, _self_metadata u64, base u64, requirement u64) SwiftAssociatedMetadata {
	if table == 0 || base == 0 || requirement <= base || (requirement - base) % 8 != 0
		|| requirement - base > 8 * 1048576 || unsafe { *(&u32(requirement)) } & 15 != 7 {
		panic('iOS: invalid Swift associated-type requirement')
	}
	slot := unsafe { &u64(table + requirement - base) }
	witness := C.ios_load_pointer(slot)
	if witness == 0 { panic('iOS: missing Swift associated-type metadata') }
	if witness & 1 == 0 { return SwiftAssociatedMetadata{ metadata: witness } }
	mut name := witness & ~u64(1)
	if unsafe { *(&u8(name)) } == 0xff { name++ }
	// String is the concrete type whose metadata this runtime supplies. Do
	// not invent metadata for arbitrary symbolic/generic mangled type names.
	if unsafe { *(&u8(name)) } != `S` || unsafe { *(&u8(name + 1)) } != `S`
		|| unsafe { *(&u8(name + 2)) } != 0 {
		panic('iOS: Swift associated-type mangled name is not implemented')
	}
	metadata := swift_string_metadata()
	C.ios_store_pointer(slot, metadata)
	return SwiftAssociatedMetadata{ metadata: metadata }
}

fn swift_raw_hash_into(hasher u64, metadata u64, _self_hashable u64, raw_table u64, raw_hashable u64, receiver u64) {
	protocol := swift_string_metadata() - 16 + 448
	raw_metadata := swift_associated_type(0, raw_table, metadata, protocol + 16, protocol + 24).metadata
	witness := read64(raw_metadata - 8)
	size := read64(witness + 64)
	if size > u64(0x7fffffffffffffff) - 15 { panic('iOS: invalid Swift RawValue size') }
	// Native Swift rounds its dynamic stack temporary to 16 bytes. alloca is
	// scoped to this invocation; callbacks cannot retain this borrowed address.
	value := u64(C.__builtin_alloca(usize((size + 15) & ~u64(15))))
	getter := unsafe { SwiftRawGetterCall(voidptr(swift_hash_entry(672))) }
	into := unsafe { SwiftRawHashCall(voidptr(swift_hash_entry(736))) }
	getter(read64(raw_table + 24), value, metadata, raw_table, receiver)
	into(hasher, raw_metadata, raw_hashable, value, read64(raw_hashable + 24))
	// Getter produced an owned RawValue, consumed here exactly once even for
	// non-POD/reference values. Self stays borrowed throughout all three calls.
	destroy := unsafe { SwiftRawDestroy(voidptr(read64(witness + 8))) }
	destroy(value, raw_metadata)
}

fn swift_raw_emit(code u64) {
	// Default: Hasher x0, Self metadata x1, Self Hashable x2,
	// RawRepresentable x3, RawValue Hashable x4, indirect Self context x20.
	write32(code, 0xaa1403e5) // mov x5,x20
	write32(code + 4, 0x58000070)
	write32(code + 8, 0xd61f0200)
	write32(code + 12, 0xd503201f)
	unsafe { *(&u64(code + 16)) = u64(voidptr(swift_raw_hash_into)) }
	// Ordinary V call -> Swift rawValue getter. It always uses an indirect
	// result in x8, including small RawValue types. Preserve caller's context.
	for i, op in [u32(0xa9be7bfd), 0xa90153f3, 0x910003fd, 0xaa0003f0, 0xaa0103e8, 0xaa0203e0,
		0xaa0303e1, 0xaa0403f4, 0xd63f0200, 0xa94153f3, 0xa8c27bfd, 0xd65f03c0]! {
		write32(code + 32 + u64(i * 4), op)
	}
	// Ordinary V call -> RawValue.hash(into:), with the temporary as self.
	for i, op in [u32(0xa9be7bfd), 0xa90153f3, 0x910003fd, 0xaa0303f4, 0xaa0403f0, 0xd63f0200,
		0xa94153f3, 0xa8c27bfd, 0xd65f03c0]! {
		write32(code + 96 + u64(i * 4), op)
	}
}

fn swift_raw_protocol_emit(data u64) {
	protocol := data + 448
	write32(protocol, 0x30043)
	swift_protocol_relative(protocol + 4, data + 192)
	swift_protocol_relative(protocol + 8, data + 512)
	write32(protocol + 16, 3)
	swift_protocol_relative(protocol + 20, data + 536)
	// Associated RawValue, init(rawValue:), rawValue getter. Retain native
	// requirement discriminators for descriptor consumers; Vinix uses ARM64
	// pointers without ARM64e authentication instructions.
	write32(protocol + 24, 0x06170007)
	write32(protocol + 32, 0x3b260002)
	write32(protocol + 40, 0x3d880013)
	C.memcpy(unsafe { voidptr(data + 512) }, c'RawRepresentable', 17)
	C.memcpy(unsafe { voidptr(data + 536) }, c'RawValue', 9)
}

fn swift_raw_symbol(symbol string) ?u64 {
	return match symbol {
		'_$ss2eeoiySbx_xtSYRzSQ8RawValueRpzlF' { u64(unsafe { voidptr(swift_raw_equal) }) }
		'_$sSYsSHRzSH8RawValueSYRpzrlE4hash4intoys6HasherVz_tF' { swift_hash_entry(640) }
		'_$sSYMp' { swift_string_metadata() - 16 + 448 }
		'_$sSYTL' { swift_string_metadata() - 16 + 464 }
		'_$s8RawValueSYTl' { swift_string_metadata() - 16 + 472 }
		'_$sSY8rawValuexSg03RawB0Qz_tcfCTq' { swift_string_metadata() - 16 + 480 }
		'_$sSY8rawValue03RawB0QzvgTq' { swift_string_metadata() - 16 + 488 }
		'_swift_getAssociatedTypeWitness' { u64(unsafe { voidptr(swift_associated_type) }) }
		else { none }
	}
}
