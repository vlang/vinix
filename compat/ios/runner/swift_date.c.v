// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn swift_date_now() f64 {
	timestamp := u64(C.__builtin_alloca(16))
	if darwin_clock_gettime(0, voidptr(timestamp)) != 0 {
		panic('iOS: cannot read Swift Date realtime clock')
	}
	// Native subtracts the 2001 epoch before adding the nanosecond fraction.
	seconds := f64(unsafe { *(&i64(timestamp)) }) - 978307200.0
	fraction := f64(unsafe { *(&i64(timestamp + 8)) }) * 1e-9
	return seconds + fraction
}

// These witnesses copy bits, including signaling NaNs, without floating
// conversion or ownership work. memmove permits unaligned spans and aliases.
fn swift_date_copy(destination u64, source u64, _metadata u64) u64 {
	C.memmove(voidptr(destination), voidptr(source), 8)
	return destination
}

fn swift_date_enum_get(value u64, empty_cases u32, _metadata u64) u32 {
	if empty_cases == 0 || unsafe { *(&u8(value + 8)) } == 0 { return 0 }
	mut tag := u32(0)
	C.memcpy(unsafe { &tag }, voidptr(value), 4)
	return tag + 1
}

fn swift_date_enum_store(value u64, tag u32, empty_cases u32, _metadata u64) {
	// Native writes a nonzero tag's payload even when no tag byte exists.
	if tag != 0 {
		payload := u64(tag - 1)
		C.memcpy(voidptr(value), unsafe { &payload }, 8)
	}
	if empty_cases != 0 {
		unsafe { *(&u8(value + 8)) = if tag == 0 { u8(0) } else { u8(1) } }
	}
}

fn swift_date_emit(code u64, data u64) {
	// Date is resilient. Native distantPast stores the eight-byte Double
	// representation through x8, without reading arguments or touching ARC.
	write32(code + 1152, 0x58000089) // ldr x9, literal at +16
	write32(code + 1156, 0xf9000109) // str x9, [x8]
	write32(code + 1160, 0xd65f03c0) // ret
	unsafe { *(&u64(code + 1168)) = u64(0xc22d63c8c5000000) } // -63114076800.0
	// timeIntervalSince borrows another resilient Date in x0 and Self in
	// x20. Native returns Self - other directly in d0, preserving IEEE values.
	for i, op in [u32(0xfd400000), 0xfd400281, 0x1e603820, 0xd65f03c0]! {
		write32(code + 1184 + u64(i * 4), op)
	}
	// Static equality borrows two Date words in x0/x1. Floating comparison
	// makes signed zeros equal and NaNs unequal; return a canonical Bool in w0.
	for i, op in [u32(0xfd400000), 0xfd400021, 0x1e612000, 0x1a9f17e0, 0xd65f03c0]! {
		write32(code + 1216 + u64(i * 4), op)
	}
	// Date() uses the same indirect x8 result as distantPast. Keep that
	// address in a saved register while the realtime clock helper returns d0.
	for i, op in [u32(0xa9bf7bf3), 0xaa0803f3, 0x580000d0, 0xd63f0200, 0xfd000260, 0xa8c17bf3,
		0xd65f03c0]! {
		write32(code + 1248 + u64(i * 4), op)
	}
	unsafe { *(&u64(code + 1280)) = u64(voidptr(swift_date_now)) }
	entry := code + 1312
	metadata := data + 432
	descriptor := data + 464
	witness := data + 512
	write32(entry, 0x58000080) // MetadataResponse { Date, Complete } in x0/x1.
	write32(entry + 4, 0xd2800001)
	write32(entry + 8, 0xd65f03c0)
	unsafe {
		*(&u64(entry + 16)) = metadata
		*(&u64(metadata - 8)) = witness
		*(&u64(metadata)) = 0x200
		*(&u64(metadata + 8)) = descriptor
		*(&u64(witness + 64)) = 8
		*(&u64(witness + 72)) = 8
	}
	write32(metadata + 16, 0)
	// Nongeneric nominal lookup with explicit witnesses; omit Apple's trailing
	// initialization extensions and field reflection records from this profile.
	write32(descriptor, 0x51)
	swift_protocol_relative(descriptor + 4, data + 64) // Foundation module.
	swift_protocol_relative(descriptor + 8, data + 496)
	swift_protocol_relative(descriptor + 12, entry)
	write32(descriptor + 20, 1)
	write32(descriptor + 24, 2)
	C.memcpy(voidptr(data + 496), c'Date', 5)
	for i, function in [u64(unsafe { voidptr(swift_date_copy) }),
		u64(unsafe { voidptr(swift_integer_destroy) }), u64(unsafe { voidptr(swift_date_copy) }),
		u64(unsafe { voidptr(swift_date_copy) }), u64(unsafe { voidptr(swift_date_copy) }),
		u64(unsafe { voidptr(swift_date_copy) }), u64(unsafe { voidptr(swift_date_enum_get) }),
		u64(unsafe { voidptr(swift_date_enum_store) })]! {
		unsafe { *(&u64(witness + u64(i * 8))) = function }
	}
	write32(witness + 80, 0x02000007) // Native inline POD flags, alignment eight.
	write32(witness + 84, 0) // Every Double bit pattern is a valid payload.
	swift_date_encoding_emit(code, data)
}
