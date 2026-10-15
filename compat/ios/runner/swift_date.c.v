// SPDX-License-Identifier: GPL-2.0-or-later
module main

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
}
