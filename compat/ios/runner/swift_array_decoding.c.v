// SPDX-License-Identifier: GPL-2.0-or-later
module main

type SwiftArrayDecodingCall = fn (u64, u64, u64, u64, u64, u64, u64, u64) u64
type SwiftArrayDecodingEnd = fn (u64, u64, u64, u64) u64

fn swift_array_decoding_table_checked(metadata u64, arguments u64) !u64 {
	swift_array_sequence_element_checked(metadata, false)!
	swift_array_decoding_arena()
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if table := ios_runtime.swift_array_decoding[metadata] { return table }
	if arguments == 0 || arguments & 7 != 0 || arguments > ~u64(0) - 8 {
		return swift_sequence_failure()
	}
	element_table := read64(arguments)
	if element_table == 0 || element_table & 7 != 0 { return swift_sequence_failure() }
	page := usize(C.getpagesize())
	allocation := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == unsafe { voidptr(-1) } { return swift_sequence_failure() }
	base := u64(allocation)
	unsafe {
		*(&u64(base)) = element_table
		*(&u64(base + 8)) = ios_runtime.swift_array_decoding_descriptor
		*(&u64(base + 16)) = ios_runtime.swift_array_decoding_arena
	}
	if C.mprotect(allocation, page, C.PROT_READ) != 0 {
		C.munmap(allocation, page)
		return swift_sequence_failure()
	}
	ios_runtime.swift_array_decoding[metadata] = base + 8
	return base + 8
}

// Decoder is owned; metadata and conditional witnesses are borrowed. Publish
// the Array only after success, and transfer the exact owned Swift error on a
// throw. All application callbacks run outside the registry lock.
fn swift_array_decoding_checked(decoder u64, metadata u64, table u64, output u64, incoming u64) !u64 {
	element_type := swift_array_sequence_element_checked(metadata, false)!
	C.ios_objc_initialize_lock()
	valid := table != 0 && (ios_runtime.swift_array_decoding[metadata] or { u64(0) }) == table
	element_table := if valid { read64(table - 8) } else { u64(0) }
	C.ios_objc_initialize_unlock()
	if !valid { return swift_sequence_failure() }
	element := swift_sequence_value_checked(element_type)!
	array := swift_array_layout(0, element_type)!
	decoder_value := swift_raw_encoding_value_checked(decoder)!
	defer { swift_raw_encoding_destroy(decoder, decoder_value) }
	decoder_self := swift_raw_encoding_project_checked(decoder, decoder_value, false)!
	getter := swift_raw_encoding_callback_checked(decoder_value.table, 32)!
	container := u64(C.__builtin_alloca(48))
	get := unsafe { SwiftRawIntegerDecodeCall(voidptr(swift_hash_entry(1216))) }
	thrown := get(getter, container, decoder_value.metadata, decoder_value.table, decoder_self, incoming)
	if thrown != 0 { return thrown } // No container was initialized.
	container_value := swift_raw_encoding_value_checked(container)!
	defer { swift_raw_encoding_destroy(container, container_value) }
	end_self := swift_raw_encoding_project_checked(container, container_value, false)!
	end_getter := swift_raw_encoding_callback_checked(container_value.table, 24)!
	is_at_end := unsafe { SwiftArrayDecodingEnd(voidptr(ios_runtime.swift_array_decoding_arena + 160)) }
	// Empty boxed containers need no mutable projection or decode witness.
	mut ended := is_at_end(end_getter, container_value.metadata, container_value.table, end_self) & 1 != 0
	mut owner := u64(0)
	mut count := u64(0)
	mut capacity := u64(0)
	if !ended {
		container_self := swift_raw_encoding_project_checked(container, container_value, true)!
		decode := swift_raw_encoding_callback_checked(container_value.table, 176)!
		storage := u64(C.__builtin_alloca(usize(element.size + element.alignment + 16)))
		temporary := (storage + element.alignment - 1) & ~(element.alignment - 1)
		call := unsafe { SwiftArrayDecodingCall(voidptr(ios_runtime.swift_array_decoding_arena + 64)) }
		take := unsafe { SwiftSequenceCopy(voidptr(element.take)) }
		destroy := unsafe { SwiftSequenceDestroy(voidptr(element.destroy)) }
		mut live := false
		defer {
			if live { destroy(temporary, element_type) }
			if owner != 0 { swift_bridge_release(owner) }
		}
		for !ended {
			error := call(decode, temporary, element_type, element_table, container_value.metadata, container_value.table, container_self, incoming)
			if error != 0 { return error } // A throwing decode produced no Element.
			live = true
			if count == capacity {
				next := if capacity == 0 { u64(1) } else { capacity * 2 }
				// Use the existing bounded builder: move initialized elements, clear
				// the old count and release its tail; no element is copied or destroyed.
				owner = swift_sequence_grow(owner, count, next, SwiftSequenceLayout{ array: array, result: element })!
				capacity = next
			}
			take(owner + array.storage.tail + count * array.storage.stride, temporary, element_type)
			live = false
			count++
			unsafe { *(&u64(owner + 16)) = count }
			ended = is_at_end(end_getter, container_value.metadata, container_value.table, end_self) & 1 != 0
		}
		if output == 0 || output & 7 != 0 || output > ~u64(0) - 8 {
			return swift_sequence_failure()
		}
		unsafe { *(&u64(output)) = owner }
		owner = 0 // Transfer ownership; the container and Decoder are still consumed.
	} else {
		if output == 0 || output & 7 != 0 || output > ~u64(0) - 8 {
			return swift_sequence_failure()
		}
		unsafe { *(&u64(output)) = swift_array_empty() }
	}
	return if count == 0 { incoming } else { u64(0) }
}

