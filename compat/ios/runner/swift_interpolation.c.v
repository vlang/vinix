// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Native-tail bytes and String's frozen flags/header were measured against
// installed libswiftCore. This private descriptor is not Swift class metadata;
// allocation/reflection of arbitrary Swift classes remains unsupported.
struct SwiftStringBufferDescriptor {
	name        &char = c'Vinix Swift String storage'
	header_size u64   = 32
}

__global swift_string_buffer_descriptor = SwiftStringBufferDescriptor{}

struct SwiftStringBytes {
	address u64
	count   u64
}

// The caller supplies stack scratch for the inline representation. Returned
// large bytes are borrowed for the duration of the operation, never consumed.
fn swift_string_bytes(words SwiftStringWords, scratch u64) !SwiftStringBytes {
	if words.second & (u64(1) << 61) != 0 {
		if words.second & (u64(1) << 63) == 0 || words.second & (u64(1) << 60) != 0 {
			return error('iOS: unsupported Swift small string representation')
		}
		unsafe { *(&SwiftStringWords(scratch)) = words }
		return SwiftStringBytes{ address: scratch, count: (words.second >> 56) & 15 }
	}
	if words.second & (u64(1) << 60) != 0 || words.first & (u64(1) << 60) == 0 {
		return error('iOS: Swift shared/foreign string storage is not implemented')
	}
	address := words.second & swift_address_mask
	if address == 0 { return error('iOS: invalid Swift string storage') }
	return SwiftStringBytes{ address: address + 32, count: words.first & swift_count_mask }
}

fn swift_interpolation_capacity(literals i64, interpolations i64) !u64 {
	maximum := i64(9223372036854775807)
	minimum := -maximum - 1
	if interpolations > maximum / 2 || interpolations < minimum / 2 {
		return error('iOS: Swift interpolation capacity overflow')
	}
	extra := interpolations * 2
	if (extra > 0 && literals > maximum - extra) || (extra < 0 && literals < minimum - extra) {
		return error('iOS: Swift interpolation capacity overflow')
	}
	capacity := literals + extra
	if capacity <= 15 { return 0 } // Native _StringGuts ignores nonpositive hints.
	if u64(capacity) > swift_count_mask {
		return error('iOS: Swift String capacity exceeds frozen representation')
	}
	return u64(capacity)
}

// Under the recursive registry lock. The 32-byte body differs from an Array:
// word 2 is capacity including NUL (not shifted), word 3 is count and flags.
fn swift_string_storage(capacity u64, count u64, ascii bool) SwiftStringWords {
	object := u64(C.calloc(1, usize(32 + capacity + 1)))
	if object == 0 { panic('iOS: cannot allocate Swift String storage') }
	flags := count | u64(0x3000000000000000) | if ascii { u64(0xc000000000000000) } else { u64(0) }
	unsafe {
		*(&u64(object)) = u64(&swift_string_buffer_descriptor)
		*(&u64(object + 8)) = 3
		*(&u64(object + 16)) = capacity + 1
		*(&u64(object + 24)) = flags
	}
	ios_runtime.swift_strings[object] = capacity
	return SwiftStringWords{ first: flags, second: object }
}

fn swift_interpolation_init(literals i64, interpolations i64) SwiftStringWords {
	capacity := swift_interpolation_capacity(literals, interpolations) or { panic(err) }
	if capacity == 0 { return SwiftStringWords{ second: u64(0xe000000000000000) } }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	return swift_string_storage(capacity, 0, true)
}

