// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Calendar.Identifier is an inline one-byte enum. Its 27 cases occupy 0...26;
// the remaining 229 byte values are extra inhabitants for single-payload enums.
fn swift_calendar_identifier_copy(destination u64, source u64, _metadata u64) u64 {
	unsafe { *(&u8(destination)) = *(&u8(source)) }
	return destination
}

fn swift_calendar_identifier_tag(value u64, _metadata u64) u32 {
	return unsafe { u32(*(&u8(value))) }
}

fn swift_calendar_identifier_inject(value u64, tag u32, _metadata u64) {
	unsafe { *(&u8(value)) = u8(tag) }
}

fn swift_calendar_identifier_tag_bytes(empty_cases u32) u32 {
	if empty_cases <= 229 { return 0 }
	// Match native's UInt32 arithmetic, including wraparound at UINT32_MAX.
	count := empty_cases + u32(26)
	return if count >> 8 < 255 { u32(1) } else if count < 0xffff00 {
		u32(2)
	} else { u32(4) }
}

fn swift_calendar_identifier_single_get(value u64, empty_cases u32, _metadata u64) u32 {
	if empty_cases == 0 { return 0 }
	width := swift_calendar_identifier_tag_bytes(empty_cases)
	mut extra := u32(0)
	for i in u32(0) .. width {
		extra |= unsafe { u32(*(&u8(value + 1 + i))) } << (i * 8)
	}
	byte := unsafe { u32(*(&u8(value))) }
	if extra != 0 { return ((extra - 1) << 8) + byte + 230 }
	return if byte < 27 { u32(0) } else { byte - 26 }
}

fn swift_calendar_identifier_single_store(value u64, tag u32, empty_cases u32, _metadata u64) {
	width := swift_calendar_identifier_tag_bytes(empty_cases)
	extra := if tag <= 229 { u32(0) } else { ((tag - 230) >> 8) + 1 }
	for i in u32(0) .. width {
		unsafe { *(&u8(value + 1 + i)) = u8(extra >> (i * 8)) }
	}
	if tag != 0 {
		unsafe { *(&u8(value)) = if tag <= 229 { u8(tag + 26) } else { u8(tag - 230) } }
	}
}

fn swift_calendar_identifier_emit(code u64, data u64) {
	entry := code + 2336
	metadata := data + 1520
	descriptor := data + 1552
	calendar_context := data + 1600
	witness := data + 1680
	write32(entry, 0x58000080) // MetadataResponse { Identifier, Complete } in x0/x1.
	write32(entry + 4, 0xd2800001)
	write32(entry + 8, 0xd65f03c0)
	unsafe {
		*(&u64(entry + 16)) = metadata
		*(&u64(metadata - 8)) = witness
		*(&u64(metadata)) = 0x201
		*(&u64(metadata + 8)) = descriptor
		*(&u64(witness + 64)) = 1
		*(&u64(witness + 72)) = 1
		*(&u64(witness + 88)) = u64(voidptr(swift_calendar_identifier_tag))
		*(&u64(witness + 96)) = u64(voidptr(swift_integer_destroy))
		*(&u64(witness + 104)) = u64(voidptr(swift_calendar_identifier_inject))
	}
	for i, function in [u64(unsafe { voidptr(swift_calendar_identifier_copy) }),
		u64(unsafe { voidptr(swift_integer_destroy) }),
		u64(unsafe { voidptr(swift_calendar_identifier_copy) }),
		u64(unsafe { voidptr(swift_calendar_identifier_copy) }),
		u64(unsafe { voidptr(swift_calendar_identifier_copy) }),
		u64(unsafe { voidptr(swift_calendar_identifier_copy) }),
		u64(unsafe { voidptr(swift_calendar_identifier_single_get) }),
		u64(unsafe { voidptr(swift_calendar_identifier_single_store) })]! {
		unsafe { *(&u64(witness + u64(i * 8))) = function }
	}
	write32(witness + 80, 0x02200000)
	write32(witness + 84, 229)
	// Nongeneric nested enum, with a private Calendar parent context for nominal
	// identity. This context provides no Calendar metadata, fields or constructor.
	write32(descriptor, 0x52)
	swift_protocol_relative(descriptor + 4, calendar_context)
	swift_protocol_relative(descriptor + 8, data + 1648)
	swift_protocol_relative(descriptor + 12, entry)
	write32(descriptor + 24, 27)
	write32(calendar_context, 0x51)
	swift_protocol_relative(calendar_context + 4, data + 64)
	swift_protocol_relative(calendar_context + 8, data + 1632)
	C.memcpy(voidptr(data + 1632), c'Calendar', 9)
	C.memcpy(voidptr(data + 1648), c'Identifier', 11)
}
