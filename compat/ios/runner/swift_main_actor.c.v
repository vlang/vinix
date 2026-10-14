// SPDX-License-Identifier: GPL-2.0-or-later
module main

// MainActor.shared is a static immortal class reference, not an allocated
// actor instance. Native Swift initializes its two-word header once and ARC
// leaves the measured 0x80000004ffffffff refcount word unchanged. Vinix seals
// that header with the nominal metadata; no mutable cache or heap owner is
// needed. Actor conformance/executor scheduling remains a separate ABI.
const swift_main_actor_immortal = u64(0x80000004ffffffff)

fn swift_main_actor_arena() !u64 {
	$if !arm64 { return error('iOS: MainActor metadata requires ARM64') }
	if ios_runtime == unsafe { nil } { return error('iOS: MainActor outside runtime lifetime') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_main_actor_retired || ios_runtime.swift_concurrency_retired {
		return error('iOS: MainActor outside runtime lifetime')
	}
	if ios_runtime.swift_main_actor_arena != 0 { return ios_runtime.swift_main_actor_arena }
	page := u64(C.getpagesize())
	arena := C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == unsafe { voidptr(-1) } { return error('iOS: cannot allocate MainActor metadata') }
	base := u64(arena)
	data := base + page
	metadata := data + 24
	descriptor := data + 128
	module_descriptor := data + 192
	owner := data + 512
	// Complete nongeneric MetadataResponse, request-independent x0/x1.
	write32(base,0x58000080)
	write32(base + 4,0xd2800001)
	write32(base + 8,0xd65f03c0)
	unsafe { *(&u64(base + 16)) = metadata }
	// shared's metatype context x20 is unused for this final class. Return
	// the canonical immortal reference, preserving x20/x21 and all owners.
	write32(base + 32,0x58000080)
	write32(base + 36,0xd65f03c0)
	unsafe { *(&u64(base + 48)) = owner }
	// A separately allocated class instance still has a real deallocating
	// destructor (Self x20), taking the measured 16-byte / alignment-8 layout.
	for i, instruction in [u32(0xaa1403e0),0xd2800201,0xd28000e2,0x58000070,0xd61f0200]! {
		write32(base + 64 + u64(i * 4),instruction)
	}
	unsafe { *(&u64(base + 88)) = u64(voidptr(swift_heap_deallocate)) }
	unsafe {
		*(&u64(metadata - 16)) = base + 64
		*(&u64(metadata - 8)) = swift_unknown_value_witnesses()
		*(&u64(metadata + 32)) = 2 // Swift class metadata, without ObjC registration.
		*(&u64(metadata + 40)) = 2 // Native ARC, instance address point zero.
		*(&u64(metadata + 48)) = 0x700000010 // Instance size 16, alignment mask 7.
		*(&u64(metadata + 56)) = 0x1800000068 // Three negative and ten positive words.
		*(&u64(metadata + 64)) = descriptor
		*(&u64(owner - 8)) = u64(-1)
		*(&u64(owner)) = metadata
		*(&u64(owner + 8)) = swift_main_actor_immortal
	}
	write32(descriptor,0x50) // Class, unique, nongeneric, no reflection/vtable tail.
	swift_protocol_relative(descriptor + 4,module_descriptor)
	swift_protocol_relative(descriptor + 8,data + 224)
	swift_protocol_relative(descriptor + 12,base)
	write32(descriptor + 24,3)
	write32(descriptor + 28,10)
	swift_protocol_relative(module_descriptor + 8,data + 216)
	C.memcpy(voidptr(data + 216),c'Swift',6)
	C.memcpy(voidptr(data + 224),c'MainActor',10)
	C.__builtin___clear_cache(arena,voidptr(base + 96))
	if C.mprotect(arena,usize(page),C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(voidptr(data),usize(page),C.PROT_READ) != 0 {
		if C.munmap(arena,usize(page * 2)) != 0 { panic('iOS: cannot retire unsealed MainActor metadata') }
		return error('iOS: cannot seal MainActor metadata')
	}
	ios_runtime.swift_main_actor_arena = base
	return base
}

// Call under the runtime registry lock. Compare identity before inspecting
// any storage, so foreign/protected/retired pointers are never dereferenced.
fn swift_main_actor_is_singleton_locked(owner u64) bool {
	base := ios_runtime.swift_main_actor_arena
	return base != 0 && !ios_runtime.swift_main_actor_retired
		&& owner == base + u64(C.getpagesize()) + 512
}

fn swift_main_actor_symbol(symbol string) !u64 {
	base := swift_main_actor_arena()!
	return match symbol {
		'_$sScMMa' { base }
		'_$sScMMn' { base + u64(C.getpagesize()) + 128 }
		'_$sScM6sharedScMvgZ' { base + 32 }
		else { return error('iOS: unsupported MainActor symbol') }
	}
}

fn swift_main_actor_stop() {
	// Arrays and heap owners have drained; retire before their borrowed VWT
	// and ARC adapters disappear. No destructor is run for static storage.
	if ios_runtime.swift_main_actor_arena != 0 {
		if C.munmap(voidptr(ios_runtime.swift_main_actor_arena),usize(C.getpagesize()) * 2) != 0 {
			panic('iOS: cannot retire MainActor metadata')
		}
		ios_runtime.swift_main_actor_arena = 0
	}
	ios_runtime.swift_main_actor_retired = true
}