// Swift inout grants exclusive access to destination. Copies of its owner may
// coexist: reuse storage only with one strong reference and sufficient room.
// Otherwise publish the completed copy before releasing the previous owner.
// memmove also handles self-append and slices borrowed from the destination.
fn swift_string_append_bytes(destination u64, source u64, count u64) {
	if destination == 0 || (source == 0 && count != 0) || count > swift_count_mask {
		panic('iOS: invalid Swift String append')
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	previous := unsafe { *(&SwiftStringWords(destination)) }
	scratch := u64(C.__builtin_alloca(16))
	old := swift_string_bytes(previous, scratch) or { panic(err) }
	if count > swift_count_mask - old.count { panic('iOS: Swift String count overflow') }
	owner := previous.second & swift_address_mask
	mortal := previous.second != 0 && previous.second & (u64(1) << 63) == 0
	if mortal && owner !in ios_runtime.swift_strings {
		panic('iOS: mutation of unregistered Swift String storage is not implemented')
	}
	if count == 0 { return }
	total := old.count + count
	mut ascii := true
	for part in [old, SwiftStringBytes{ address: source, count: count }]! {
		for i in u64(0) .. part.count {
			if unsafe { *(&u8(part.address + i)) } >= 128 {
				ascii = false
				break
			}
		}
		if !ascii { break }
	}
	if total <= 15 && !mortal {
		result := u64(C.__builtin_alloca(16))
		unsafe { *(&SwiftStringWords(result)) = SwiftStringWords{} }
		C.memcpy(unsafe { voidptr(result) }, unsafe { voidptr(old.address) }, usize(old.count))
		C.memcpy(unsafe { voidptr(result + old.count) }, unsafe { voidptr(source) }, usize(count))
		unsafe { *(&SwiftStringWords(destination)) = swift_string_literal(&u8(result), i64(total), ascii) }
		return
	}
	if mortal && (read64(owner + 8) >> 33) == 0 && ios_runtime.swift_strings[owner] >= total {
		C.memmove(unsafe { voidptr(owner + 32 + old.count) }, unsafe { voidptr(source) }, usize(count))
		flags := total | u64(0x3000000000000000) | if ascii {
			u64(0xc000000000000000)
		} else {
			u64(0)
		}
		unsafe {
			*(&u8(owner + 32 + total)) = 0
			*(&u64(owner + 24)) = flags
			*(&SwiftStringWords(destination)) = SwiftStringWords{ first: flags, second: owner }
		}
		return
	}
	old_capacity := if mortal { ios_runtime.swift_strings[owner] } else { old.count }
	capacity := if old_capacity <= swift_count_mask / 2 && old_capacity * 2 > total {
		old_capacity * 2
	} else {
		total
	}
	result := swift_string_storage(capacity, total, ascii)
	C.memcpy(unsafe { voidptr(result.second + 32) }, unsafe { voidptr(old.address) }, usize(old.count))
	C.memcpy(unsafe { voidptr(result.second + 32 + old.count) }, unsafe { voidptr(source) }, usize(count))
	unsafe { *(&SwiftStringWords(destination)) = result }
	swift_bridge_release(previous.second)
}

fn swift_interpolation_literal(first u64, second u64, destination u64) {
	scratch := u64(C.__builtin_alloca(16))
	bytes := swift_string_bytes(SwiftStringWords{ first: first, second: second }, scratch) or { panic(err) }
	swift_string_append_bytes(destination, bytes.address, bytes.count)
}

fn swift_interpolation_ascii(source u64, count i64, destination u64) {
	if count < 0 { panic('iOS: negative Swift ASCII buffer count') }
	// The protocol's _writeASCII contract supplies ASCII bytes. Reject a violated
	// contract instead of marking non-ASCII or invalid UTF-8 as an ASCII String.
	if u64(count) > swift_count_mask || (count != 0 && source == 0) {
		panic('iOS: invalid Swift ASCII buffer')
	}
	for i in i64(0) .. count {
		if unsafe { *(&u8(source + u64(i))) } >= 128 { panic('iOS: non-ASCII Swift ASCII buffer') }
	}
	swift_string_append_bytes(destination, source, u64(count))
}

fn swift_stream_ascii_literal(source u64, count i64) SwiftStringWords {
	if count < 0 || u64(count) > swift_count_mask || (count != 0 && source == 0) {
		panic('iOS: invalid Swift ASCII buffer')
	}
	for i in i64(0) .. count {
		if unsafe { *(&u8(source + u64(i))) } >= 128 { panic('iOS: non-ASCII Swift ASCII buffer') }
	}
	if count <= 15 { return swift_string_literal(unsafe { &u8(source) }, count, true) }
	// A target may retain the borrowed String. Copy large buffer bytes into an
	// owner, and retire the temporary reference only after its callback returns.
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	result := swift_string_storage(u64(count), u64(count), true)
	C.memcpy(unsafe { voidptr(result.second + 32) }, unsafe { voidptr(source) }, usize(count))
	return result
}

// Frozen interpolation has one String at offset zero and shares its value
// witnesses. Its own nominal descriptor and four-slot TextOutputStream table
// are canonical; reflection/conformance discovery exports stay unsupported.
fn swift_interpolation_metadata() u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	page := u64(C.getpagesize())
	if ios_runtime.swift_interpolation_arena == 0 {
		$if !arm64 {
			panic('iOS: Swift interpolation requires ARM64')
		}
		string_metadata := swift_string_metadata()
		arena := C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if arena == unsafe { voidptr(-1) } {
			panic('iOS: cannot allocate Swift interpolation metadata')
		}
		base := u64(arena)
		data := base + page
		metadata := data + 16
		descriptor := data + 64
		module_descriptor := data + 96
		table := data + 160
		conformance := data + 208
		protocol := data + 224
		write32(base, 0x58000080)
		write32(base + 4, 0xd2800001)
		write32(base + 8, 0xd65f03c0)
		unsafe {
			*(&u64(base + 16)) = metadata
			*(&u64(data + 8)) = read64(string_metadata - 8)
			*(&u64(metadata)) = 0x200
			*(&u64(metadata + 8)) = descriptor
			*(&u64(table)) = conformance
			*(&u64(table + 8)) = base + 192
			*(&u64(table + 16)) = base + 192
			*(&u64(table + 24)) = base + 160
			*(&u64(table + 32)) = base + 224
		}
		write32(descriptor, 0x51)
		swift_protocol_relative(descriptor + 4, module_descriptor)
		swift_protocol_relative(descriptor + 8, data + 112)
		swift_protocol_relative(descriptor + 12, base)
		write32(descriptor + 20, 1)
		write32(descriptor + 24, 2)
		swift_protocol_relative(module_descriptor + 8, data + 152)
		C.memcpy(unsafe { voidptr(data + 112) }, c'DefaultStringInterpolation', 27)
		C.memcpy(unsafe { voidptr(data + 152) }, c'Swift', 6)
		swift_protocol_relative(conformance, protocol)
		swift_protocol_relative(conformance + 4, descriptor)
		swift_protocol_relative(conformance + 8, table)
		write32(protocol, 0x30043)
		swift_protocol_relative(protocol + 4, module_descriptor)
		swift_protocol_relative(protocol + 8, data + 288)
		write32(protocol + 16, 4)
		for i in 0 .. 4 { write32(protocol + 24 + u64(i * 8), 0x11) }
		// Installed default lock/unlock are RET. The generic ASCII default
		// forwards through the supplied target table; write has no default.
		swift_protocol_relative(protocol + 28, base + 192)
		swift_protocol_relative(protocol + 36, base + 192)
		swift_protocol_relative(protocol + 52, base + 256)
		C.memcpy(unsafe { voidptr(data + 288) }, c'TextOutputStream', 17)
		// Generic dual-constrained append: x0 borrowed value, x1 Self metadata,
		// x2 CustomStringConvertible table, x3 TextOutputStreamable table,
		// x20 interpolation inout. Source.write receives Target in x0/x1/x2,
		// source metadata/table in x3/x4, source self in x20. No lock over callback.
		for i, op in [u32(0xa9be7bfd), 0xa90153f3, 0xaa0303e4, 0xaa0103e3, 0xf9400490, // source table, metadata, write slot
		0xaa0003e9, 0xaa1403e0, 0xaa0903f4, 0x58000101, 0x58000122, // Target metadata/table literals +96/+104
		0xd63f0200, 0xa94153f3, 0xa8c27bfd, 0xd65f03c0]! {
			write32(base + 32 + u64(i * 4), op)
		}
		unsafe {
			*(&u64(base + 96)) = metadata
			*(&u64(base + 104)) = table
		}
		// Literal/String.append: x0/x1 borrowed String; x20 destination.
		for offset in [u64(128), 160]! {
			write32(base + offset, 0xaa1403e2)
			write32(base + offset + 4, 0x58000070)
			write32(base + offset + 8, 0xd61f0200)
			unsafe { *(&u64(base + offset + 16)) = u64(voidptr(swift_interpolation_literal)) }
		}
		write32(base + 192, 0xd65f03c0) // Measured default lock/unlock.
		// _writeASCII buffer in x0/x1 and target context in x20.
		write32(base + 224, 0xaa1403e2)
		write32(base + 228, 0x58000070)
		write32(base + 232, 0xd61f0200)
		unsafe { *(&u64(base + 240)) = u64(voidptr(swift_interpolation_ascii)) }
		// Generic TextOutputStream._writeASCII default: x0/x1 buffer, x2/x3
		// target metadata/table, x20 target self. Preserve context and forward
		// a borrowed String through the caller's write slot, without a lock.
		for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0203f3, 0xaa0303f5, 0xf9400c76,
			0x58000210, // ldr x16,literal at +344
			0xd63f0200, 0xaa1303e2, 0xaa1503e3, 0xaa0103f5, 0xd63f02c0, 0xaa1503e0, 0x58000170,
			0xd63f0200, // release temporary owner via +352
			0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
			write32(base + 256 + u64(i * 4), op)
		}
		unsafe {
			*(&u64(base + 344)) = u64(voidptr(swift_stream_ascii_literal))
			*(&u64(base + 352)) = u64(voidptr(swift_bridge_release))
		}
		// _StringGuts.grow: capacity in x0, inout String in Swift self x20.
		write32(base + 384, 0xaa1403e1) // mov x1,x20
		write32(base + 388, 0x58000070) // ldr x16,+16
		write32(base + 392, 0xd61f0200) // br x16; C preserves x20/x21
		unsafe { *(&u64(base + 400)) = u64(voidptr(swift_string_grow)) }
		// C-to-Swift stream write: String x0/x1, metadata/table x2/x3,
		// inout target x4, write entry x5. Preserve the caller's Swift context.
		for i, op in [u32(0xa9be7bfd), 0xa90153f3, 0xaa0403f4, 0xd63f00a0,
			0xa94153f3, 0xa8c27bfd, 0xd65f03c0]! { write32(base + 416 + u64(i * 4), op) }
		C.__builtin___clear_cache(arena, unsafe { voidptr(base + 444) })
		if C.mprotect(arena, usize(page), C.PROT_READ | C.PROT_EXEC) != 0
			|| C.mprotect(unsafe { voidptr(data) }, usize(page), C.PROT_READ) != 0 {
			C.munmap(arena, usize(page * 2))
			panic('iOS: cannot seal Swift interpolation metadata')
		}
		ios_runtime.swift_interpolation_arena = base
	}
	return ios_runtime.swift_interpolation_arena + page + 16
}

