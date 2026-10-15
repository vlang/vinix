// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The base encoder construction path used by Fortnite: Ma, allocObject,
// then the initializing constructor with borrowed Self in x20. This private
// native-ARC profile owns default options and an independent lock context.
// Encoding, option mutation, subclassing and ObjC exposure need their own
// implementations; every unimplemented virtual entry fails explicitly.
// Destruction owns only the default options installed here. Option setters
// cannot mutate this profile until their ownership paths are implemented.
const swift_json_encoder_size = u64(144)

fn swift_json_encoder_empty_locked(owner u64) bool {
	base := ios_runtime.swift_json_encoder_arena
	return base != 0 && !ios_runtime.swift_json_encoder_retired
		&& owner == base + u64(C.getpagesize()) + 1024
}

fn swift_json_encoder_initialize_checked(owner u64) !u64 {
	if ios_runtime == unsafe { nil } { return error('iOS: JSONEncoder outside runtime lifetime') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	base := ios_runtime.swift_json_encoder_arena
	if base == 0 || ios_runtime.swift_json_encoder_retired {
		return error('iOS: JSONEncoder outside runtime lifetime')
	}
	// Establish ownership and extent before reading any supplied pointer.
	storage := ios_runtime.swift_heap[owner] or { return error('iOS: JSONEncoder requires allocated Self') }
	data := base + u64(C.getpagesize())
	if storage.metadata != data + 24 || storage.size != swift_json_encoder_size || storage.mask != 7
		|| storage.deiniting || owner in ios_runtime.swift_json_encoders
		|| read64(owner) != storage.metadata || C.ios_load_pointer(unsafe { &u64(owner + 8) }) != 3 {
		return error('iOS: JSONEncoder requires unique uninitialized base Self')
	}
	child := swift_heap_allocate(data + 1216, 20, 7)
	write32(child + 16, 0)
	// Native writes 25 bytes of formatting/date options, preserving the seven
	// enum-padding bytes, then the remaining default options and owned lock.
	C.memset(voidptr(owner + 16), 0, 25)
	unsafe { *(&u8(owner + 40)) = 2 } // Date: deferredToDate.
	C.memset(voidptr(owner + 48), 0, 80)
	unsafe {
		*(&u64(owner + 48)) = 1 // Data: base64.
		*(&u64(owner + 128)) = data + 1024 // Immortal empty userInfo Dictionary.
		*(&u64(owner + 136)) = child
	}
	ios_runtime.swift_json_encoders[owner] = child
	return owner
}

fn swift_json_encoder_initialize(owner u64) u64 {
	return swift_json_encoder_initialize_checked(owner) or { panic(err) }
}

fn swift_json_encoder_destroy(owner u64) {
	C.ios_objc_initialize_lock()
	child := ios_runtime.swift_json_encoders[owner] or { panic('iOS: uninitialized JSONEncoder destruction') }
	storage := ios_runtime.swift_heap[owner] or { panic('iOS: missing JSONEncoder owner') }
	if !storage.deiniting || read64(owner + 136) != child {
		panic('iOS: invalid JSONEncoder destruction')
	}
	ios_runtime.swift_json_encoders.delete(owner)
	C.ios_objc_initialize_unlock()
	// Retire the registry entry before callbacks and never read freed Self.
	swift_release(child)
	swift_heap_deallocate(owner, swift_json_encoder_size, 7)
}

fn swift_json_encoder_lock_destroy(owner u64) {
	swift_heap_deallocate(owner, 20, 7)
}

fn swift_json_encoder_unsupported() {
	panic('iOS: JSONEncoder encoding/options/subclass methods are not implemented')
}

fn swift_json_encoder_arena() !u64 {
	$if !arm64 {
		return error('iOS: JSONEncoder requires ARM64')
	}
	if ios_runtime == unsafe { nil } { return error('iOS: JSONEncoder outside runtime lifetime') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_json_encoder_retired || ios_runtime.swift_concurrency_retired {
		return error('iOS: JSONEncoder outside runtime lifetime')
	}
	if ios_runtime.swift_json_encoder_arena != 0 { return ios_runtime.swift_json_encoder_arena }
	page := u64(C.getpagesize())
	arena := C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == unsafe { voidptr(-1) } { return error('iOS: cannot allocate JSONEncoder metadata') }
	base := u64(arena)
	data := base + page
	metadata := data + 24
	descriptor := data + 512
	// Request-independent complete MetadataResponse in x0/x1.
	write32(base, 0x58000080)
	write32(base + 4, 0xd2800001)
	write32(base + 8, 0xd65f03c0)
	unsafe { *(&u64(base + 16)) = metadata }
	swift_dispatch_bridge(base + 32, 0xaa1403e0, 0xd503201f, u64(voidptr(swift_json_encoder_initialize)))
	swift_dispatch_bridge(base + 64, 0xaa1403e0, 0xd503201f, u64(voidptr(swift_json_encoder_destroy)))
	swift_dispatch_bridge(base + 96, 0xaa1403e0, 0xd503201f, u64(voidptr(swift_json_encoder_lock_destroy)))
	swift_dispatch_bridge(base + 128, 0xd503201f, 0xd503201f, u64(voidptr(swift_json_encoder_unsupported)))
	unsafe {
		*(&u64(metadata - 16)) = base + 64
		*(&u64(metadata - 8)) = swift_unknown_value_witnesses()
		*(&u64(metadata + 32)) = 2 // Swift metadata; no ObjC registration.
		*(&u64(metadata + 40)) = 6 // Native ARC, instance address point zero.
		*(&u64(metadata + 48)) = 0x700000090 // Instance 144 bytes, alignment eight.
		*(&u64(metadata + 56)) = 0x1800000148 // Three negative, 38 positive words.
		*(&u64(metadata + 64)) = descriptor
		*(&u64(metadata + 80)) = 16
		*(&u64(metadata + 88)) = 136
	}
	for slot in u64(12) .. 38 {
		unsafe { *(&u64(metadata + slot * 8)) = base + 128 }
	}
	// Nongeneric class descriptor and vtable shape, with a private reflection
	// profile. No resilient-superclass/ObjC stub or borrowed native addresses.
	write32(descriptor, 0x80000050)
	swift_protocol_relative(descriptor + 4, data + 832)
	swift_protocol_relative(descriptor + 8, data + 864)
	swift_protocol_relative(descriptor + 12, base)
	write32(descriptor + 24, 3)
	write32(descriptor + 28, 38)
	write32(descriptor + 32, 28)
	write32(descriptor + 36, 2)
	write32(descriptor + 40, 10)
	write32(descriptor + 44, 12)
	write32(descriptor + 48, 26)
	for i in u64(0) .. 26 {
		write32(descriptor + 52 + i * 8, 0x10)
		swift_protocol_relative(descriptor + 56 + i * 8, base + 128)
	}
	swift_protocol_relative(data + 840, data + 852)
	C.memcpy(voidptr(data + 852), c'Foundation', 11)
	C.memcpy(voidptr(data + 864), c'JSONEncoder', 12)
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
			panic('iOS: cannot retire unsealed JSONEncoder metadata')
		}
		return error('iOS: cannot seal JSONEncoder metadata')
	}
	ios_runtime.swift_json_encoder_arena = base
	return base
}

fn swift_json_encoder_symbol(symbol string) ?u64 {
	if symbol !in ['_$s10Foundation11JSONEncoderCACycfc', '_$s10Foundation11JSONEncoderCMa',
		'_$s10Foundation11JSONEncoderCMn']! {
		return none
	}
	base := swift_json_encoder_arena() or { return none }
	return match symbol {
		'_$s10Foundation11JSONEncoderCACycfc' { base + 32 }
		'_$s10Foundation11JSONEncoderCMa' { base }
		else { base + u64(C.getpagesize()) + 512 }
	}
}

fn swift_json_encoder_stop() {
	if ios_runtime.swift_json_encoders.len != 0 {
		panic('iOS: JSONEncoder owners still live at shutdown')
	}
	unsafe { ios_runtime.swift_json_encoders.free() }
	ios_runtime.swift_json_encoder_retired = true
	if ios_runtime.swift_json_encoder_arena == 0 { return }
	if C.munmap(voidptr(ios_runtime.swift_json_encoder_arena), usize(C.getpagesize()) * 2) != 0 {
		panic('iOS: cannot retire JSONEncoder metadata')
	}
	ios_runtime.swift_json_encoder_arena = 0
}
