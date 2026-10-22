// SPDX-License-Identifier: GPL-2.0-or-later
module main

// URL's resilient payload is a borrowed implementation object plus its table.
// The table is inert data; only the first word participates in unknown ARC.
struct SwiftURLWords {
	owner u64
	table u64
}

fn swift_url_copy(destination u64, source u64, _metadata u64) u64 {
	words := unsafe { *(&SwiftURLWords(source)) }
	swift_unknown_retain(words.owner)
	unsafe { *(&SwiftURLWords(destination)) = words }
	return destination
}

fn swift_url_destroy(value u64, _metadata u64) {
	swift_unknown_release(read64(value))
}

fn swift_url_assign_copy(destination u64, source u64, _metadata u64) u64 {
	// Native copy assignment publishes only the owner before releasing the old
	// value. A reentrant destructor sees the old table and unretained source.
	words := unsafe { *(&SwiftURLWords(source)) }
	previous := read64(destination)
	unsafe { *(&u64(destination)) = words.owner }
	swift_unknown_release(previous)
	swift_unknown_retain(words.owner)
	unsafe { *(&u64(destination + 8)) = words.table }
	return destination
}

fn swift_url_take(destination u64, source u64, _metadata u64) u64 {
	unsafe { *(&SwiftURLWords(destination)) = *(&SwiftURLWords(source)) }
	return destination
}

fn swift_url_assign_take(destination u64, source u64, metadata u64) u64 {
	// Take assignment destroys the old value before publishing either word.
	swift_url_destroy(destination, metadata)
	return swift_url_take(destination, source, metadata)
}

// Single-payload enums use low/null implementation words as extra inhabitants.
// More than INT32_MAX empty cases require a byte after the sixteen-byte value.
// memcpy permits the native witnesses' unaligned and exactly bounded storage.
fn swift_url_enum_get(value u64, empty_cases u32, _metadata u64) u32 {
	if empty_cases == 0 { return 0 }
	if empty_cases > 0x7fffffff && unsafe { *(&u8(value + 16)) } != 0 {
		mut index := u32(0)
		C.memcpy(unsafe { &index }, voidptr(value), 4)
		return index + 0x80000000
	}
	mut owner := u64(0)
	C.memcpy(unsafe { &owner }, voidptr(value), 8)
	return if owner >> 32 == 0 { u32(owner) + 1 } else { u32(0) }
}

fn swift_url_enum_store(value u64, which_case u32, empty_cases u32, _metadata u64) {
	if empty_cases > 0x7fffffff {
		unsafe { *(&u8(value + 16)) = if which_case > 0x7fffffff { u8(1) } else { u8(0) } }
	}
	if which_case == 0 { return }
	owner := if which_case <= 0x7fffffff {
		u64(which_case - 1)
	} else {
		u64(which_case - 0x80000000)
	}
	C.memcpy(voidptr(value), unsafe { &owner }, 8)
	if which_case > 0x7fffffff { C.memset(voidptr(value + 8), 0, 8) }
}

fn swift_url_metadata_emit(code u64, data u64) {
	entry := code + 928
	metadata := data + 144
	descriptor := data + 176
	module_descriptor := data + 64 // Shared Foundation module, also used by Date.
	witness := data + 256
	write32(entry, 0x58000080)
	write32(entry + 4, 0xd2800001)
	write32(entry + 8, 0xd65f03c0)
	unsafe {
		*(&u64(entry + 16)) = metadata
		*(&u64(metadata - 8)) = witness
		*(&u64(metadata)) = 0x200
		*(&u64(metadata + 8)) = descriptor
	}
	write32(metadata + 16, 0)
	// Private nominal lookup profile: explicit witnesses replace Apple's
	// compact layout interpreter. No field-reflection or layout-string flags.
	write32(descriptor, 0x51)
	swift_protocol_relative(descriptor + 4, module_descriptor)
	swift_protocol_relative(descriptor + 8, data + 224)
	swift_protocol_relative(descriptor + 12, entry)
	write32(descriptor + 20, 1)
	write32(descriptor + 24, 2)
	C.memcpy(voidptr(data + 224), c'URL', 4)
	for i, function in [u64(unsafe { voidptr(swift_url_copy) }),
		u64(unsafe { voidptr(swift_url_destroy) }), u64(unsafe { voidptr(swift_url_copy) }),
		u64(unsafe { voidptr(swift_url_assign_copy) }), u64(unsafe { voidptr(swift_url_take) }),
		u64(unsafe { voidptr(swift_url_assign_take) }), u64(unsafe { voidptr(swift_url_enum_get) }),
		u64(unsafe { voidptr(swift_url_enum_store) })]! {
		unsafe { *(&u64(witness + u64(i * 8))) = function }
	}
	unsafe {
		*(&u64(witness + 64)) = 16
		*(&u64(witness + 72)) = 16
	}
	write32(witness + 80, 0x02010007)
	write32(witness + 84, 0x7fffffff)
}
