// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Encodable and Decodable have the same two conditional requirements and
// private witness layout. Their descriptors, caches and method entries remain
// distinct. Neither descriptor's table pattern is a specialized witness table.
fn swift_dictionary_codable_emit(code u64, data u64, protocol u64, offset u64, entry_offset u64, cache_offset u64, handler u64) {
	entry := code + entry_offset
	write32(entry, 0x58000050)
	write32(entry + 4, 0xd61f0200)
	unsafe { *(&u64(voidptr(entry + 8))) = handler }
	descriptor := data + offset
	swift_protocol_relative(descriptor, protocol)
	swift_protocol_relative(descriptor + 4, data + 160)
	swift_protocol_relative(descriptor + 8, descriptor + 64)
	write32(descriptor + 12, 0x20200) // Two conditional requirements, generic table.
	for i in 0 .. 2 {
		requirement := descriptor + 16 + u64(i * 12)
		write32(requirement, 0x80) // Key argument, protocol conformance.
		swift_protocol_relative(requirement + 4, descriptor + 96 + u64(i * 2))
		swift_protocol_relative(requirement + 8, protocol)
	}
	C.memcpy(voidptr(descriptor + 96), c'x', 2)
	C.memcpy(voidptr(descriptor + 98), c'q_', 3)
	write32(descriptor + 40, 0x50002) // Two pattern words, two private words, requires instantiation.
	// No instantiator: the runtime copies conditional witnesses in reverse
	// order immediately before the table address point, as on native Swift.
	swift_protocol_relative(descriptor + 48, code + u64(C.getpagesize()) * 2 + cache_offset)
	unsafe {
		*(&u64(voidptr(descriptor + 64))) = descriptor
		*(&u64(voidptr(descriptor + 72))) = entry
	}
}

fn swift_dictionary_codable_table_checked(metadata u64, arguments u64, pattern_offset u64, mut cache map[u64]u64) !u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_dictionary_metadata_retired || ios_runtime.swift_concurrency_retired
		|| metadata < 8 || metadata & 7 != 0
		|| metadata - 8 !in ios_runtime.swift_dictionary_metadata {
		return swift_dictionary_metadata_failure()
	}
	// Like native Swift, each conformance cache is keyed by the conforming
	// type. Hits borrow neither the argument array nor later inputs.
	if table := cache[metadata] { return table }
	if arguments == 0 || arguments & 7 != 0 || arguments > ~u64(0) - 15 {
		return swift_dictionary_metadata_failure()
	}
	key := read64(arguments)
	value := read64(arguments + 8)
	if key == 0 || value == 0 || (key | value) & 7 != 0 {
		return swift_dictionary_metadata_failure()
	}
	page := usize(C.getpagesize())
	allocation := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == unsafe { voidptr(-1) } { return swift_dictionary_metadata_failure() }
	base := u64(allocation)
	pattern := ios_runtime.swift_dictionary_metadata_arena + u64(page) + pattern_offset
	unsafe {
		*(&u64(voidptr(base))) = value
		*(&u64(voidptr(base + 8))) = key
		*(&u64(voidptr(base + 16))) = read64(pattern)
		*(&u64(voidptr(base + 24))) = read64(pattern + 8)
	}
	if C.mprotect(allocation, page, C.PROT_READ) != 0 {
		C.munmap(allocation, page)
		return swift_dictionary_metadata_failure()
	}
	cache[metadata] = base + 16
	return base + 16
}

// After users drain, retire witnesses before their borrowed metadata and
// descriptors. The callers retain descriptor addresses to reject stale lookups.
fn swift_dictionary_codable_stop(mut cache map[u64]u64) {
	for _, table in cache {
		if C.munmap(voidptr(table - 16), usize(C.getpagesize())) != 0 {
			panic('iOS: cannot retire Swift Dictionary Codable witnesses')
		}
	}
	unsafe { cache.free() }
}
