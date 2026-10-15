// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn swift_date_decoding_project(value u64) u64 {
	// Decoding only borrows the projected value. Unlike encoding's mutable
	// container, it needs no box uniqueness check or copy-on-write operation.
	return swift_date_encoding_project_checked(value, false) or { panic(err) }
}

fn swift_date_decoding_destroy(value u64) {
	metadata := read64(value + 24)
	witness := read64(metadata - 8)
	if read32(witness + 80) & 0x20000 != 0 {
		// Destroy the owned buffer, not its projected payload. Other retained
		// references to this box may still be reading the value.
		swift_release(read64(value))
	} else {
		swift_date_encoding_destroy(value)
	}
}

fn swift_date_decoding_emit(code u64, data u64) {
	entry := code + 1664
	// Native init(from:) consumes Decoder in x0, writes Date through x8,
	// and forwards an owned error in x21. Do not destroy an uninitialized
	// container when its getter throws, or write a result on either failure.
	for i, op in [u32(0xd10203ff), 0xfd001be8, 0xa90463f9, 0xa9055bf7, 0xa9064ff4,
		0xa9077bfd, 0x9101c3fd, 0xaa1503f6, 0xaa0003f3, 0xaa0803f7, 0xa941e418,
		0x580006b0, 0xd63f0200, // checked Decoder projection
		0x910023e8, 0xaa0003f4, 0xaa1603f5, 0xaa1803e0, 0xaa1903e1, 0xf9401730, 0xd63f0200,
		0xaa1503f6, 0xb5000255, // getter error -> Decoder cleanup
		0xa94267f8, 0x910023e0, 0x58000510, 0xd63f0200, // readonly container projection
		0xaa0003f4, 0xaa1603f5, 0xaa1803e0, 0xaa1903e1, 0xf9401730, 0xd63f0200,
		0x1e604008, 0xaa1503f6, 0x910023e0, 0x580003f0, 0xd63f0200,
		0xb5000056, 0xfd0002e8, // initialize Date only after successful decode
		0xaa1303e0, 0x58000350, 0xd63f0200, 0xaa1603f5,
		0xa9477bfd, 0xa9464ff4, 0xa9455bf7, 0xa94463f9, 0xfd401be8, 0x910203ff, 0xd65f03c0]! {
		write32(entry + u64(i * 4), op)
	}
	unsafe {
		*(&u64(entry + 256)) = u64(voidptr(swift_date_decoding_project))
		*(&u64(entry + 264)) = u64(voidptr(swift_date_decoding_destroy))
	}
	conformance := data + 720
	table := data + 736
	protocol := data + 752
	swift_protocol_relative(conformance, protocol)
	swift_protocol_relative(conformance + 4, data + 464)
	swift_protocol_relative(conformance + 8, table)
	unsafe { *(&u64(table)) = conformance; *(&u64(table + 8)) = entry }
	write32(protocol, 0x30043)
	swift_protocol_relative(protocol + 4, swift_integer_metadata() - 16 + 192)
	swift_protocol_relative(protocol + 8, data + 784)
	write32(protocol + 16, 1)
	write32(protocol + 24, 0x8b5e0002) // Native throwing initializer requirement.
	C.memcpy(voidptr(data + 784), c'Decodable', 10)
}

fn swift_date_decoding_protocol_symbol(symbol string) ?u64 {
	if symbol !in ['_$sSeMp', '_$sSe4fromxs7Decoder_p_tKcfCTq']! { return none }
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return none }
	return swift_foundation_arena() + u64(C.getpagesize()) + if symbol == '_$sSeMp' { u64(752) } else { u64(776) }
}
