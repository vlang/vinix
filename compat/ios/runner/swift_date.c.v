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

fn swift_date_emit(code u64) {
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
}
