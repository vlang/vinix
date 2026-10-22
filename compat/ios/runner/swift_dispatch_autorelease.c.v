// SPDX-License-Identifier: GPL-2.0-or-later
module main

// DispatchQueue.AutoreleaseFrequency is a one-byte enum: inherit, workItem,
// never. Its other 253 byte values are extra inhabitants, not owned payloads.
fn swift_dispatch_autorelease_tag(value u64, _metadata u64) u32 {
	return unsafe { u32(*(&u8(value))) }
}

fn swift_dispatch_autorelease_inject(value u64, tag u32, _metadata u64) {
	unsafe { *(&u8(value)) = u8(tag) }
}

fn swift_dispatch_autorelease_tag_bytes(empty_cases u32) u32 {
	if empty_cases <= 253 { return 0 }
	// Native uses wrapping UInt32 arithmetic, including extreme case counts.
	count := empty_cases + u32(2)
	return if count >> 8 < 255 { u32(1) } else if count < 0xffff00 {
		u32(2)
	} else { u32(4) }
}

fn swift_dispatch_autorelease_single_get(value u64, empty_cases u32, _metadata u64) u32 {
	if empty_cases == 0 { return 0 }
	width := swift_dispatch_autorelease_tag_bytes(empty_cases)
	mut extra := u32(0)
	for i in u32(0) .. width {
		extra |= unsafe { u32(*(&u8(value + 1 + i))) } << (i * 8)
	}
	byte := unsafe { u32(*(&u8(value))) }
	if extra != 0 { return ((extra - 1) << 8) + byte + 254 }
	return if byte < 3 { u32(0) } else { byte - 2 }
}

fn swift_dispatch_autorelease_single_store(value u64, tag u32, empty_cases u32, _metadata u64) {
	width := swift_dispatch_autorelease_tag_bytes(empty_cases)
	extra := if tag <= 253 { u32(0) } else { ((tag - 254) >> 8) + 1 }
	for i in u32(0) .. width {
		unsafe { *(&u8(value + 1 + i)) = u8(extra >> (i * 8)) }
	}
	if tag != 0 {
		unsafe { *(&u8(value)) = if tag <= 253 { u8(tag + 2) } else { u8(tag - 254) } }
	}
}

fn swift_dispatch_autorelease_build(base u64, data u64) {
	accessor := base + 896; metadata := data + 1800
	descriptor := data + 1824; witness := data + 1856
	write32(accessor, 0x58000080) // MetadataResponse { metadata, Complete } in x0/x1.
	write32(accessor + 4, 0xd2800001)
	write32(accessor + 8, 0xd65f03c0)
	unsafe {
		*(&u64(accessor + 16)) = metadata
		*(&u64(metadata - 8)) = witness
		*(&u64(metadata)) = 0x201
		*(&u64(metadata + 8)) = descriptor
		*(&u64(witness + 64)) = 1
		*(&u64(witness + 72)) = 1
		*(&u64(witness + 88)) = u64(voidptr(swift_dispatch_autorelease_tag))
		*(&u64(witness + 96)) = u64(voidptr(swift_integer_destroy))
		*(&u64(witness + 104)) = u64(voidptr(swift_dispatch_autorelease_inject))
	}
	for i, function in [u64(unsafe { voidptr(swift_byte_copy) }),
		u64(unsafe { voidptr(swift_integer_destroy) }),
		u64(unsafe { voidptr(swift_byte_copy) }), u64(unsafe { voidptr(swift_byte_copy) }),
		u64(unsafe { voidptr(swift_byte_copy) }), u64(unsafe { voidptr(swift_byte_copy) }),
		u64(unsafe { voidptr(swift_dispatch_autorelease_single_get) }),
		u64(unsafe { voidptr(swift_dispatch_autorelease_single_store) })]! {
		unsafe { *(&u64(witness + u64(i * 8))) = function }
	}
	write32(witness + 80, 0x02200000) // POD, inline, bitwise-takable enum, alignment 1.
	write32(witness + 84, 253)
	write32(descriptor, 0x52) // Unique nongeneric enum; reflection absent.
	swift_protocol_relative(descriptor + 4, data + 1344) // Dispatch's queue extension.
	swift_protocol_relative(descriptor + 8, data + 1968)
	swift_protocol_relative(descriptor + 12, accessor)
	write32(descriptor + 24, 3) // No payload cases; three empty cases.
	C.memcpy(voidptr(data + 1968), c'AutoreleaseFrequency', 20)
}
