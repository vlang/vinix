// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftStringProtocolNode {
	name   string
	offset u64
	cell   u64
}

struct SwiftStringProtocolFailure {}

fn (_ &SwiftStringProtocolFailure) msg() string {
	return 'iOS: Swift StringProtocol witness instantiation is not implemented'
}

fn (_ &SwiftStringProtocolFailure) code() int { return 1 }

__global swift_string_protocol_failure_value = SwiftStringProtocolFailure{}

fn swift_string_protocol_failure() IError { return unsafe { &swift_string_protocol_failure_value } }

// This is a declaration-only profile. StringProtocol's 27-word witness table
// needs encoded views, literal/interpolation and character collection support.
// Neither the descriptor nor this callback publishes a partial witness table.
fn swift_string_protocol_instantiate_unavailable(_table u64, _metadata u64, _arguments u64) {
	panic('iOS: Swift StringProtocol witness instantiation is not implemented')
}

fn swift_string_protocol_default_unavailable() {
	panic('iOS: Swift StringProtocol inherited protocol default is not implemented')
}

fn swift_string_protocol_table_checked(_metadata u64, _arguments u64) !u64 {
	// Recognized before reading the descriptor, even after its arena is retired.
	return swift_string_protocol_failure()
}

fn swift_string_protocol_allocation_size() u64 {
	page := u64(C.getpagesize())
	return page + ((u64(swift_string_protocol_schema_words.len * 8) + page - 1) & ~(page - 1))
}

fn swift_string_protocol_descriptor_checked() !u64 {
	$if !arm64 {
		return swift_string_protocol_failure()
	}
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return swift_string_protocol_failure()
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_string_protocol_arena != 0 {
		return ios_runtime.swift_string_protocol_descriptor
	}
	string_type := swift_string_metadata()
	swift_collection_arena() // Reuse already implemented core protocol identities.
	page := u64(C.getpagesize())
	size := swift_string_protocol_allocation_size()
	allocation := C.mmap(unsafe { nil }, usize(size), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == unsafe { voidptr(-1) } { return swift_string_protocol_failure() }
	code := u64(allocation)
	data := code + page
	C.memcpy(voidptr(data), &swift_string_protocol_schema_words[0], usize(swift_string_protocol_schema_words.len * 8))
	for i, target in [
		u64(unsafe { voidptr(swift_string_protocol_instantiate_unavailable) }),
		u64(unsafe { voidptr(swift_string_protocol_default_unavailable) }),
	]! {
		entry := code + u64(i * 16)
		write32(entry, 0x58000050)
		write32(entry + 4, 0xd61f0200)
		unsafe { *(&u64(entry + 8)) = target }
	}
	// Generic witness control: 27 words, requires instantiation, no private
	// prefix. The uninstantiated pattern remains private and the optional
	// preallocated cache is absent. The fatal instantiator never publishes it.
	swift_protocol_relative(data + 20, code)
	unsafe {
		*(&u64(data + 32)) = read64(string_type + 8)
		*(&u64(data + swift_string_protocol_schema_pattern_offset)) = data
	}
	integer := ios_runtime.swift_integer_arena + page
	string_data := ios_runtime.swift_metadata_arena + page
	collection := ios_runtime.swift_collection_arena + page
	sequence := ios_runtime.swift_array_sequence_arena + page
	for node in swift_string_protocol_schema_nodes {
		address := match node.name {
			'Hashable' { integer + 352 }
			'Equatable' { integer + 432 }
			'TextOutputStreamable' { string_data + 320 }
			'CustomStringConvertible' { string_data + 352 }
			'Collection' { collection + 256 }
			'Comparable' { collection + 800 }
			'Sequence' { sequence + 256 }
			'IteratorProtocol' { sequence + 384 }
			else { data + node.offset }
		}
		unsafe { *(&u64(data + node.cell)) = address }
	}
	for field in swift_string_protocol_schema_defaults {
		swift_protocol_relative(data + field, code + 16)
	}
	C.__builtin___clear_cache(allocation, voidptr(code + 32))
	if C.mprotect(allocation, usize(page), C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(voidptr(data), usize(size - page), C.PROT_READ) != 0 {
		if C.munmap(allocation, usize(size)) != 0 {
			panic('iOS: cannot retire unsealed StringProtocol declaration')
		}
		return swift_string_protocol_failure()
	}
	ios_runtime.swift_string_protocol_arena = code
	ios_runtime.swift_string_protocol_descriptor = data
	return data
}

fn swift_string_protocol_stop() {
	if ios_runtime.swift_string_protocol_arena == 0 { return }
	if C.munmap(voidptr(ios_runtime.swift_string_protocol_arena), usize(swift_string_protocol_allocation_size())) != 0 {
		panic('iOS: cannot retire StringProtocol declaration')
	}
	ios_runtime.swift_string_protocol_arena = 0
	// Remember descriptor identity until the runtime is replaced, so a stale
	// swift_getWitnessTable request is rejected before any unmapped read.
}