fn swift_array_decoding(decoder u64, metadata u64, table u64, output u64, incoming u64) u64 {
	return swift_array_decoding_checked(decoder, metadata, table, output, incoming) or { panic(err) }
}

fn swift_array_decoding_arena() u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		panic('iOS: Array decoding outside runtime lifetime')
	}
	nominal := swift_array_arena() + u64(C.getpagesize()) + 160
	protocol := swift_foundation_arena() + u64(C.getpagesize()) + 752
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_array_decoding_arena != 0 { return ios_runtime.swift_array_decoding_arena }
	page := usize(C.getpagesize())
	allocation := C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == unsafe { voidptr(-1) } {
		panic('iOS: cannot allocate Array Decodable records')
	}
	base := u64(allocation)
	data := base + u64(page)
	// Swift Decoder/Array metadata/table x0..x2 and indirect result x8.
	for i, op in [u32(0xa9bf7bfd), 0xaa0803e3, 0xaa1503e4, 0x580000b0, 0xd63f0200, 0xaa0003f5,
		0xa8c17bfd, 0xd65f03c0]! {
		write32(base + u64(i * 4), op)
	}
	unsafe { *(&u64(base + 32)) = u64(voidptr(swift_array_decoding)) }
	// C -> throwing generic decode<T>: T.Type/T metadata/T:Decodable and
	// container metadata/table x0..x4, result x8, mutable container x20.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103e8, 0xaa0203e0,
		0xaa0203e1, 0xaa0303e2, 0xaa0403e3, 0xaa0503e4, 0xaa0603f4, 0xaa0703f5, 0xd63f0200, 0xaa1503e0,
		0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(base + 64 + u64(i * 4), op)
	}
	// C -> nonthrowing isAtEnd. Preserve C's x21 across a clobbering getter.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103e0, 0xaa0203e1,
		0xaa0303f4, 0xd63f0200, 0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(base + 160 + u64(i * 4), op)
	}
	swift_protocol_relative(data, protocol)
	swift_protocol_relative(data + 4, nominal)
	swift_protocol_relative(data + 8, data + 64)
	write32(data + 12, 0x20100)
	write32(data + 16, 0x80)
	swift_protocol_relative(data + 20, data + 48)
	swift_protocol_relative(data + 24, protocol)
	write32(data + 28, 0x30002)
	swift_protocol_relative(data + 36, base + u64(page * 2))
	C.memcpy(voidptr(data + 48), c'x', 2)
	unsafe {
		*(&u64(data + 64)) = data
		*(&u64(data + 72)) = base
	}
	C.__builtin___clear_cache(allocation, voidptr(base + 208))
	if C.mprotect(allocation, page, C.PROT_READ | C.PROT_EXEC) != 0 || C.mprotect(voidptr(data), page, C.PROT_READ) != 0 {
		C.munmap(allocation, page * 3)
		panic('iOS: cannot seal Array Decodable records')
	}
	ios_runtime.swift_array_decoding_arena = base
	ios_runtime.swift_array_decoding_descriptor = data
	return base
}

fn swift_array_decoding_symbol(symbol string) ?u64 {
	if symbol != '_$sSayxGSesSeRzlMc' || ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return none
	}
	return swift_array_decoding_arena() + u64(C.getpagesize())
}

fn swift_array_decoding_stop() {
	page := usize(C.getpagesize())
	for _, table in ios_runtime.swift_array_decoding {
		if C.munmap(voidptr(table - 8), page) != 0 {
			panic('iOS: cannot retire Array Decodable table')
		}
	}
	unsafe { ios_runtime.swift_array_decoding.free() }
	if ios_runtime.swift_array_decoding_arena != 0 {
		if C.munmap(voidptr(ios_runtime.swift_array_decoding_arena), page * 3) != 0 {
			panic('iOS: cannot retire Array Decodable records')
		}
		ios_runtime.swift_array_decoding_arena = 0
	}
}
