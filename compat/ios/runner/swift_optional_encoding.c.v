// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Compare registered identities before reading metadata. Optional's existing
// accessor admits complete, copyable bitwise-takable layouts with Optional
// size at most 65536/alignment 8; scratch follows that same bounded layout.
fn swift_optional_encoding_wrapped_checked(metadata u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_optional_retired
		|| ios_runtime.swift_concurrency_retired { return swift_optional_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	for wrapped, candidate in ios_runtime.swift_optional_metadata {
		if candidate == metadata { return wrapped }
	}
	return swift_optional_failure()
}

fn swift_optional_encoding_table_checked(metadata u64, arguments u64) !u64 {
	swift_optional_encoding_wrapped_checked(metadata)!
	base := swift_optional_encoding_arena_checked()!
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	// Native caches by Optional metadata. A hit does not reread the borrowed
	// conditional argument, which may already have gone out of scope.
	if table := ios_runtime.swift_optional_encoding[metadata] { return table }
	if arguments == 0 || arguments & 7 != 0 || arguments > ~u64(0) - 8 { return swift_optional_failure() }
	wrapped_table := read64(arguments)
	if wrapped_table == 0 || wrapped_table & 7 != 0 { return swift_optional_failure() }
	page := usize(C.getpagesize())
	allocation := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == unsafe { voidptr(-1) } { return swift_optional_failure() }
	table := u64(allocation) + 8
	unsafe {
		*(&u64(table - 8)) = wrapped_table
		*(&u64(table)) = ios_runtime.swift_optional_encoding_descriptor
		*(&u64(table + 8)) = base
	}
	if C.mprotect(allocation, page, C.PROT_READ) != 0 {
		C.munmap(allocation, page); return swift_optional_failure()
	}
	ios_runtime.swift_optional_encoding[metadata] = table
	return table
}

fn swift_optional_encoding_checked(encoder u64, metadata u64, table u64, receiver u64, incoming u64) !u64 {
	wrapped := swift_optional_encoding_wrapped_checked(metadata)!
	if receiver == 0 { return swift_optional_failure() }
	C.ios_objc_initialize_lock()
	valid := table != 0 && (ios_runtime.swift_optional_encoding[metadata] or { u64(0) }) == table
	wrapped_table := if valid { read64(table - 8) } else { u64(0) }
	C.ios_objc_initialize_unlock()
	if !valid { return swift_optional_failure() }
	layout := swift_sequence_value_checked(wrapped)!
	encoder_value := swift_raw_encoding_value_checked(encoder)!
	encoder_self := swift_raw_encoding_project_checked(encoder, encoder_value, false)!
	getter := swift_raw_encoding_callback_checked(encoder_value.table, 40)!
	container := u64(C.__builtin_alloca(48))
	get := unsafe { SwiftRawGetterCall(voidptr(swift_hash_entry(960))) }
	get(getter, container, encoder_value.metadata, encoder_value.table, encoder_self)
	container_value := swift_raw_encoding_value_checked(container)!
	defer { swift_raw_encoding_destroy(container, container_value) }
	// Create the container before inspecting an owned copy of the Optional.
	// A some payload is then moved out, borrowed by generic encode,
	// and destroyed on success, throw and checked dispatch failures.
	optional := u64(C.__builtin_alloca(usize(read64(read64(metadata - 8) + 64) + 1)))
	swift_optional_copy(optional, receiver, metadata)
	tag := swift_optional_tag(optional, metadata)
	if tag == 1 {
		container_self := swift_raw_encoding_project_checked(container, container_value, true)!
		encode_nil := swift_raw_encoding_callback_checked(container_value.table, 16)!
		call := unsafe { SwiftOptionalNilCall(voidptr(ios_runtime.swift_optional_encoding_arena + 144)) }
		return call(encode_nil, container_value.metadata, container_value.table, container_self, incoming)
	}
	if tag != 0 { return swift_optional_failure() }
	payload := u64(C.__builtin_alloca(usize(layout.size + 1)))
	take := unsafe { SwiftSequenceCopy(voidptr(read64(read64(wrapped - 8) + 32))) }
	take(payload, optional, wrapped)
	destroy := unsafe { SwiftSequenceDestroy(voidptr(layout.destroy)) }
	defer { destroy(payload, wrapped) }
	container_self := swift_raw_encoding_project_checked(container, container_value, true)!
	encode := swift_raw_encoding_callback_checked(container_value.table, 152)!
	call := unsafe { SwiftArrayEncodingCall(voidptr(ios_runtime.swift_optional_encoding_arena + 64)) }
	return call(encode, payload, wrapped, wrapped_table, container_value.metadata, container_value.table, container_self, incoming)
}

type SwiftOptionalNilCall = fn (u64, u64, u64, u64, u64) u64

fn swift_optional_encoding(encoder u64, metadata u64, table u64, receiver u64, incoming u64) u64 {
	return swift_optional_encoding_checked(encoder, metadata, table, receiver, incoming) or { panic(err) }
}

fn swift_optional_encoding_arena_checked() !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_optional_retired
		|| ios_runtime.swift_concurrency_retired { return swift_optional_failure() }
	nominal := swift_optional_metadata_arena_checked()! + u64(C.getpagesize()) + 160
	protocol := swift_foundation_arena() + u64(C.getpagesize()) + 640
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_optional_retired || ios_runtime.swift_concurrency_retired { return swift_optional_failure() }
	if ios_runtime.swift_optional_encoding_arena != 0 { return ios_runtime.swift_optional_encoding_arena }
	page := usize(C.getpagesize())
	allocation := C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == unsafe { voidptr(-1) } { return swift_optional_failure() }
	base := u64(allocation); data := base + u64(page)
	// Swift encode(to:): Encoder x0, Optional metadata x1, table x2, Self x20.
	for i, op in [u32(0xa9bf7bfd), 0xaa1403e3, 0xaa1503e4, 0x580000b0, 0xd63f0200, 0xaa0003f5, 0xa8c17bfd, 0xd65f03c0]! {
		write32(base + u64(i * 4), op)
	}
	unsafe { *(&u64(base + 32)) = u64(voidptr(swift_optional_encoding)) }
	// Generic SingleValueEncodingContainer.encode<T>, preserving C contexts
	// while exposing the exact returned owned Swift error as a C word.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103e0, 0xaa0203e1,
		0xaa0303e2, 0xaa0403e3, 0xaa0503e4, 0xaa0603f4, 0xaa0703f5, 0xd63f0200, 0xaa1503e0,
		0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! { write32(base + 64 + u64(i * 4), op) }
	// C(entry,metadata,table,Self,incoming) -> throwing encodeNil().
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103e0, 0xaa0203e1,
		0xaa0303f4, 0xaa0403f5, 0xd63f0200, 0xaa1503e0, 0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(base + 144 + u64(i * 4), op)
	}
	swift_protocol_relative(data, protocol); swift_protocol_relative(data + 4, nominal)
	swift_protocol_relative(data + 8, data + 64); write32(data + 12, 0x20100); write32(data + 16, 0x80)
	swift_protocol_relative(data + 20, data + 48); swift_protocol_relative(data + 24, protocol)
	write32(data + 28, 0x30002); swift_protocol_relative(data + 36, base + u64(page * 2))
	C.memcpy(voidptr(data + 48), c'x', 2)
	unsafe { *(&u64(data + 64)) = data; *(&u64(data + 72)) = base }
	C.__builtin___clear_cache(allocation, voidptr(base + 200))
	if C.mprotect(allocation, page, C.PROT_READ | C.PROT_EXEC) != 0 || C.mprotect(voidptr(data), page, C.PROT_READ) != 0 {
		C.munmap(allocation, page * 3); return swift_optional_failure()
	}
	ios_runtime.swift_optional_encoding_arena = base
	ios_runtime.swift_optional_encoding_descriptor = data
	return base
}

fn swift_optional_encoding_symbol(symbol string) ?u64 {
	if symbol != '_$sxSgSEsSERzlMc' { return none }
	base := swift_optional_encoding_arena_checked() or { return none }
	return base + u64(C.getpagesize())
}

fn swift_optional_encoding_stop() {
	page := usize(C.getpagesize())
	for _, table in ios_runtime.swift_optional_encoding {
		if C.munmap(voidptr(table - 8), page) != 0 { panic('iOS: cannot retire Optional Encodable table') }
	}
	unsafe { ios_runtime.swift_optional_encoding.free() }
	if ios_runtime.swift_optional_encoding_arena != 0 {
		if C.munmap(voidptr(ios_runtime.swift_optional_encoding_arena), page * 3) != 0 { panic('iOS: cannot retire Optional Encodable records') }
		ios_runtime.swift_optional_encoding_arena = 0
	}
}
