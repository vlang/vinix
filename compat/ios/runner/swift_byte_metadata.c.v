// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Int8 and UInt8 have distinct canonical nominal metadata but share an inline
// one-byte POD VWT. Copy/take never widens, signs, retains or reads neighbours.
fn swift_byte_copy(destination u64, source u64, _metadata u64) u64 {
	unsafe { *(&u8(destination)) = *(&u8(source)) }
	return destination
}
// Preserve the measured native UInt32 arithmetic, including cases+255 wrap.
// The tag is stored after the payload, with unaligned little-endian bytes.
fn swift_byte_tag_width(empty_cases u32) u32 {
	if empty_cases == 0 { return 0 }
	rounded := empty_cases + u32(255)
	if rounded < 256 { return 0 }
	if rounded >> 8 < 255 { return 1 }
	return if rounded < 0x00ffff00 { u32(2) } else { u32(4) }
}
fn swift_byte_enum_get(value u64, empty_cases u32, _metadata u64) u32 {
	width := swift_byte_tag_width(empty_cases)
	if width == 0 { return 0 }
	mut tag := u32(0)
	for i in u32(0) .. width { tag |= u32(unsafe { *(&u8(value + 1 + i)) }) << (i * 8) }
	if tag == 0 { return 0 }
	return (tag << 8 | u32(unsafe { *(&u8(value)) })) - u32(255)
}
fn swift_byte_enum_store(value u64, which_case u32, empty_cases u32, _metadata u64) {
	width := swift_byte_tag_width(empty_cases)
	mut tag := u32(0)
	if which_case != 0 {
		bits := which_case - u32(1)
		unsafe { *(&u8(value)) = u8(bits) }
		tag = (bits >> 8) + u32(1)
	}
	for i in u32(0) .. width { unsafe { *(&u8(value + 1 + i)) = u8(tag >> (i * 8)) } }
}

fn swift_byte_metadata_emit(base u64, data u64) {
	witness := data + 768
	for i, function in [u64(unsafe { voidptr(swift_byte_copy) }),
		u64(unsafe { voidptr(swift_integer_destroy) }),u64(unsafe { voidptr(swift_byte_copy) }),
		u64(unsafe { voidptr(swift_byte_copy) }),u64(unsafe { voidptr(swift_byte_copy) }),
		u64(unsafe { voidptr(swift_byte_copy) }),u64(unsafe { voidptr(swift_byte_enum_get) }),
		u64(unsafe { voidptr(swift_byte_enum_store) })]! { unsafe { *(&u64(witness + u64(i * 8))) = function } }
	unsafe { *(&u64(witness + 64)) = 1;*(&u64(witness + 72)) = 1 }
	// Flags/extra inhabitants remain zero: POD, alignment1, inline and complete.
	for i in 0 .. 2 {
		metadata := data + 648 + u64(i * 32)
		descriptor := data + 704 + u64(i * 32)
		name := data + 864 + u64(i * 16)
		accessor := base + 352 + u64(i * 32)
		unsafe { *(&u64(metadata - 8)) = witness;*(&u64(metadata)) = 0x200;*(&u64(metadata + 8)) = descriptor }
		// The single stored byte's field offset at metadata word2 remains zero.
		write32(descriptor,0x51)
		swift_protocol_relative(descriptor + 4,data + 192)
		swift_protocol_relative(descriptor + 8,name)
		swift_protocol_relative(descriptor + 12,accessor)
		write32(descriptor + 20,1);write32(descriptor + 24,2)
		C.memcpy(unsafe { voidptr(name) },if i == 0 { c'Int8' } else { c'UInt8' },if i == 0 { usize(5) } else { usize(6) })
		// Every request returns the same complete MetadataResponse in x0/x1.
		write32(accessor,0x58000080);write32(accessor + 4,0xd2800001)
		write32(accessor + 8,0xd65f03c0);write32(accessor + 12,0xd503201f)
		unsafe { *(&u64(accessor + 16)) = metadata }
	}
}
fn swift_byte_symbol(symbol string) ?u64 {
	offset := match symbol {
		'_$ss4Int8VN' { 648 }
		'_$ss5UInt8VN' { 680 }
		'_$ss4Int8VMn' { 704 }
		'_$ss5UInt8VMn' { 736 }
		'_$sBi8_WV' { 768 }
		'_$ss4Int8VMa', '_$ss5UInt8VMa' { 0 }
		else { return none }
	}
	data := swift_integer_metadata() - 16
	if symbol == '_$ss4Int8VMa' { return ios_runtime.swift_integer_arena + 352 }
	if symbol == '_$ss5UInt8VMa' { return ios_runtime.swift_integer_arena + 384 }
	return data + u64(offset)
}
