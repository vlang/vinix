// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Serialization needs Dictionary iteration and keyed/unkeyed Encoder
// containers. Keep that call explicit while supporting conformance identity
// and conditional witness specialization; never report a successful encode.
fn swift_dictionary_encoding_unavailable() {
	panic('iOS: Swift Dictionary encoding is not implemented')
}

fn swift_dictionary_encoding_emit(code u64, data u64, protocol u64) {
	entry := code + 64
	write32(entry, 0x58000050)
	write32(entry + 4, 0xd61f0200)
	unsafe { *(&u64(voidptr(entry + 8))) = u64(voidptr(swift_dictionary_encoding_unavailable)) }
	descriptor := data + 320
	swift_protocol_relative(descriptor, protocol)
	swift_protocol_relative(descriptor + 4, data + 160)
	swift_protocol_relative(descriptor + 8, data + 384)
	write32(descriptor + 12, 0x20200) // Two conditional requirements, generic table.
	for i in 0 .. 2 {
		requirement := descriptor + 16 + u64(i * 12)
		write32(requirement, 0x80) // Key argument, protocol conformance.
		swift_protocol_relative(requirement + 4, data + 416 + u64(i * 2))
		swift_protocol_relative(requirement + 8, protocol)
	}
	C.memcpy(voidptr(data + 416), c'x', 2)
	C.memcpy(voidptr(data + 418), c'q_', 3)
	write32(descriptor + 40, 0x50002) // Two pattern words, two private words, requires instantiation.
	// No instantiator: the runtime copies conditional witnesses in reverse
	// order immediately before the table address point, as on native Swift.
	swift_protocol_relative(descriptor + 48, code + u64(C.getpagesize()) * 2 + 128)
	unsafe {
		*(&u64(voidptr(data + 384))) = descriptor
		*(&u64(voidptr(data + 392))) = entry
	}
}

fn swift_dictionary_encoding_table_checked(metadata u64, arguments u64) !u64 {
	if ios_runtime == unsafe { nil } { return swift_dictionary_metadata_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_dictionary_metadata_retired || ios_runtime.swift_concurrency_retired
		|| metadata < 8 || metadata & 7 != 0
		|| metadata - 8 !in ios_runtime.swift_dictionary_metadata {
		return swift_dictionary_metadata_failure()
	}
	// Like native Swift, the cache is keyed by the conforming type. Once
	// published, a table borrows neither the argument array nor later inputs.
	if table := ios_runtime.swift_dictionary_encoding[metadata] { return table }
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
	pattern := ios_runtime.swift_dictionary_metadata_arena + u64(page) + 384
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
	ios_runtime.swift_dictionary_encoding[metadata] = base + 16
	return base + 16
}

// After users drain, retire witnesses before their borrowed metadata and
// descriptor. Remember the descriptor address to reject stale lookups safely.
fn swift_dictionary_encoding_stop() {
	for _, table in ios_runtime.swift_dictionary_encoding {
		if C.munmap(voidptr(table - 16), usize(C.getpagesize())) != 0 {
			panic('iOS: cannot retire Swift Dictionary Encodable witnesses')
		}
	}
	unsafe { ios_runtime.swift_dictionary_encoding.free() }
}

fn swift_dictionary_encoding_symbol(symbol string) ?u64 {
	if symbol != '_$sSDyxq_GSEsSERzSER_rlMc' || ios_runtime == unsafe { nil }
		|| ios_runtime.swift_dictionary_metadata_retired || ios_runtime.swift_concurrency_retired {
		return none
	}
	return swift_dictionary_metadata_arena() + u64(C.getpagesize()) + 320
}
