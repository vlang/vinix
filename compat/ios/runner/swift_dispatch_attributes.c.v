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
}
