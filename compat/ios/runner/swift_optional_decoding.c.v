// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Compare registered identities before reading metadata. Optional's existing
// accessor admits complete, copyable inline Wrapped layouts of at most 24
// bytes/alignment 8; this conformance uses that same bounded lifetime.
fn swift_optional_decoding_wrapped_checked(metadata u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_optional_retired
		|| ios_runtime.swift_concurrency_retired { return swift_optional_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	for wrapped, candidate in ios_runtime.swift_optional_metadata {
		if candidate == metadata { return wrapped }
	}
	return swift_optional_failure()
}

fn swift_optional_decoding_table_checked(metadata u64, arguments u64) !u64 {
	swift_optional_decoding_wrapped_checked(metadata)!
	base := swift_optional_decoding_arena_checked()!
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	// Native caches by Optional metadata. A hit does not reread the borrowed
	// conditional argument, which may already have gone out of scope.
	if table := ios_runtime.swift_optional_decoding[metadata] { return table }
	if arguments == 0 || arguments & 7 != 0 || arguments > ~u64(0) - 8 { return swift_optional_failure() }
	wrapped_table := read64(arguments)
	if wrapped_table == 0 || wrapped_table & 7 != 0 { return swift_optional_failure() }
	page := usize(C.getpagesize())
	allocation := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == unsafe { voidptr(-1) } { return swift_optional_failure() }
	table := u64(allocation) + 8
	unsafe {
		*(&u64(table - 8)) = wrapped_table
		*(&u64(table)) = ios_runtime.swift_optional_decoding_descriptor
		*(&u64(table + 8)) = base
	}
	if C.mprotect(allocation, page, C.PROT_READ) != 0 {
		C.munmap(allocation, page); return swift_optional_failure()
	}
	ios_runtime.swift_optional_decoding[metadata] = table
	return table
}

// Decoder is consumed; its projection, metadata and conditional table are
// borrowed. Decode into bounded scratch, retire the container, then publish
// the Optional before consuming Decoder, matching the native ownership order.
fn swift_optional_decoding_checked(decoder u64, metadata u64, table u64, output u64, incoming u64) !u64 {
 wrapped := swift_optional_decoding_wrapped_checked(metadata)!
 C.ios_objc_initialize_lock()
 valid := table != 0 && (ios_runtime.swift_optional_decoding[metadata] or { u64(0) }) == table
 wrapped_table := if valid { read64(table - 8) } else { u64(0) }
 C.ios_objc_initialize_unlock()
 if !valid { return swift_optional_failure() }
 layout := swift_sequence_value_checked(wrapped)!
 decoder_value := swift_raw_encoding_value_checked(decoder)!
 defer { swift_raw_encoding_destroy(decoder, decoder_value) }
 decoder_self := swift_raw_encoding_project_checked(decoder, decoder_value, false)!
 getter := swift_raw_encoding_callback_checked(decoder_value.table, 40)!
 container := u64(C.__builtin_alloca(48))
 get := unsafe { SwiftRawIntegerDecodeCall(voidptr(swift_hash_entry(1216))) }
 thrown := get(getter, container, decoder_value.metadata, decoder_value.table, decoder_self, incoming)
 if thrown != 0 { return thrown } // No container or Wrapped value was initialized.
 container_value := swift_raw_encoding_value_checked(container)!
 optional := u64(C.__builtin_alloca(24))
 mut live := false
 defer { if live { swift_optional_destroy(optional, metadata) } }
 {
  defer { swift_raw_encoding_destroy(container, container_value) }
  container_self := swift_raw_encoding_project_checked(container, container_value, false)!
  nil_getter := swift_raw_encoding_callback_checked(container_value.table, 16)!
  is_nil := unsafe { SwiftArrayDecodingEnd(voidptr(ios_runtime.swift_optional_decoding_arena + 160)) }
  if is_nil(nil_getter, container_value.metadata, container_value.table, container_self) & 1 != 0 {
   swift_optional_inject(optional, 1, metadata)
  } else {
   decode := swift_raw_encoding_callback_checked(container_value.table, 152)!
   payload := u64(C.__builtin_alloca(24))
   call := unsafe { SwiftArrayDecodingCall(voidptr(ios_runtime.swift_optional_decoding_arena + 64)) }
   error := call(decode, payload, wrapped, wrapped_table, container_value.metadata, container_value.table, container_self, 0)
   if error != 0 { return error } // A throwing decode initialized no payload.
   take := unsafe { SwiftSequenceCopy(voidptr(layout.take)) }
   take(optional, payload, wrapped)
   swift_optional_inject(optional, 0, metadata)
  }
  live = true
 }
 witness := read64(metadata - 8)
 size := read64(witness + 64)
 mask := u64(read32(witness + 80) & 255)
 if output == 0 || output & mask != 0 || output > ~u64(0) - size { return swift_optional_failure() }
 swift_optional_take(output, optional, metadata)
 live = false
 return 0
}

fn swift_optional_decoding(decoder u64, metadata u64, table u64, output u64, incoming u64) u64 {
 return swift_optional_decoding_checked(decoder, metadata, table, output, incoming) or { panic(err) }
}

fn swift_optional_decoding_arena_checked() !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_optional_retired
		|| ios_runtime.swift_concurrency_retired { return swift_optional_failure() }
	nominal := swift_optional_metadata_arena_checked()! + u64(C.getpagesize()) + 160
	protocol := swift_foundation_arena() + u64(C.getpagesize()) + 752
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_optional_retired || ios_runtime.swift_concurrency_retired { return swift_optional_failure() }
	if ios_runtime.swift_optional_decoding_arena != 0 { return ios_runtime.swift_optional_decoding_arena }
	page := usize(C.getpagesize())
	allocation := C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == unsafe { voidptr(-1) } { return swift_optional_failure() }
	base := u64(allocation); data := base + u64(page)
	// Swift Decoder/Optional metadata/table x0..x2 and indirect result x8.
	for i, op in [u32(0xa9bf7bfd), 0xaa0803e3, 0xaa1503e4, 0x580000b0, 0xd63f0200, 0xaa0003f5,
		0xa8c17bfd, 0xd65f03c0]! {
		write32(base + u64(i * 4), op)
	}
	unsafe { *(&u64(base + 32)) = u64(voidptr(swift_optional_decoding)) }
	// C -> throwing generic decode<T>: T.Type/T metadata/T:Decodable and
	// container metadata/table x0..x4, result x8, borrowed container x20.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103e8, 0xaa0203e0,
		0xaa0203e1, 0xaa0303e2, 0xaa0403e3, 0xaa0503e4, 0xaa0603f4, 0xaa0703f5, 0xd63f0200, 0xaa1503e0,
		0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(base + 64 + u64(i * 4), op)
	}
	// C -> nonthrowing decodeNil. Preserve C's x21 across a clobbering getter.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103e0, 0xaa0203e1,
		0xaa0303f4, 0xd63f0200, 0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(base + 160 + u64(i * 4), op)
	}
	swift_protocol_relative(data, protocol); swift_protocol_relative(data + 4, nominal)
	swift_protocol_relative(data + 8, data + 64); write32(data + 12, 0x20100); write32(data + 16, 0x80)
	swift_protocol_relative(data + 20, data + 48); swift_protocol_relative(data + 24, protocol)
	write32(data + 28, 0x30002); swift_protocol_relative(data + 36, base + u64(page * 2))
	C.memcpy(voidptr(data + 48), c'x', 2)
	unsafe { *(&u64(data + 64)) = data; *(&u64(data + 72)) = base }
	C.__builtin___clear_cache(allocation, voidptr(base + 208))
	if C.mprotect(allocation, page, C.PROT_READ | C.PROT_EXEC) != 0 || C.mprotect(voidptr(data), page, C.PROT_READ) != 0 {
		C.munmap(allocation, page * 3); return swift_optional_failure()
	}
	ios_runtime.swift_optional_decoding_arena = base
	ios_runtime.swift_optional_decoding_descriptor = data
	return base
}

fn swift_optional_decoding_symbol(symbol string) ?u64 {
	if symbol != '_$sxSgSesSeRzlMc' { return none }
	base := swift_optional_decoding_arena_checked() or { return none }
	return base + u64(C.getpagesize())
}

fn swift_optional_decoding_stop() {
	page := usize(C.getpagesize())
	for _, table in ios_runtime.swift_optional_decoding {
		if C.munmap(voidptr(table - 8), page) != 0 { panic('iOS: cannot retire Optional Decodable table') }
	}
	unsafe { ios_runtime.swift_optional_decoding.free() }
	if ios_runtime.swift_optional_decoding_arena != 0 {
		if C.munmap(voidptr(ios_runtime.swift_optional_decoding_arena), page * 3) != 0 { panic('iOS: cannot retire Optional Decodable records') }
		ios_runtime.swift_optional_decoding_arena = 0
	}
}
