// SPDX-License-Identifier: GPL-2.0-or-later
module main

type SwiftDateEncodingDestroy = fn (u64, u64)

// Existential records, metadata and callback tables are borrowed readable
// image spans. The encoder may be boxed; the returned mutable container must
// fit the inline buffer. General box uniqueness/copying is a separate profile.
fn swift_date_encoding_project_checked(value u64, mutable bool) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired || value == 0 || value & 7 != 0 {
		return error('iOS: Date encoding requires an active runtime and aligned existential')
	}
	metadata := read64(value + 24)
	if metadata < 8 || metadata & 7 != 0 { return error('iOS: invalid Date encoder value metadata') }
	witness := read64(metadata - 8)
	if witness == 0 || witness & 7 != 0 { return error('iOS: invalid Date encoder value witnesses') }
	flags := read32(witness + 80)
	mask := u64(flags & 255)
	size := read64(witness + 64)
	stride := read64(witness + 72)
	if mask & (mask + 1) != 0 || stride < size || stride & mask != 0 || flags & 0x00400000 != 0 {
		return error('iOS: unsupported Date encoder value layout')
	}
	table := read64(value + 32)
	if table == 0 || table & 7 != 0 || read64(table + 40) == 0 || read64(witness + 8) == 0 {
		return error('iOS: incomplete Date encoder callbacks')
	}
	if flags & 0x20000 == 0 {
		if size > 24 || mask > 7 { return error('iOS: invalid inline Date encoder value') }
		return value
	}
	if mutable { return error('iOS: boxed mutable Date encoding containers are not implemented') }
	owner := read64(value)
	offset := (16 + mask) & ~mask
	if owner == 0 || owner > ~u64(0) - offset { return error('iOS: invalid boxed Date encoder') }
	return owner + offset
}

fn swift_date_encoding_encoder(value u64) u64 {
	return swift_date_encoding_project_checked(value, false) or { panic(err) }
}

fn swift_date_encoding_container(value u64) u64 {
	return swift_date_encoding_project_checked(value, true) or { panic(err) }
}

fn swift_date_encoding_destroy(value u64) {
	metadata := read64(value + 24)
	witness := read64(metadata - 8)
	destroy := unsafe { SwiftDateEncodingDestroy(voidptr(read64(witness + 8))) }
	destroy(value, metadata)
}

fn swift_date_encoding_emit(code u64, data u64) {
	entry := code + 1360
	// Native Date.encode(to:) borrows Encoder in x0 and Date in x20. It owns
	// the single-value container, calls its Double witness, then destroys it
	// on both success and failure while forwarding the owned x21 error.
	for i, op in [u32(0xd101c3ff), 0xfd001be8, 0xa9045bf7, 0xa9054ff4, 0xa9067bfd,
		0x910183fd, 0xaa1503f3, 0xfd400288, 0xa941dc16,
		0x580006f0, 0xd63f0200, // checked borrowed Encoder projection
		0x910023e8, 0xaa0003f4, 0xaa1603e0, 0xaa1703e1, 0xf94016f0, 0xd63f0200,
		0xa9425ff6, 0x910023e0, 0x580005f0, 0xd63f0200, // owned inline container
		0x4ea81d00, 0xaa0003f4, 0xaa1303f5, 0xaa1603e0, 0xaa1703e1, 0xf94016f0, 0xd63f0200,
		0xaa1503f3, 0x910023e0, 0x580004d0, 0xd63f0200,
		0xaa1303f5, 0xa9467bfd, 0xa9454ff4, 0xa9445bf7, 0xfd401be8, 0x9101c3ff, 0xd65f03c0]! {
		write32(entry + u64(i * 4), op)
	}
	unsafe {
		*(&u64(entry + 256)) = u64(voidptr(swift_date_encoding_encoder))
		*(&u64(entry + 264)) = u64(voidptr(swift_date_encoding_container))
		*(&u64(entry + 272)) = u64(voidptr(swift_date_encoding_destroy))
	}
	conformance := data + 608
	table := data + 624
	protocol := data + 640
	// Already-specialized concrete witnesses replace native resilient/generic
	// instantiation. The nominal Date identity and Swift protocol stay distinct.
	swift_protocol_relative(conformance, protocol)
	swift_protocol_relative(conformance + 4, data + 464)
	swift_protocol_relative(conformance + 8, table)
	unsafe { *(&u64(table)) = conformance; *(&u64(table + 8)) = entry }
	write32(protocol, 0x30043)
	swift_protocol_relative(protocol + 4, swift_integer_metadata() - 16 + 192)
	swift_protocol_relative(protocol + 8, data + 672)
	write32(protocol + 16, 1)
	write32(protocol + 24, 0x69460011) // Native throwing instance requirement.
	C.memcpy(voidptr(data + 672), c'Encodable', 10)
}

fn swift_date_encoding_protocol_symbol(symbol string) ?u64 {
	if symbol !in ['_$sSEMp', '_$sSE6encode2toys7Encoder_p_tKFTq']! { return none }
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return none }
	return swift_foundation_arena() + u64(C.getpagesize()) + if symbol == '_$sSEMp' { u64(640) } else { u64(664) }
}
