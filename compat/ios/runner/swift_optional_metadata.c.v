// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftOptionalFailure {}

fn (_ &SwiftOptionalFailure) msg() string {
	return 'iOS: Optional requires live, complete, copyable inline Wrapped metadata (at most 24 bytes, alignment at most 8)'
}

fn (_ &SwiftOptionalFailure) code() int { return 1 }

__global swift_optional_failure_value = SwiftOptionalFailure{}

fn swift_optional_failure() IError { return unsafe { &swift_optional_failure_value } }

type SwiftOptionalStore = fn (u64, u32, u32, u64)

// Value witnesses borrow live caller-owned metadata and initialized spans.
// Every published specialization has validated Wrapped witnesses; no registry
// lock is held while user-defined Wrapped operations run.
fn swift_optional_tag(value u64, metadata u64) u32 {
	wrapped := read64(metadata + 16)
	get := unsafe { SwiftSequenceTag(voidptr(read64(read64(wrapped - 8) + 48))) }
	return get(value, 1, wrapped)
}

fn swift_optional_inject(value u64, tag u32, metadata u64) {
	wrapped := read64(metadata + 16)
	store := unsafe { SwiftOptionalStore(voidptr(read64(read64(wrapped - 8) + 56))) }
	store(value, tag, 1, wrapped)
}

fn swift_optional_project(_value u64, _metadata u64) {}

fn swift_optional_destroy(value u64, metadata u64) {
	if swift_optional_tag(value, metadata) != 0 { return }
	wrapped := read64(metadata + 16)
	destroy := unsafe { SwiftSequenceDestroy(voidptr(read64(read64(wrapped - 8) + 8))) }
	destroy(value, wrapped)
}

fn swift_optional_initialize(destination u64, source u64, metadata u64, taking bool) u64 {
	if swift_optional_tag(source, metadata) != 0 {
		C.memmove(voidptr(destination), voidptr(source), usize(read64(read64(metadata - 8) + 64)))
	} else {
		wrapped := read64(metadata + 16)
		call := unsafe {
			SwiftSequenceCopy(voidptr(read64(read64(wrapped - 8) + if taking {
				u64(32)
			} else {
				u64(16)
			})))
		}
		call(destination, source, wrapped)
		swift_optional_inject(destination, 0, metadata)
	}
	return destination
}

fn swift_optional_copy(destination u64, source u64, metadata u64) u64 {
	return swift_optional_initialize(destination, source, metadata, false)
}

fn swift_optional_take(destination u64, source u64, metadata u64) u64 {
	return swift_optional_initialize(destination, source, metadata, true)
}

fn swift_optional_assign(destination u64, source u64, metadata u64, taking bool) u64 {
	if destination == source { return destination }
	old_some := swift_optional_tag(destination, metadata) == 0
	new_some := swift_optional_tag(source, metadata) == 0
	wrapped := read64(metadata + 16)
	witness := read64(wrapped - 8)
	if old_some && new_some {
		call := unsafe {
			SwiftSequenceCopy(voidptr(read64(witness + if taking {
				u64(40)
			} else {
				u64(24)
			})))
		}
		call(destination, source, wrapped)
	} else if old_some {
		// Publish nil before a retiring payload can reenter the runtime. The
		// bounded stack temporary owns the old payload until destruction ends.
		temporary := u64(C.__builtin_alloca(24))
		move := unsafe { SwiftSequenceCopy(voidptr(read64(witness + 32))) }
		move(temporary, destination, wrapped)
		C.memmove(voidptr(destination), voidptr(source), usize(read64(read64(metadata - 8) + 64)))
		destroy := unsafe { SwiftSequenceDestroy(voidptr(read64(witness + 8))) }
		destroy(temporary, wrapped)
	} else {
		swift_optional_initialize(destination, source, metadata, taking)
	}
	return destination
}

fn swift_optional_assign_copy(destination u64, source u64, metadata u64) u64 {
	return swift_optional_assign(destination, source, metadata, false)
}

fn swift_optional_assign_take(destination u64, source u64, metadata u64) u64 {
	return swift_optional_assign(destination, source, metadata, true)
}

// Single-payload witnesses describe an enclosing enum whose payload is this
// Optional. Its remaining extra inhabitants exclude Wrapped's nil case.
// Match native UInt32 rounding/wrap, byte widths, and little-endian accesses.
fn swift_optional_extra_width(size u64, extra u32, cases u32) u32 {
	if cases <= extra { return 0 }
	if size >= 4 { return 1 }
	bits := u32(size * 8)
	mask := (u32(1) << bits) - u32(1)
	values := ((cases - extra + mask) >> bits) + u32(1)
	if values <= 1 { return 0 }
	if values <= 255 { return 1 }
	return if values < 65536 { u32(2) } else { u32(4) }
}

