// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Native ARM64 DateEncodingStrategy: two payload cases (formatter reference,
// thick closure), four empty cases, and a tag byte after the 16-byte payload.
// These witnesses manage storage and ownership; they never invoke a formatter
// or closure and do not implement JSONEncoder's options or encoding methods.
fn swift_json_date_tag(value u64, _metadata u64) u32 {
	tag := unsafe { *(&u8(value + 16)) }
	return if tag < 2 { u32(tag) } else { read32(value) + u32(2) }
}

fn swift_json_date_project(_value u64, _metadata u64) {}

fn swift_json_date_inject(value u64, which u32, _metadata u64) {
	mut tag := which
	if which >= 2 {
		unsafe {
			*(&u64(value)) = u64(which - 2)
			*(&u64(value + 8)) = 0
		}
		tag = 2
	}
	unsafe { *(&u8(value + 16)) = u8(tag) }
}

fn swift_json_date_single_get(value u64, empty_cases u32, _metadata u64) u32 {
	if empty_cases == 0 { return 0 }
	if empty_cases >= 254 && unsafe { *(&u8(value + 17)) } != 0 {
		return read32(value) + u32(254)
	}
	tag := unsafe { *(&u8(value + 16)) }
	return if tag < 3 { u32(0) } else { u32(256) - u32(tag) }
}

fn swift_json_date_single_store(value u64, which u32, empty_cases u32, _metadata u64) {
	if which <= 253 {
		if empty_cases >= 254 { unsafe { *(&u8(value + 17)) = 0 } }
		if which != 0 { unsafe { *(&u8(value + 16)) = u8(u32(0) - which) } }
	} else {
		unsafe {
			*(&u64(value)) = u64(which - 254)
			*(&u64(value + 8)) = 0
			*(&u8(value + 16)) = 0
			*(&u8(value + 17)) = 1
		}
	}
}

fn swift_json_date_retain(value u64) {
	tag := unsafe { *(&u8(value + 16)) }
	if tag == 0 {
		swift_unknown_retain(read64(value))
	} else if tag == 1 {
		swift_retain(read64(value + 8))
	}
}

fn swift_json_date_destroy(value u64, _metadata u64) {
	tag := unsafe { *(&u8(value + 16)) }
	if tag == 0 {
		swift_unknown_release(read64(value))
	} else if tag == 1 {
		swift_release(read64(value + 8))
	}
}

fn swift_json_date_take(destination u64, source u64, _metadata u64) u64 {
	first := read64(source)
	second := read64(source + 8)
	tag := unsafe { *(&u8(source + 16)) }
	unsafe {
		*(&u64(destination)) = first
		*(&u64(destination + 8)) = second
		*(&u8(destination + 16)) = tag
	}
	return destination
}

fn swift_json_date_copy(destination u64, source u64, metadata u64) u64 {
	swift_json_date_take(destination, source, metadata)
	swift_json_date_retain(destination)
	return destination
}

fn swift_json_date_assign_copy(destination u64, source u64, metadata u64) u64 {
	if destination == source { return destination }
	swift_json_date_destroy(destination, metadata)
	return swift_json_date_copy(destination, source, metadata)
}

fn swift_json_date_assign_take(destination u64, source u64, metadata u64) u64 {
	swift_json_date_destroy(destination, metadata)
	return swift_json_date_take(destination, source, metadata)
}

fn swift_json_date_arena() !u64 {
	$if !arm64 {
		return error('iOS: JSON date strategy requires ARM64')
	}
	if ios_runtime == unsafe { nil } {
		return error('iOS: JSON date strategy outside runtime lifetime')
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_json_date_retired || ios_runtime.swift_concurrency_retired {
		return error('iOS: JSON date strategy outside runtime lifetime')
	}
	if ios_runtime.swift_json_date_arena != 0 { return ios_runtime.swift_json_date_arena }
	page := usize(C.getpagesize())
	arena := C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == unsafe { voidptr(-1) } {
		return error('iOS: cannot allocate JSON date strategy metadata')
	}
	base := u64(arena)
	data := base + u64(page)
	metadata := data + 16
	witness := data + 64
	descriptor := data + 192
	write32(base, 0x58000080)
	write32(base + 4, 0xd2800001)
	write32(base + 8, 0xd65f03c0)
	unsafe {
		*(&u64(base + 16)) = metadata
		*(&u64(metadata - 8)) = witness
		*(&u64(metadata)) = 0x201
		*(&u64(metadata + 8)) = descriptor
	}
	for i, function in [u64(unsafe { voidptr(swift_json_date_copy) }),
		u64(unsafe { voidptr(swift_json_date_destroy) }),
		u64(unsafe { voidptr(swift_json_date_copy) }),
		u64(unsafe { voidptr(swift_json_date_assign_copy) }),
		u64(unsafe { voidptr(swift_json_date_take) }),
		u64(unsafe { voidptr(swift_json_date_assign_take) }),
		u64(unsafe { voidptr(swift_json_date_single_get) }),
		u64(unsafe { voidptr(swift_json_date_single_store) })]! {
		unsafe { *(&u64(witness + u64(i * 8))) = function }
	}
	unsafe {
		*(&u64(witness + 64)) = 17
		*(&u64(witness + 72)) = 24
		*(&u64(witness + 88)) = u64(voidptr(swift_json_date_tag))
		*(&u64(witness + 96)) = u64(voidptr(swift_json_date_project))
		*(&u64(witness + 104)) = u64(voidptr(swift_json_date_inject))
	}
	write32(witness + 80, 0x00210007) // Non-POD, inline, bitwise-takable, enum witnesses.
	write32(witness + 84, 253)
	// Private nongeneric enum descriptor; reflection and Apple's layout-string
	// extensions are not exported. The ordinary VWT is self-contained.
	write32(descriptor, 0x52)
	swift_protocol_relative(descriptor + 4, data + 256)
	swift_protocol_relative(descriptor + 8, data + 304)
	swift_protocol_relative(descriptor + 12, base)
	write32(descriptor + 20, 2)
	write32(descriptor + 24, 4)
	swift_protocol_relative(data + 264, data + 280)
	C.memcpy(voidptr(data + 280), c'Foundation', 11)
	C.memcpy(voidptr(data + 304), c'DateEncodingStrategy', 21)
	C.__builtin___clear_cache(arena, voidptr(base + 24))
	if C.mprotect(arena, page, C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(voidptr(data), page, C.PROT_READ) != 0 {
		if C.munmap(arena, page * 2) != 0 {
			panic('iOS: cannot retire unsealed JSON date strategy')
		}
		return error('iOS: cannot seal JSON date strategy metadata')
	}
	ios_runtime.swift_json_date_arena = base
	return base
}

fn swift_json_date_symbol(symbol string) ?u64 {
	if symbol !in ['_$s10Foundation11JSONEncoderC20DateEncodingStrategyOMa',
		'_$s10Foundation11JSONEncoderC20DateEncodingStrategyOMn']! {
		return none
	}
	base := swift_json_date_arena() or { return none }
	return if symbol.ends_with('Ma') { base } else { base + u64(C.getpagesize()) + 192 }
}

fn swift_json_date_stop() {
	// Called with the runtime lock after array/heap users have drained, before
	// ARC support retires. No outstanding value or callback may retain this VWT.
	ios_runtime.swift_json_date_retired = true
	if ios_runtime.swift_json_date_arena == 0 { return }
	if C.munmap(voidptr(ios_runtime.swift_json_date_arena), usize(C.getpagesize()) * 2) != 0 {
		panic('iOS: cannot retire JSON date strategy metadata')
	}
	ios_runtime.swift_json_date_arena = 0
}