fn swift_interpolation_symbol(symbol string) ?u64 {
	if symbol == '_$ss26DefaultStringInterpolationV15literalCapacity18interpolationCountABSi_SitcfC' {
		return u64(unsafe { voidptr(swift_interpolation_init) })
	}
	offset := match symbol {
		'_$ss26DefaultStringInterpolationVN' { 16 }
		'_$ss26DefaultStringInterpolationVMn' { 64 }
		'_$ss26DefaultStringInterpolationVs16TextOutputStreamsWP' { 160 }
		'_$ss26DefaultStringInterpolationVs16TextOutputStreamsMc' { 208 }
		'_$ss16TextOutputStreamMp' { 224 }
		'_$ss26DefaultStringInterpolationVMa' { -16 }
		'_$ss26DefaultStringInterpolationV06appendC0yyxs06CustomB11ConvertibleRzs20TextOutputStreamableRzlF' {
			-32
		}
		'_$ss26DefaultStringInterpolationV13appendLiteralyySSF', '_$sSS6appendyySSF' { -128 }
		'_$ss11_StringGutsV4growyySiF' { -384 }
		else { return none }
	}
	metadata := swift_interpolation_metadata()
	return if offset < 0 {
		ios_runtime.swift_interpolation_arena + if offset == -16 { u64(0) } else { u64(-offset) }
	} else {
		metadata - 16 + u64(offset)
	}
}

fn swift_interpolation_stop() {
	if ios_runtime.swift_interpolation_arena != 0 {
		if C.munmap(unsafe { voidptr(ios_runtime.swift_interpolation_arena) }, usize(C.getpagesize()) * 2) != 0 {
			panic('iOS: cannot retire Swift interpolation metadata')
		}
		ios_runtime.swift_interpolation_arena = 0
	}
}