fn swift_optional_enum_get(value u64, cases u32, metadata u64) u32 {
	if cases == 0 { return 0 }
	witness := read64(metadata - 8)
	size := read64(witness + 64)
	extra := read32(witness + 84)
	mut tag := u32(0)
	for i in u32(0) .. swift_optional_extra_width(size, extra, cases) {
		tag |= u32(unsafe { *(&u8(value + size + i)) }) << (i * 8)
	}
	if tag != 0 {
		mut payload := u32(0)
		for i in u64(0) .. if size < 4 { size } else { u64(4) } {
			payload |= u32(unsafe { *(&u8(value + i)) }) << u32(i * 8)
		}
		return (if size < 4 { (tag - u32(1)) << u32(size * 8) } else { u32(0) } | payload) + extra + u32(1)
	}
	if extra == 0 { return 0 }
	wrapped := read64(metadata + 16)
	wrapped_witness := read64(wrapped - 8)
	get := unsafe { SwiftSequenceTag(voidptr(read64(wrapped_witness + 48))) }
	inhabitant := get(value, read32(wrapped_witness + 84), wrapped)
	return if inhabitant > 1 { inhabitant - u32(1) } else { u32(0) }
}

fn swift_optional_enum_store(value u64, which u32, cases u32, metadata u64) {
	witness := read64(metadata - 8)
	size := read64(witness + 64)
	extra := read32(witness + 84)
	width := swift_optional_extra_width(size, extra, cases)
	mut external := u32(0)
	if which > extra {
		bits := which - extra - u32(1)
		C.memset(voidptr(value), 0, usize(size))
		for i in u64(0) .. if size < 4 { size } else { u64(4) } {
			unsafe { *(&u8(value + i)) = u8(bits >> u32(i * 8)) }
		}
		external = if size < 4 { (bits >> u32(size * 8)) + u32(1) } else { u32(1) }
	}
	for i in u32(0) .. width {
		unsafe { *(&u8(value + size + i)) = u8(external >> (i * 8)) }
	}
	if which != 0 && which <= extra {
		wrapped := read64(metadata + 16)
		wrapped_witness := read64(wrapped - 8)
		store := unsafe { SwiftOptionalStore(voidptr(read64(wrapped_witness + 56))) }
		store(value, which + u32(1), read32(wrapped_witness + 84), wrapped)
	}
}

