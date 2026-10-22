// SPDX-License-Identifier: GPL-2.0-or-later
module main

// DispatchQueue.Attributes is a UInt64 OptionSet nested in Dispatch's extension
// of the imported OS_dispatch_queue class. Keep that nominal context distinct
// from DispatchWorkItemFlags even though their POD8 value witnesses agree.
fn swift_dispatch_attributes_build(base u64, data u64) {
	accessor := base + 832; metadata := data + 1280
	descriptor := data + 1312; extension := data + 1344
	write32(accessor, 0x58000080)
	write32(accessor + 4, 0xd2800001)
	write32(accessor + 8, 0xd65f03c0)
	unsafe {
		*(&u64(accessor + 16)) = metadata
		*(&u64(metadata - 8)) = data + 64 // Shared ownership-free POD8 witnesses.
		*(&u64(metadata)) = 0x200
		*(&u64(metadata + 8)) = descriptor
	}
	// mmap supplies rawValue's zero field offset and absent reflection record.
	// Native initialization extensions are deliberately not advertised.
	write32(descriptor, 0x51)
	swift_protocol_relative(descriptor + 4, extension)
	swift_protocol_relative(descriptor + 8, data + 1376)
	swift_protocol_relative(descriptor + 12, accessor)
	write32(descriptor + 20, 1); write32(descriptor + 24, 2)
	write32(extension, 0x41) // Unique nongeneric extension context.
	swift_protocol_relative(extension + 4, data + 192) // Dispatch module.
	swift_protocol_relative(extension + 8, data + 1392)
	C.memcpy(voidptr(data + 1376), c'Attributes', 11)
	C.memcpy(voidptr(data + 1392), c'So17OS_dispatch_queueC', 22)
	// Share the canonical protocol identities and scalar bodies, while keeping
	// each conformance's nominal descriptor and associated Self independent.
	table := data + 1504; literal_table := data + 1696; equal_table := data + 1728
	integer_data := ios_runtime.swift_integer_arena + u64(C.getpagesize())
	for i, protocol in [data + 576, data + 800, integer_data + 432]! {
		record := data + 1440 + u64(i * 16)
		pattern := [table, literal_table, equal_table]![i]
		swift_protocol_relative(record, protocol)
		swift_protocol_relative(record + 4, descriptor)
		swift_protocol_relative(record + 8, pattern)
		unsafe { *(&u64(pattern)) = record }
	}
	unsafe {
		*(&u64(table + 8)) = equal_table; *(&u64(table + 16)) = literal_table; *(&u64(table + 24)) = metadata
		*(&u64(equal_table + 8)) = read64(data + 552)
		*(&u64(literal_table + 8)) = metadata; *(&u64(literal_table + 16)) = base + 864
		for slot in 4..22 { *(&u64(table + u64(slot * 8))) = read64(data + 320 + u64(slot * 8)) }
	}
	swift_dispatch_bridge(base + 864, 0xaa0803e1, 0xd503201f, u64(unsafe { voidptr(swift_dispatch_attributes_literal) }))
}
