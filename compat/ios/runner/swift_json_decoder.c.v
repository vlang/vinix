// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The base decoder construction path used by Fortnite: Ma, allocObject,
// then the initializing constructor with borrowed Self in x20. This private
// native-ARC profile owns default options and an independent lock context.
// Decoding, option mutation, subclassing and ObjC exposure need their own
// implementations; every unimplemented virtual entry fails explicitly.
const swift_json_decoder_size = u64(160)

fn swift_json_decoder_empty_locked(owner u64) bool {
	base := ios_runtime.swift_json_decoder_arena
	return base != 0 && !ios_runtime.swift_json_decoder_retired
		&& owner == base + u64(C.getpagesize()) + 1024
}

fn swift_json_decoder_initialize_checked(owner u64) !u64 {
	if ios_runtime == unsafe { nil } { return error('iOS: JSONDecoder outside runtime lifetime') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	base := ios_runtime.swift_json_decoder_arena
	if base == 0 || ios_runtime.swift_json_decoder_retired {
		return error('iOS: JSONDecoder outside runtime lifetime')
	}
	// Establish ownership and extent before reading any supplied pointer.
	storage := ios_runtime.swift_heap[owner] or { return error('iOS: JSONDecoder requires allocated Self') }
	data := base + u64(C.getpagesize())
	if storage.metadata != data + 24 || storage.size != swift_json_decoder_size || storage.mask != 7
		|| storage.deiniting || owner in ios_runtime.swift_json_decoders
		|| read64(owner) != storage.metadata || C.ios_load_pointer(unsafe { &u64(owner + 8) }) != 3 {
		return error('iOS: JSONDecoder requires unique uninitialized base Self')
	}
	child := swift_heap_allocate(data + 1216, 20, 7)
	write32(child + 16, 0)
	// Native initializes these exact extents, leaving enum/bool padding alone.
	// The private top-level JSON5 key is an immutable large String literal.
	unsafe {
		*(&u64(owner + 16)) = 0xd000000000000021
		*(&u64(owner + 24)) = 0x8000000000000000 | (data + 896 - 32)
	}
	C.memset(voidptr(owner + 32), 0, 17)
	unsafe { *(&u8(owner + 48)) = 2 } // Date: deferredToDate, nonpayload case.
	C.memset(voidptr(owner + 56), 0, 88)
	unsafe {
		*(&u64(owner + 56)) = 1 // Data: base64, nonpayload case.
		*(&u64(owner + 136)) = data + 1024 // Empty userInfo Dictionary singleton.
		*(&u8(owner + 144)) = 0 // JSON5 disabled.
		*(&u64(owner + 152)) = child
	}
	ios_runtime.swift_json_decoders[owner] = child
	return owner
}

fn swift_json_decoder_initialize(owner u64) u64 {
	return swift_json_decoder_initialize_checked(owner) or { panic(err) }
}

fn swift_json_decoder_destroy(owner u64) {
	C.ios_objc_initialize_lock()
	child := ios_runtime.swift_json_decoders[owner] or { panic('iOS: uninitialized JSONDecoder destruction') }
	storage := ios_runtime.swift_heap[owner] or { panic('iOS: missing JSONDecoder owner') }
	if !storage.deiniting || read64(owner + 152) != child {
		panic('iOS: invalid JSONDecoder destruction')
	}
	ios_runtime.swift_json_decoders.delete(owner)
	C.ios_objc_initialize_unlock()
	// Retire the registry entry before callbacks and never read freed Self.
	swift_release(child)
	swift_heap_deallocate(owner, swift_json_decoder_size, 7)
}

fn swift_json_decoder_lock_destroy(owner u64) {
	swift_heap_deallocate(owner, 20, 7)
}

fn swift_json_decoder_unsupported() {
	panic('iOS: JSONDecoder decoding/options/subclass methods are not implemented')
}

fn swift_json_decoder_arena() !u64 {
	$if !arm64 {
		return error('iOS: JSONDecoder requires ARM64')
	}
	if ios_runtime == unsafe { nil } { return error('iOS: JSONDecoder outside runtime lifetime') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_json_decoder_retired || ios_runtime.swift_concurrency_retired {
		return error('iOS: JSONDecoder outside runtime lifetime')
	}
	if ios_runtime.swift_json_decoder_arena != 0 { return ios_runtime.swift_json_decoder_arena }
	page := u64(C.getpagesize())
	arena := C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == unsafe { voidptr(-1) } { return error('iOS: cannot allocate JSONDecoder metadata') }
	base := u64(arena)
	data := base + page
	metadata := data + 24
	descriptor := data + 512
	// Request-independent complete MetadataResponse in x0/x1.
	write32(base, 0x58000080)
	write32(base + 4, 0xd2800001)
	write32(base + 8, 0xd65f03c0)
	unsafe { *(&u64(base + 16)) = metadata }
	swift_dispatch_bridge(base + 32, 0xaa1403e0, 0xd503201f, u64(voidptr(swift_json_decoder_initialize)))
	swift_dispatch_bridge(base + 64, 0xaa1403e0, 0xd503201f, u64(voidptr(swift_json_decoder_destroy)))
	swift_dispatch_bridge(base + 96, 0xaa1403e0, 0xd503201f, u64(voidptr(swift_json_decoder_lock_destroy)))
	swift_dispatch_bridge(base + 128, 0xd503201f, 0xd503201f, u64(voidptr(swift_json_decoder_unsupported)))
	unsafe {
		*(&u64(metadata - 16)) = base + 64
		*(&u64(metadata - 8)) = swift_unknown_value_witnesses()
		*(&u64(metadata + 32)) = 2 // Swift metadata; no ObjC registration.
		*(&u64(metadata + 40)) = 6 // Native ARC, instance address point zero.
		*(&u64(metadata + 48)) = 0x7000000a0 // Instance 160 bytes, alignment eight.
		*(&u64(metadata + 56)) = 0x1800000178 // Three negative, 44 positive words.
		*(&u64(metadata + 64)) = descriptor
		*(&u64(metadata + 80)) = 16
		*(&u64(metadata + 88)) = 32
		*(&u64(metadata + 96)) = 152
	}
	for slot in u64(13) .. 44 {
		unsafe { *(&u64(metadata + slot * 8)) = base + 128 }
	}
	// Nongeneric class descriptor and vtable shape, with a private reflection
	// profile. No resilient-superclass/ObjC stub or borrowed native addresses.
	write32(descriptor, 0x80000050)
	swift_protocol_relative(descriptor + 4, data + 832)
	swift_protocol_relative(descriptor + 8, data + 864)
	swift_protocol_relative(descriptor + 12, base)
	write32(descriptor + 24, 3)
	write32(descriptor + 28, 44)
	write32(descriptor + 32, 34)
	write32(descriptor + 36, 3)
	write32(descriptor + 40, 10)
	write32(descriptor + 44, 13)
	write32(descriptor + 48, 31)
	for i in u64(0) .. 31 {
		write32(descriptor + 52 + i * 8, 0x10)
		swift_protocol_relative(descriptor + 56 + i * 8, base + 128)
	}
	swift_protocol_relative(data + 840, data + 852)
	C.memcpy(voidptr(data + 852), c'Foundation', 11)
	C.memcpy(voidptr(data + 864), c'JSONDecoder', 12)
	C.memcpy(voidptr(data + 896), c'_NSAssumesTopLevelDictionaryJSON5', 34)
	// Canonical empty Dictionary storage: zero count/capacity/seed, one
	// sentinel bucket and an occupied padding bitmap. ARC is immortal.
	unsafe {
		*(&u64(data + 1024)) = data + 1152
		*(&u64(data + 1032)) = 0x80000004ffffffff
		*(&u64(data + 1072)) = 1
		*(&u64(data + 1080)) = 1
		*(&u64(data + 1088)) = ~u64(1)
		*(&u64(data + 1152)) = 0x500 // Private immortal heap context.
		*(&u64(data + 1200)) = base + 96
		*(&u64(data + 1216)) = 0x400 // Owned lock heap context.
	}
	C.__builtin___clear_cache(arena, voidptr(base + 152))
	if C.mprotect(arena, usize(page), C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(voidptr(data), usize(page), C.PROT_READ) != 0 {
		if C.munmap(arena, usize(page * 2)) != 0 {
			panic('iOS: cannot retire unsealed JSONDecoder metadata')
		}
		return error('iOS: cannot seal JSONDecoder metadata')
	}
	ios_runtime.swift_json_decoder_arena = base
	return base
}

fn swift_json_decoder_symbol(symbol string) ?u64 {
	if symbol !in ['_$s10Foundation11JSONDecoderCACycfc', '_$s10Foundation11JSONDecoderCMa',
		'_$s10Foundation11JSONDecoderCMn']! {
		return none
	}
	base := swift_json_decoder_arena() or { return none }
	return match symbol {
		'_$s10Foundation11JSONDecoderCACycfc' { base + 32 }
		'_$s10Foundation11JSONDecoderCMa' { base }
		else { base + u64(C.getpagesize()) + 512 }
	}
}

fn swift_json_decoder_stop() {
	if ios_runtime.swift_json_decoders.len != 0 {
		panic('iOS: JSONDecoder owners still live at shutdown')
	}
	unsafe { ios_runtime.swift_json_decoders.free() }
	ios_runtime.swift_json_decoder_retired = true
	if ios_runtime.swift_json_decoder_arena == 0 { return }
	if C.munmap(voidptr(ios_runtime.swift_json_decoder_arena), usize(C.getpagesize()) * 2) != 0 {
		panic('iOS: cannot retire JSONDecoder metadata')
	}
	ios_runtime.swift_json_decoder_arena = 0
}