fn swift_optional_access_checked(_request u64, wrapped u64) !SwiftAssociatedMetadata {
	if ios_runtime == unsafe { nil } { return swift_optional_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_optional_retired || ios_runtime.swift_concurrency_retired {
		return swift_optional_failure()
	}
	if metadata := ios_runtime.swift_optional_metadata[wrapped] {
		return SwiftAssociatedMetadata{ metadata: metadata }
	}
	layout := swift_sequence_value_checked(wrapped) or {
		swift_optional_probe(wrapped, 1, 0, 0, 0, 0)
		return swift_optional_failure()
	}
	witness := read64(wrapped - 8)
	flags := read32(witness + 80)
	wrapped_extra := read32(witness + 84)
	size := layout.size + if wrapped_extra == 0 { u64(1) } else { u64(0) }
	if size > 24 || layout.alignment > 8 || flags & ~u32(0x022100ff) != 0 {
		swift_optional_probe(wrapped, 2, layout.size, layout.alignment, flags, wrapped_extra)
		return swift_optional_failure()
	}
	for offset in [u64(24), 40, 56]! {
		if read64(witness + offset) == 0 || read64(witness + offset) & 3 != 0 {
			swift_optional_probe(wrapped, 3, layout.size, layout.alignment, flags, wrapped_extra)
			return swift_optional_failure()
		}
	}
	base := swift_optional_metadata_arena_checked()!
	page := usize(C.getpagesize())
	allocation := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == voidptr(-1) { return swift_optional_failure() }
	metadata := u64(allocation) + 8
	optional_witness := u64(allocation) + 64
	unsafe {
		*(&u64(metadata - 8)) = optional_witness
		*(&u64(metadata)) = 0x202 // Optional has its own metadata kind.
		*(&u64(metadata + 8)) = base + u64(page) + 160
		*(&u64(metadata + 16)) = wrapped
	}
	for i, entry in [u64(unsafe { voidptr(swift_optional_copy) }),
		u64(unsafe { voidptr(swift_optional_destroy) }), u64(unsafe { voidptr(swift_optional_copy) }),
		u64(unsafe { voidptr(swift_optional_assign_copy) }),
		u64(unsafe { voidptr(swift_optional_take) }),
		u64(unsafe { voidptr(swift_optional_assign_take) }),
		u64(unsafe { voidptr(swift_optional_enum_get) }),
		u64(unsafe { voidptr(swift_optional_enum_store) })]! {
		unsafe { *(&u64(optional_witness + u64(i * 8))) = entry }
	}
	unsafe {
		*(&u64(optional_witness + 64)) = size
		*(&u64(optional_witness + 72)) = if size == 0 {
			u64(1)
		} else {
			(size + layout.alignment - 1) & ~(layout.alignment - 1)
		}
		*(&u64(optional_witness + 88)) = u64(voidptr(swift_optional_tag))
		*(&u64(optional_witness + 96)) = u64(voidptr(swift_optional_project))
		*(&u64(optional_witness + 104)) = u64(voidptr(swift_optional_inject))
	}
	write32(optional_witness + 80, flags | 0x00200000)
	write32(optional_witness + 84, if wrapped_extra > 0 { wrapped_extra - u32(1) } else { u32(0) })
	if C.mprotect(allocation, page, C.PROT_READ) != 0 {
		if C.munmap(allocation, page) != 0 {
			panic('iOS: cannot retire unsealed Optional metadata')
		}
		return swift_optional_failure()
	}
	ios_runtime.swift_optional_metadata[wrapped] = metadata
	return SwiftAssociatedMetadata{ metadata: metadata }
}

fn swift_optional_access(request u64, wrapped u64) SwiftAssociatedMetadata {
	return swift_optional_access_checked(request, wrapped) or { panic(err) }
}

fn swift_optional_instantiate(descriptor u64, arguments u64, pattern u64) u64 {
	base := swift_optional_metadata_arena_checked() or { panic(err) }
	data := base + u64(C.getpagesize())
	if descriptor != data + 160 || pattern != data + 272 || arguments == 0 {
		panic('iOS: invalid Optional metadata instantiation')
	}
	return swift_optional_access(0, read64(arguments)).metadata
}

fn swift_optional_metadata_arena_checked() !u64 {
	$if !arm64 {
		return swift_optional_failure()
	}
	if ios_runtime == unsafe { nil } { return swift_optional_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_optional_retired || ios_runtime.swift_concurrency_retired {
		return swift_optional_failure()
	}
	if ios_runtime.swift_optional_arena != 0 { return ios_runtime.swift_optional_arena }
	page := u64(C.getpagesize())
	arena := C.mmap(unsafe { nil }, usize(page * 3), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == voidptr(-1) { return swift_optional_failure() }
	base := u64(arena)
	data := base + page
	descriptor := data + 160
	for i, target in [u64(unsafe { voidptr(swift_optional_access) }),
		u64(unsafe { voidptr(swift_optional_instantiate) })]! {
		address := base + u64(i * 32)
		write32(address, 0x58000050)
		write32(address + 4, 0xd61f0200)
		unsafe { *(&u64(address + 8)) = target }
	}
	write32(descriptor, 0xd2) // Unique generic enum; one payload case, one empty case.
	swift_protocol_relative(descriptor + 4, data + 224)
	swift_protocol_relative(descriptor + 8, data + 248)
	swift_protocol_relative(descriptor + 12, base)
	write32(descriptor + 20, 1)
	write32(descriptor + 24, 1)
	swift_protocol_relative(descriptor + 28, base + page * 2)
	swift_protocol_relative(descriptor + 32, data + 272)
	write32(descriptor + 36, 1)
	write32(descriptor + 40, 1)
	write32(descriptor + 44, 0x80)
	swift_protocol_relative(data + 232, data + 240)
	C.memcpy(voidptr(data + 240), c'Swift', 6)
	C.memcpy(voidptr(data + 248), c'Optional', 9)
	swift_protocol_relative(data + 272, base + 32)
	// Optional generic pattern; value witnesses are computed per Wrapped.
	write32(data + 280, 0x40400000)
	C.__builtin___clear_cache(arena, voidptr(base + 48))
	if C.mprotect(arena, usize(page), C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(voidptr(data), usize(page), C.PROT_READ) != 0 {
		if C.munmap(arena, usize(page * 3)) != 0 {
			panic('iOS: cannot retire unsealed Optional descriptor')
		}
		return swift_optional_failure()
	}
	ios_runtime.swift_optional_arena = base
	return base
}

fn swift_optional_symbol(symbol string) ?u64 {
	if symbol !in ['_$sSqMa', '_$sSqMn']! { return none }
	base := swift_optional_metadata_arena_checked() or { return none }
	return if symbol == '_$sSqMa' { base } else { base + u64(C.getpagesize()) + 160 }
}

fn swift_optional_stop() {
	// Metadata users/typed owners have drained before this locked retirement.
	ios_runtime.swift_optional_retired = true
	swift_optional_decoding_stop()
	swift_optional_encoding_stop()
	page := usize(C.getpagesize())
	for _, metadata in ios_runtime.swift_optional_metadata {
		if C.munmap(voidptr(metadata - 8), page) != 0 {
			panic('iOS: cannot retire Optional metadata')
		}
	}
	unsafe { ios_runtime.swift_optional_metadata.free() }
	if ios_runtime.swift_optional_arena != 0 {
		if C.munmap(voidptr(ios_runtime.swift_optional_arena), page * 3) != 0 {
			panic('iOS: cannot retire Optional descriptor')
		}
		ios_runtime.swift_optional_arena = 0
	}
}
